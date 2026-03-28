if Code.ensure_loaded?(Ecto) do
  defmodule Sigil.Agent.EventStore do
    @moduledoc """
    Append-only event log for agent runs.

    Every meaningful action an agent takes — receiving a message, calling
    the LLM, executing a tool, compacting context — is recorded as an
    immutable event. Events are never modified or deleted.

    Events are written asynchronously via a batched writer GenServer
    to avoid blocking the agent loop.

    ## Event Types

    | Type | When |
    |---|---|
    | `user_message` | User sends a message |
    | `llm_request` | Before each LLM call |
    | `llm_response` | After LLM responds |
    | `tool_start` | Tool execution begins |
    | `tool_result` | Tool returns successfully |
    | `tool_error` | Tool fails |
    | `approval_requested` | Agent pauses for human approval |
    | `approval_resolved` | Approval granted/denied |
    | `context_compacted` | Context window compressed |
    | `checkpoint_created` | State snapshot saved |
    | `agent_complete` | Agent finishes |
    | `agent_error` | Agent crashes |

    ## Usage

        EventStore.append(run_id, :llm_response, %{content: "...", usage: ...})
        events = EventStore.replay(run_id)
        events = EventStore.replay(run_id, from_sequence: 47)
    """

    import Ecto.Query

    # Ecto Schema for agent_events
    defmodule Event do
      use Ecto.Schema

      @primary_key {:id, :id, autogenerate: true}
      schema "agent_events" do
        field(:run_id, Ecto.UUID)
        field(:agent_module, :string)
        field(:event_type, :string)
        field(:sequence, :integer)
        field(:payload, :map, default: %{})
        field(:token_count, :integer, default: 0)

        timestamps(type: :utc_datetime, updated_at: false)
      end
    end

    # Ecto Schema for context_snapshots
    defmodule ContextSnapshot do
      use Ecto.Schema

      @primary_key {:id, :binary_id, autogenerate: true}
      schema "context_snapshots" do
        field(:run_id, Ecto.UUID)
        field(:event_id, :integer)
        field(:messages, :map)
        field(:token_count, :integer)
        field(:model, :string)

        timestamps(type: :utc_datetime, updated_at: false)
      end
    end

    @doc """
    Append an event to the log.

    Events are batched and written asynchronously to avoid blocking
    the agent loop. Use `append_sync/4` if you need guaranteed writes.
    """
    def append(run_id, event_type, payload, opts \\ []) do
      if repo_available?() do
        event = build_event(run_id, event_type, payload, opts)
        Sigil.Agent.EventStore.Writer.write(event)
      end

      :ok
    end

    @doc """
    Append an event synchronously (blocks until written).

    Use this for critical events like checkpoints and completions.
    """
    def append_sync(run_id, event_type, payload, opts \\ []) do
      event = build_event(run_id, event_type, payload, opts)

      case repo().insert(event) do
        {:ok, saved} -> {:ok, saved}
        {:error, changeset} -> {:error, changeset}
      end
    end

    @doc """
    Save a context snapshot — the exact messages sent to the LLM.
    """
    def save_context_snapshot(run_id, event_id, messages, token_count, model) do
      if repo_available?() do
        snapshot = %ContextSnapshot{
          run_id: run_id,
          event_id: event_id,
          messages: %{"messages" => serialize_messages(messages)},
          token_count: token_count,
          model: model
        }

        Sigil.Agent.EventStore.Writer.write_snapshot(snapshot)
      end

      :ok
    end

    @doc """
    Replay all events for a run, in sequence order.
    """
    def replay(run_id, opts \\ []) do
      from_seq = Keyword.get(opts, :from_sequence, 0)
      limit = Keyword.get(opts, :limit, 10_000)

      query =
        from(e in Event,
          where: e.run_id == ^run_id and e.sequence >= ^from_seq,
          order_by: [asc: e.sequence],
          limit: ^limit
        )

      if repo_available?() do
        {:ok, repo().all(query)}
      else
        {:ok, []}
      end
    end

    @doc """
    Replay events from a specific sequence number.
    """
    def replay_from(run_id, sequence) do
      replay(run_id, from_sequence: sequence)
    end

    @doc """
    Get the last sequence number for a run.
    """
    def last_sequence(run_id) do
      query =
        from(e in Event,
          where: e.run_id == ^run_id,
          select: max(e.sequence)
        )

      if repo_available?() do
        repo().one(query) || 0
      else
        0
      end
    end

    @doc """
    Get events of a specific type for a run.
    """
    def events_by_type(run_id, event_type) do
      type_str = to_string(event_type)

      query =
        from(e in Event,
          where: e.run_id == ^run_id and e.event_type == ^type_str,
          order_by: [asc: e.sequence]
        )

      repo().all(query)
    end

    @doc """
    Get aggregate token usage for a run.
    """
    def token_usage(run_id) do
      query =
        from(e in Event,
          where: e.run_id == ^run_id,
          select: %{
            total_tokens: sum(e.token_count),
            event_count: count(e.id)
          }
        )

      if repo_available?() do
        repo().one(query)
      else
        %{total_tokens: 0, event_count: 0}
      end
    end

    @doc """
    Get all tool calls with their results for a run.
    """
    def tool_calls(run_id) do
      query =
        from(e in Event,
          where:
            e.run_id == ^run_id and e.event_type in ["tool_start", "tool_result", "tool_error"],
          order_by: [asc: e.sequence]
        )

      events = repo().all(query)

      # Pair tool_start events with their results
      events
      |> Enum.chunk_while(
        nil,
        fn
          %{event_type: "tool_start"} = e, nil ->
            {:cont, e}

          %{event_type: type} = e, start when type in ["tool_result", "tool_error"] ->
            {:cont, %{start: start, result: e, type: type}, nil}

          %{event_type: "tool_start"} = e, _prev ->
            {:cont, e}

          _e, acc ->
            {:cont, acc}
        end,
        fn
          nil -> {:cont, nil}
          acc -> {:cont, acc, nil}
        end
      )
      |> Enum.reject(&is_nil/1)
    end

    @doc """
    Get a context snapshot for a specific event.
    """
    def context_at(run_id, opts) do
      event_id = Keyword.get(opts, :event_id)
      sequence = Keyword.get(opts, :sequence)

      query =
        cond do
          event_id ->
            from(s in ContextSnapshot,
              where: s.run_id == ^run_id and s.event_id == ^event_id
            )

          sequence ->
            # Find the event at this sequence, then its snapshot
            from(s in ContextSnapshot,
              join: e in Event,
              on: s.event_id == e.id,
              where: e.run_id == ^run_id and e.sequence == ^sequence
            )

          true ->
            # Latest snapshot
            from(s in ContextSnapshot,
              where: s.run_id == ^run_id,
              order_by: [desc: s.inserted_at],
              limit: 1
            )
        end

      case repo().one(query) do
        nil -> {:error, :not_found}
        snapshot -> {:ok, snapshot}
      end
    end

    # Private

    defp build_event(run_id, event_type, payload, opts) do
      %Event{
        run_id: run_id,
        agent_module: Keyword.get(opts, :agent_module, "") |> to_string(),
        event_type: to_string(event_type),
        sequence: Keyword.get(opts, :sequence, 0),
        payload: serialize_payload(payload),
        token_count: Keyword.get(opts, :token_count, 0)
      }
    end

    defp serialize_payload(payload) when is_map(payload) do
      payload
      |> Map.new(fn {k, v} -> {to_string(k), serialize_value(v)} end)
    end

    defp serialize_payload(payload), do: %{"value" => inspect(payload)}

    defp serialize_value(v) when is_atom(v), do: to_string(v)
    defp serialize_value(v) when is_pid(v), do: inspect(v)
    defp serialize_value(v) when is_reference(v), do: inspect(v)
    defp serialize_value(v) when is_function(v), do: inspect(v)
    defp serialize_value(%{__struct__: _} = v), do: Map.from_struct(v) |> serialize_payload()
    defp serialize_value(v) when is_map(v), do: serialize_payload(v)
    defp serialize_value(v) when is_list(v), do: Enum.map(v, &serialize_value/1)
    defp serialize_value(v), do: v

    defp serialize_messages(messages) do
      Enum.map(messages, fn msg ->
        msg
        |> Map.new(fn {k, v} -> {to_string(k), serialize_value(v)} end)
      end)
    end

    defp repo do
      Application.get_env(:sigil, :repo, Sigil.Repo)
    end

    defp repo_available? do
      Application.get_env(:sigil, Sigil.Repo) != nil
    end
  end

  defmodule Sigil.Agent.EventStore.Writer do
    @moduledoc """
    Batched async writer for agent events.

    Collects events and writes them in batches to reduce
    database round-trips. Flushes on a timer or when the
    batch size is reached.
    """
    use GenServer

    @batch_size 50
    @flush_interval_ms 1_000

    def start_link(opts \\ []) do
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end

    @doc "Queue an event for writing."
    def write(%Sigil.Agent.EventStore.Event{} = event) do
      GenServer.cast(__MODULE__, {:write_event, event})
    end

    @doc "Queue a context snapshot for writing."
    def write_snapshot(%Sigil.Agent.EventStore.ContextSnapshot{} = snapshot) do
      GenServer.cast(__MODULE__, {:write_snapshot, snapshot})
    end

    @doc "Force flush all pending writes."
    def flush do
      GenServer.call(__MODULE__, :flush, 10_000)
    end

    # GenServer callbacks

    @impl true
    def init(_opts) do
      schedule_flush()
      {:ok, %{events: [], snapshots: []}}
    end

    @impl true
    def handle_cast({:write_event, event}, state) do
      events = [event | state.events]

      if length(events) >= @batch_size do
        do_flush_events(events)
        {:noreply, %{state | events: []}}
      else
        {:noreply, %{state | events: events}}
      end
    end

    def handle_cast({:write_snapshot, snapshot}, state) do
      snapshots = [snapshot | state.snapshots]

      if length(snapshots) >= @batch_size do
        do_flush_snapshots(snapshots)
        {:noreply, %{state | snapshots: []}}
      else
        {:noreply, %{state | snapshots: snapshots}}
      end
    end

    @impl true
    def handle_call(:flush, _from, state) do
      do_flush_events(state.events)
      do_flush_snapshots(state.snapshots)
      {:reply, :ok, %{state | events: [], snapshots: []}}
    end

    @impl true
    def handle_info(:flush_timer, state) do
      if state.events != [] do
        do_flush_events(state.events)
      end

      if state.snapshots != [] do
        do_flush_snapshots(state.snapshots)
      end

      schedule_flush()
      {:noreply, %{state | events: [], snapshots: []}}
    end

    defp do_flush_events([]), do: :ok

    defp do_flush_events(events) do
      repo = Application.get_env(:sigil, :repo, Sigil.Repo)

      entries =
        events
        |> Enum.reverse()
        |> Enum.map(fn event ->
          %{
            run_id: event.run_id,
            agent_module: event.agent_module,
            event_type: event.event_type,
            sequence: event.sequence,
            payload: event.payload,
            token_count: event.token_count,
            inserted_at: DateTime.utc_now()
          }
        end)

      try do
        repo.insert_all(Sigil.Agent.EventStore.Event, entries)
      rescue
        e ->
          require Logger
          Logger.error("Failed to flush agent events: #{Exception.message(e)}")
      end
    end

    defp do_flush_snapshots([]), do: :ok

    defp do_flush_snapshots(snapshots) do
      repo = Application.get_env(:sigil, :repo, Sigil.Repo)

      entries =
        snapshots
        |> Enum.reverse()
        |> Enum.map(fn snap ->
          %{
            id: Ecto.UUID.generate(),
            run_id: snap.run_id,
            event_id: snap.event_id,
            messages: snap.messages,
            token_count: snap.token_count,
            model: snap.model,
            inserted_at: DateTime.utc_now()
          }
        end)

      try do
        repo.insert_all(Sigil.Agent.EventStore.ContextSnapshot, entries)
      rescue
        e ->
          require Logger
          Logger.error("Failed to flush context snapshots: #{Exception.message(e)}")
      end
    end

    defp schedule_flush do
      Process.send_after(self(), :flush_timer, @flush_interval_ms)
    end
  end
end
