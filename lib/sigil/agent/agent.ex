defmodule Sigil.Agent do
  @moduledoc """
  The core agent orchestrator — a GenServer that runs the
  think → act → observe loop.

  ## Defining an Agent

      defmodule MyAgent do
        use Sigil.Agent

        @impl true
        def init_agent(opts) do
          %{
            llm: {Sigil.LLM.Anthropic, model: "claude-sonnet-4-20250514"},
            tools: [MyApp.Tools.Search, MyApp.Tools.SendEmail],
            system: "You are a helpful assistant.",
            memory: :progressive,
            max_turns: 10
          }
        end

        # Optional callbacks for customization:

        @impl true
        def before_call(messages, state) do
          # Inject context before each LLM call
          {messages, state}
        end

        @impl true
        def on_tool_result(tool_name, result, state) do
          # Inspect/transform tool results before the AI sees them
          {result, state}
        end

        @impl true
        def on_complete(response, state) do
          # Save results, update memory, etc.
          {:ok, response, state}
        end

        @impl true
        def on_agent_message(message, state) do
          # Handle messages from other agents in a team
          {:noreply, state}
        end
      end

  ## Starting an Agent

      {:ok, pid} = Sigil.Agent.start(MyAgent, api_key: "sk-...")
      {:ok, response} = Sigil.Agent.chat(pid, "Hello!")

  ## Resuming an Agent

      {:ok, pid} = Sigil.Agent.resume(run_id)
      {:ok, response} = Sigil.Agent.chat(pid, "Continue where you left off")

  ## Lifecycle

  1. `init_agent/1` — Configure LLM, tools, memory, system prompt
  2. `before_call/2` — Inject context before each LLM call
  3. LLM call — AI decides what to do
  4. Tool execution — Run the selected tool
  5. `on_tool_result/3` — Inspect result before AI sees it
  6. Loop 3-5 until AI is done or max turns reached
  7. `on_complete/2` — Final hook for saving results

  All steps emit events to the `Sigil.Agent.EventStore` for
  full audit trail and decision replay. State is periodically
  checkpointed for durable execution across restarts.
  """

  use GenServer

  alias Sigil.Agent.{EventStore, Checkpoint, Telemetry}
  alias Sigil.Agent.State, as: S
  alias Sigil.Memory.{Budget, Context, Tokenizer}

  @type agent_config :: %{
          llm: {module(), keyword()},
          tools: [module()],
          system: String.t(),
          memory: atom(),
          max_turns: pos_integer()
        }

  # Callbacks for agent modules

  @doc "Configure the agent. Returns a config map."
  @callback init_agent(opts :: keyword()) :: agent_config()

  @doc "Hook called before each LLM call. Can modify messages."
  @callback before_call(messages :: list(), state :: map()) ::
              {list(), map()}

  @doc "Hook called after a tool returns a result."
  @callback on_tool_result(tool_name :: String.t(), result :: term(), state :: map()) ::
              {term(), map()}

  @doc "Hook called when the agent completes (no more tool calls)."
  @callback on_complete(response :: map(), state :: map()) ::
              {:ok, map(), map()}

  @doc "Hook called when a message is received from another agent."
  @callback on_agent_message(message :: map(), state :: map()) ::
              {:reply, term(), map()} | {:noreply, map()}

  @optional_callbacks [before_call: 2, on_tool_result: 3, on_complete: 2, on_agent_message: 2]

  defmacro __using__(_opts) do
    quote do
      @behaviour Sigil.Agent

      @impl Sigil.Agent
      def before_call(messages, state), do: {messages, state}

      @impl Sigil.Agent
      def on_tool_result(_tool_name, result, state), do: {result, state}

      @impl Sigil.Agent
      def on_complete(response, state), do: {:ok, response, state}

      @impl Sigil.Agent
      def on_agent_message(_message, state), do: {:noreply, state}

      defoverridable before_call: 2, on_tool_result: 3, on_complete: 2, on_agent_message: 2
    end
  end

  # Client API

  @doc "Start an agent under the Runner supervisor."
  def start(agent_module, opts \\ []) do
    DynamicSupervisor.start_child(
      Sigil.Agent.Runner,
      {__MODULE__, {agent_module, opts}}
    )
  end

  @doc "Start an agent linked to the calling process."
  def start_link({:resume, state}) do
    GenServer.start_link(__MODULE__, {:resume, state})
  end

  def start_link({agent_module, opts}) do
    GenServer.start_link(__MODULE__, {agent_module, opts})
  end

  @doc """
  Resume an agent from its last checkpoint.

  Loads the latest checkpoint for the given run_id, replays any
  events since the checkpoint, and starts a new GenServer with
  the reconstructed state.

  ## Options

  - `:checkpoint_id` — Resume from a specific checkpoint (default: latest)
  - `:agent_module` — Override the agent module (required if not in checkpoint)
  """
  def resume(run_id, opts \\ []) do
    checkpoint_result =
      case Keyword.get(opts, :checkpoint_id) do
        nil -> Checkpoint.latest(run_id)
        id -> Checkpoint.load(id)
      end

    case checkpoint_result do
      {:ok, checkpoint} ->
        # Reconstruct the agent module from checkpoint config
        agent_module =
          Keyword.get(opts, :agent_module) ||
            resolve_module(checkpoint.config["module"] || checkpoint.state["module"])

        if agent_module do
          # Rebuild the state
          config = agent_module.init_agent(opts)

          state = %S{
            module: agent_module,
            config: config,
            messages: checkpoint.messages,
            opts: opts,
            turn_count: checkpoint.state["turn_count"] || 0,
            status: :ready,
            run_id: run_id,
            event_sequence: checkpoint.sequence,
            budget: build_budget(config),
            checkpoint_policy: Checkpoint.default_policy(),
            summaries_cache: checkpoint.state["summaries_cache"] || %{},
            resumed_from: checkpoint.id
          }

          # Replay events since checkpoint
          {:ok, events} = EventStore.replay_from(run_id, checkpoint.sequence + 1)
          state = apply_replay_events(state, events)

          # Emit resume event
          emit_event(state, :agent_resumed, %{
            checkpoint_id: checkpoint.id,
            checkpoint_sequence: checkpoint.sequence,
            events_replayed: length(events)
          })

          DynamicSupervisor.start_child(
            Sigil.Agent.Runner,
            {__MODULE__, {:resume, state}}
          )
        else
          {:error, :agent_module_required}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Send a message and get a response (synchronous)."
  def chat(pid, message, timeout \\ 120_000) do
    GenServer.call(pid, {:chat, message}, timeout)
  end

  @doc "Send a message and stream chunks back to the caller."
  def stream(pid, message) do
    GenServer.cast(pid, {:stream, message, self()})
  end

  @doc "Get the current agent state."
  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  @doc "Force a checkpoint of the current agent state."
  def checkpoint(pid) do
    GenServer.call(pid, :checkpoint)
  end

  @doc "Get the event history for the agent's current run."
  def history(pid, opts \\ []) do
    GenServer.call(pid, {:history, opts})
  end

  @doc "Get the run_id for the current agent."
  def run_id(pid) do
    GenServer.call(pid, :run_id)
  end

  @doc "Stop the agent."
  def stop(pid) do
    GenServer.stop(pid, :normal)
  end

  # GenServer implementation

  @impl true
  def init({:resume, %S{} = state}) do
    {:ok, %S{state | status: :ready}}
  end

  def init({agent_module, opts}) do
    config = agent_module.init_agent(opts)
    validate_config!(config, agent_module)

    state = %S{
      module: agent_module,
      config: config,
      messages: [],
      opts: opts,
      turn_count: 0,
      status: :ready,
      run_id: Ecto.UUID.generate(),
      event_sequence: 0,
      budget: build_budget(config),
      checkpoint_policy: Map.get(config, :checkpoint_policy, Checkpoint.default_policy()),
      summaries_cache: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:chat, message}, _from, state) do
    user_message = %{role: "user", content: message}
    messages = state.messages ++ [user_message]

    # Emit user message event
    state =
      emit_event(state, :user_message, %{
        content: message,
        token_count: Tokenizer.count(message)
      })

    case run_loop(messages, state) do
      {:ok, response, new_state} ->
        {:reply, {:ok, response}, new_state}

      {:error, reason, new_state} ->
        {:reply, {:error, reason}, new_state}
    end
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:checkpoint, _from, state) do
    case do_checkpoint(state) do
      {:ok, checkpoint} ->
        {:reply, {:ok, checkpoint.id}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:history, opts}, _from, state) do
    {:reply, EventStore.replay(state.run_id, opts), state}
  end

  def handle_call(:run_id, _from, state) do
    {:reply, state.run_id, state}
  end

  @impl true
  def handle_cast({:stream, message, caller_pid}, state) do
    user_message = %{role: "user", content: message}
    messages = state.messages ++ [user_message]

    state =
      emit_event(state, :user_message, %{
        content: message,
        token_count: Tokenizer.count(message)
      })

    # Run in a task to not block the GenServer
    Task.start(fn ->
      case run_loop(messages, state, caller_pid) do
        {:ok, response, _new_state} ->
          send(caller_pid, {:sigil_complete, response})

        {:error, reason, _new_state} ->
          send(caller_pid, {:sigil_error, reason})
      end
    end)

    {:noreply, %{state | status: :running}}
  end

  @impl true
  def handle_info({:sigil_agent_message, message}, state) do
    state =
      emit_event(state, :agent_message_received, %{
        from: inspect(message.from),
        content: inspect(message.content)
      })

    case state.module.on_agent_message(message, state) do
      {:reply, reply, new_state} ->
        if message.from && is_pid(message.from) do
          send(message.from, {:sigil_agent_message, %{message | content: reply, from: self()}})
        end

        {:noreply, new_state}

      {:noreply, new_state} ->
        {:noreply, new_state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Core agent loop

  defp run_loop(messages, state, stream_to \\ nil) do
    {adapter, llm_opts} = state.config.llm
    tools = state.config[:tools] || []
    system = state.config[:system]
    max_turns = state.config[:max_turns] || 10
    memory_strategy = state.config[:memory] || :sliding_window

    # Update budget with current system prompt and tools
    budget =
      state.budget
      |> Budget.reserve(:system, system || "")
      |> Budget.reserve(:tools, tools)

    # Compact messages if needed (budget-aware)
    compact_opts = [
      strategy: memory_strategy,
      budget: budget,
      summaries_cache: state.summaries_cache,
      api_key: resolve_api_key(state),
      agent_llm: state.config.llm,
      return_cache: true
    ]

    {messages, state} =
      case Context.compact(messages, compact_opts) do
        {:ok, compacted, new_cache} ->
          if length(compacted) < length(messages) do
            before_tokens = Tokenizer.count_messages(messages)
            after_tokens = Tokenizer.count_messages(compacted)

            state =
              emit_event(state, :context_compacted, %{
                strategy: to_string(memory_strategy),
                before_tokens: before_tokens,
                after_tokens: after_tokens,
                messages_before: length(messages),
                messages_after: length(compacted)
              })

            {compacted, %{state | summaries_cache: new_cache}}
          else
            {compacted, %{state | summaries_cache: new_cache}}
          end

        compacted when is_list(compacted) ->
          {compacted, state}
      end

    # Let the agent modify messages before calling
    {messages, state} = state.module.before_call(messages, state)

    # Build LLM options
    api_key = resolve_api_key(state)

    call_opts =
      llm_opts
      |> Keyword.put(:system, system)
      |> Keyword.put(:tools, tools)
      |> Keyword.put(:api_key, api_key)

    # Emit LLM request event with context snapshot
    message_tokens = Tokenizer.count_messages(messages)
    {_adapter_name, adapter_opts} = state.config.llm
    model = Keyword.get(adapter_opts, :model, "unknown")

    state =
      emit_event(state, :llm_request, %{
        model: model,
        message_count: length(messages),
        total_tokens: message_tokens
      })

    # Save context snapshot — what the LLM actually sees
    EventStore.save_context_snapshot(
      state.run_id,
      nil,
      messages,
      message_tokens,
      model
    )

    # Call the LLM with retry
    llm_start = System.monotonic_time(:millisecond)

    case llm_call_with_retry(adapter, messages, call_opts) do
      {:ok, response} ->
        llm_duration = System.monotonic_time(:millisecond) - llm_start

        # Emit LLM response event + telemetry
        state =
          emit_event(
            state,
            :llm_response,
            %{
              content: truncate_for_event(response.content),
              tool_calls: length(response.tool_calls),
              stop_reason: response.stop_reason,
              input_tokens: response.usage.input_tokens,
              output_tokens: response.usage.output_tokens
            },
            token_count: Map.get(response, :token_count, 0)
          )

        # Telemetry
        Telemetry.emit_llm_call(state.run_id, %{
          model: model,
          adapter: adapter,
          input_tokens: response.usage.input_tokens,
          output_tokens: response.usage.output_tokens,
          duration_ms: llm_duration
        })

        # Build assistant message — include tool_use blocks when present
        assistant_content =
          if response.tool_calls != [] do
            text_blocks =
              if response.content != "",
                do: [%{"type" => "text", "text" => response.content}],
                else: []

            tool_blocks =
              Enum.map(response.tool_calls, fn tc ->
                %{"type" => "tool_use", "id" => tc.id, "name" => tc.name, "input" => tc.input}
              end)

            text_blocks ++ tool_blocks
          else
            response.content
          end

        assistant_message = %{role: "assistant", content: assistant_content}
        messages = messages ++ [assistant_message]

        if response.tool_calls != [] and state.turn_count < max_turns do
          # Execute tools and loop
          {messages, state} = execute_tools(response.tool_calls, messages, state, stream_to)
          state = %{state | turn_count: state.turn_count + 1}

          # Maybe checkpoint after tool execution
          state = maybe_checkpoint(state, messages)

          run_loop(messages, state, stream_to)
        else
          # Done — fire completion hook
          {:ok, final_response, state} = state.module.on_complete(response, state)

          state =
            emit_event(state, :agent_complete, %{
              final_response: truncate_for_event(final_response.content),
              total_turns: state.turn_count,
              total_tokens: EventStore.token_usage(state.run_id)
            })

          # Telemetry
          Telemetry.emit_complete(state.run_id, %{
            total_turns: state.turn_count,
            total_tokens: 0
          })

          # Final checkpoint
          do_checkpoint(%{state | messages: messages})

          new_state = %{state | messages: messages, status: :ready, turn_count: 0}

          {:ok, final_response, new_state}
        end

      {:error, reason} ->
        state =
          emit_event(state, :agent_error, %{
            error: inspect(reason),
            turn: state.turn_count
          })

        Telemetry.emit_error(state.run_id, reason)

        {:error, reason, state}
    end
  end

  defp execute_tools(tool_calls, messages, state, stream_to) do
    tools = state.config[:tools] || []
    tool_map = Map.new(tools, fn t -> {t.name(), t} end)

    Enum.reduce(tool_calls, {messages, state}, fn tool_call, {msgs, st} ->
      tool_module = Map.get(tool_map, tool_call.name)

      if tool_module do
        # Emit tool start event
        st =
          emit_event(st, :tool_start, %{
            tool_name: tool_call.name,
            input: truncate_for_event(inspect(tool_call.input))
          })

        # Notify stream listener
        if stream_to do
          send(stream_to, {:sigil_tool_start, tool_call.name, tool_call.input})
        end

        context = %{
          session_id: st.opts[:session_id],
          tenant_id: st.opts[:tenant_id],
          agent_module: st.module,
          run_id: st.run_id
        }

        start_time = System.monotonic_time(:millisecond)

        case Sigil.Tool.execute(tool_module, tool_call.input, context) do
          {:ok, result} ->
            duration = System.monotonic_time(:millisecond) - start_time
            {result, st} = st.module.on_tool_result(tool_call.name, result, st)

            # Emit tool result event + telemetry
            st =
              emit_event(st, :tool_result, %{
                tool_name: tool_call.name,
                result: truncate_for_event(inspect(result)),
                duration_ms: duration
              })

            Telemetry.emit_tool_call(st.run_id, tool_call.name, %{
              duration_ms: duration,
              status: :ok
            })

            # Flag for checkpoint after tool execution
            st = %{st | checkpoint_after_tool: true}

            if stream_to do
              send(stream_to, {:sigil_tool_result, tool_call.name, result})
            end

            tool_result_msg = %{
              role: "user",
              content: [
                %{
                  type: "tool_result",
                  tool_use_id: tool_call.id,
                  content: format_tool_result(result)
                }
              ]
            }

            {msgs ++ [tool_result_msg], st}

          {:approval_required, _tool, _params} ->
            st =
              emit_event(st, :approval_requested, %{
                tool_name: tool_call.name,
                input: truncate_for_event(inspect(tool_call.input))
              })

            approval_msg = %{
              role: "user",
              content: [
                %{
                  type: "tool_result",
                  tool_use_id: tool_call.id,
                  content: "[Awaiting human approval for #{tool_call.name}]"
                }
              ]
            }

            if stream_to do
              send(stream_to, {:sigil_approval_required, tool_call.name, tool_call.input})
            end

            {msgs ++ [approval_msg], st}

          {:error, reason} ->
            duration = System.monotonic_time(:millisecond) - start_time

            st =
              emit_event(st, :tool_error, %{
                tool_name: tool_call.name,
                error: inspect(reason),
                duration_ms: duration
              })

            error_msg = %{
              role: "user",
              content: [
                %{
                  type: "tool_result",
                  tool_use_id: tool_call.id,
                  content: "Error: #{inspect(reason)}"
                }
              ]
            }

            {msgs ++ [error_msg], st}
        end
      else
        # Unknown tool
        st =
          emit_event(st, :tool_error, %{
            tool_name: tool_call.name,
            error: "Unknown tool"
          })

        unknown_msg = %{
          role: "user",
          content: [
            %{
              type: "tool_result",
              tool_use_id: tool_call.id,
              content: "Error: Unknown tool '#{tool_call.name}'"
            }
          ]
        }

        {msgs ++ [unknown_msg], st}
      end
    end)
  end

  # Event emission

  defp emit_event(state, event_type, payload, opts \\ []) do
    seq = state.event_sequence + 1
    token_count = Keyword.get(opts, :token_count, 0)

    EventStore.append(
      state.run_id,
      event_type,
      payload,
      sequence: seq,
      agent_module: state.module,
      token_count: token_count
    )

    %{state | event_sequence: seq}
  end

  # Checkpointing

  defp maybe_checkpoint(state, messages) do
    if Checkpoint.should_checkpoint?(state) do
      do_checkpoint(%{state | messages: messages})
      %{state | checkpoint_after_tool: false, checkpoint_before_compaction: false}
    else
      state
    end
  end

  defp do_checkpoint(state) do
    Checkpoint.save(
      state.run_id,
      state,
      state.messages,
      state.config,
      state.event_sequence
    )
  end

  # Resume helpers

  defp apply_replay_events(state, events) do
    Enum.reduce(events, state, fn event, acc ->
      case event.event_type do
        "user_message" ->
          msg = %{role: "user", content: event.payload["content"]}
          %{acc | messages: acc.messages ++ [msg], event_sequence: event.sequence}

        "llm_response" ->
          %{acc | event_sequence: event.sequence}

        "agent_complete" ->
          %{acc | event_sequence: event.sequence, status: :ready}

        _ ->
          %{acc | event_sequence: event.sequence}
      end
    end)
  end

  defp resolve_module(nil), do: nil

  defp resolve_module(module_string) when is_binary(module_string) do
    try do
      String.to_existing_atom("Elixir." <> module_string)
    rescue
      ArgumentError ->
        try do
          String.to_existing_atom(module_string)
        rescue
          ArgumentError -> nil
        end
    end
  end

  defp resolve_module(module) when is_atom(module), do: module

  # Config validation

  defp validate_config!(config, agent_module) do
    unless is_map(config) do
      raise ArgumentError,
            "#{inspect(agent_module)}.init_agent/1 must return a map, got: #{inspect(config)}"
    end

    unless Map.has_key?(config, :llm) do
      raise ArgumentError,
            "#{inspect(agent_module)}.init_agent/1 must include :llm key. " <>
              "Example: %{llm: {Sigil.LLM.Anthropic, model: \"claude-sonnet-4-20250514\"}, ...}"
    end

    case config.llm do
      {adapter, opts} when is_atom(adapter) and is_list(opts) ->
        unless Code.ensure_loaded?(adapter) do
          raise ArgumentError,
                "LLM adapter #{inspect(adapter)} is not a loaded module. " <>
                  "Did you mean Sigil.LLM.Anthropic or Sigil.LLM.OpenAI?"
        end

      other ->
        raise ArgumentError,
              ":llm must be a {module, keyword()} tuple, got: #{inspect(other)}"
    end

    if tools = config[:tools] do
      Enum.each(tools, fn tool ->
        unless is_atom(tool) and Code.ensure_loaded?(tool) do
          raise ArgumentError,
                "Tool #{inspect(tool)} is not a loaded module."
        end
      end)
    end

    :ok
  end

  # LLM retry with exponential backoff

  @max_retries 3
  @retry_base_ms 1_000

  defp llm_call_with_retry(adapter, messages, opts, attempt \\ 0) do
    case Sigil.LLM.chat(adapter, messages, opts) do
      {:ok, response} ->
        {:ok, response}

      {:error, %{status: status}}
      when status in [429, 529, 502, 503] and attempt < @max_retries ->
        backoff = (@retry_base_ms * :math.pow(2, attempt)) |> trunc()
        jitter = :rand.uniform(backoff)
        Process.sleep(backoff + jitter)
        llm_call_with_retry(adapter, messages, opts, attempt + 1)

      {:error, %Req.TransportError{}} = _error when attempt < @max_retries ->
        backoff = (@retry_base_ms * :math.pow(2, attempt)) |> trunc()
        Process.sleep(backoff)
        llm_call_with_retry(adapter, messages, opts, attempt + 1)

      error ->
        error
    end
  end

  # Budget helpers

  defp build_budget(config) do
    {_adapter, llm_opts} = config.llm
    model = Keyword.get(llm_opts, :model, "claude-sonnet-4-20250514")
    Budget.new(model: model)
  end

  defp resolve_api_key(state) do
    Keyword.get(state.opts, :api_key) ||
      Application.get_env(:sigil, :anthropic_api_key) ||
      System.get_env("ANTHROPIC_API_KEY")
  end

  defp format_tool_result(result) when is_binary(result), do: result
  defp format_tool_result(result) when is_map(result), do: Jason.encode!(result)
  defp format_tool_result(result), do: inspect(result)

  defp truncate_for_event(content) when is_binary(content) do
    if String.length(content) > 1000 do
      String.slice(content, 0, 1000) <> "...[truncated]"
    else
      content
    end
  end

  defp truncate_for_event(content), do: truncate_for_event(inspect(content))

  # Child spec for DynamicSupervisor
  def child_spec({:resume, state}) do
    %{
      id: {__MODULE__, make_ref()},
      start: {__MODULE__, :start_link, [{:resume, state}]},
      restart: :temporary
    }
  end

  def child_spec({agent_module, opts}) do
    %{
      id: {__MODULE__, make_ref()},
      start: {__MODULE__, :start_link, [{agent_module, opts}]},
      restart: :temporary
    }
  end
end
