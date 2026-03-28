defmodule Sigil.LLM.Mock do
  @moduledoc """
  Mock LLM adapter for testing.

  Returns configurable responses without hitting any API.
  Use this in your test suite to test agents deterministically.

  ## Usage

      # Simple mock that always returns the same response
      defmodule TestAgent do
        use Sigil.Agent

        def init_agent(opts) do
          %{
            llm: {Sigil.LLM.Mock, responses: [
              "Hello! How can I help?",
              "I'll look that up for you."
            ]},
            system: "You are a test agent."
          }
        end
      end

      # Mock with tool calls
      defmodule ToolTestAgent do
        use Sigil.Agent

        def init_agent(_opts) do
          %{
            llm: {Sigil.LLM.Mock, responses: [
              %{content: "Let me search that.", tool_calls: [
                %{id: "call_1", name: "search", input: %{"query" => "test"}}
              ]},
              "Found the results."
            ]},
            tools: [MyTool],
            system: "Test agent."
          }
        end
      end

  ## Options

  - `:responses` — List of responses to cycle through. Can be strings or response maps.
  - `:delay_ms` — Simulated latency per call (default: 0)
  - `:fail_on` — Call number to fail on (1-indexed, for testing error handling)
  - `:fail_error` — Error to return on failure (default: transient API error)
  """
  @behaviour Sigil.LLM

  @impl true
  def chat(_messages, opts) do
    responses = Keyword.get(opts, :responses, ["Mock response"])
    delay_ms = Keyword.get(opts, :delay_ms, 0)
    fail_on = Keyword.get(opts, :fail_on)

    # Track call count via process dictionary
    call_count = Process.get(:sigil_mock_call_count, 0) + 1
    Process.put(:sigil_mock_call_count, call_count)

    # Simulate latency
    if delay_ms > 0, do: Process.sleep(delay_ms)

    # Check if this call should fail
    if fail_on && call_count == fail_on do
      fail_error = Keyword.get(opts, :fail_error, %{status: 500, body: "Mock error"})
      {:error, fail_error}
    else
      # Cycle through responses
      idx = rem(call_count - 1, length(responses))
      raw_response = Enum.at(responses, idx)

      {:ok, build_response(raw_response, call_count)}
    end
  end

  @impl true
  def stream(_messages, opts) do
    case chat([], opts) do
      {:ok, response} ->
        # Emit response as a single chunk stream
        stream = Stream.map([response.content], fn text -> {:chunk, text} end)
        {:ok, stream}

      error ->
        error
    end
  end

  @impl true
  def embed(input, _opts) do
    # Generate a deterministic fake embedding from the input
    hash = :erlang.phash2(input)
    embedding = for i <- 0..1535, do: :math.sin(hash + i) * 0.1
    {:ok, embedding}
  end

  @doc "Reset the mock call counter (call between tests)."
  def reset do
    Process.put(:sigil_mock_call_count, 0)
    :ok
  end

  @doc "Get the current call count."
  def call_count do
    Process.get(:sigil_mock_call_count, 0)
  end

  # Private

  defp build_response(text, call_count) when is_binary(text) do
    %{
      role: "assistant",
      content: text,
      tool_calls: [],
      stop_reason: "end_turn",
      token_count: div(String.length(text), 4),
      usage: %{
        input_tokens: 100 * call_count,
        output_tokens: div(String.length(text), 4)
      }
    }
  end

  defp build_response(%{content: content} = response_map, call_count) do
    tool_calls = Map.get(response_map, :tool_calls, [])

    %{
      role: "assistant",
      content: content || "",
      tool_calls: tool_calls,
      stop_reason: if(tool_calls != [], do: "tool_use", else: "end_turn"),
      token_count: 100,
      usage: %{
        input_tokens: 100 * call_count,
        output_tokens: 100
      }
    }
  end

  defp build_response(other, call_count) do
    build_response(inspect(other), call_count)
  end
end
