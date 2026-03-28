defmodule Sigil.Agent.Observer do
  @moduledoc """
  Observability tools for agent execution.

  Answers questions like:
  - "What did the agent see when it decided to call CreateExpense?"
  - "How has token usage grown over this agent's run?"
  - "Has the agent's understanding drifted from its original task?"

  ## Usage

      # Full timeline of an agent run
      timeline = Observer.timeline(run_id)

      # What the LLM saw at a specific decision point
      {:ok, context} = Observer.context_at(run_id, sequence: 47)

      # Token usage over time
      trend = Observer.token_trend(run_id)

      # Check for context drift
      {:ok, report} = Observer.drift_check(run_id)

      # Replay a specific decision
      {:ok, replay} = Observer.decision_replay(run_id, event_id)
  """

  alias Sigil.Agent.{EventStore, Checkpoint}

  @doc """
  Get a full timeline of an agent run.

  Returns a chronological list of events with human-readable
  descriptions, token counts, and timestamps.

  ## Options

  - `:types` — Filter to specific event types (default: all)
  - `:limit` — Max events to return (default: 1000)
  """
  def timeline(run_id, opts \\ []) do
    type_filter = Keyword.get(opts, :types)

    {:ok, events} = EventStore.replay(run_id, opts)

    timeline =
      events
      |> maybe_filter_types(type_filter)
      |> Enum.map(&format_timeline_entry/1)

    {:ok, timeline}
  end

  @doc """
  Get the exact context (messages) the LLM saw at a specific point.

  ## Options (one of):

  - `:sequence` — Event sequence number
  - `:event_id` — Specific event ID
  """
  def context_at(run_id, opts) do
    EventStore.context_at(run_id, opts)
  end

  @doc """
  Get token usage over time for a run.

  Returns a list of `%{turn, cumulative_tokens, event_tokens, event_type}`
  entries showing how token usage grows over the agent's execution.
  """
  def token_trend(run_id) do
    {:ok, events} = EventStore.replay(run_id)

    {trend, _total} =
      events
      |> Enum.filter(fn e -> e.token_count > 0 end)
      |> Enum.reduce({[], 0}, fn event, {entries, cumulative} ->
        new_cumulative = cumulative + event.token_count

        entry = %{
          sequence: event.sequence,
          event_type: event.event_type,
          event_tokens: event.token_count,
          cumulative_tokens: new_cumulative,
          timestamp: event.inserted_at
        }

        {entries ++ [entry], new_cumulative}
      end)

    {:ok, trend}
  end

  @doc """
  Check for context drift — whether the agent's recent behavior
  has diverged from its original task.

  Uses cosine similarity between the original system prompt + early
  messages and the most recent context. A high drift score (> 0.3)
  suggests the agent may have gone off-track.

  ## Options

  - `:threshold` — Drift score above which to flag (default: 0.3)
  - `:embed_adapter` — LLM adapter for embeddings (default: OpenAI)
  - `:api_key` — API key for embeddings
  """
  def drift_check(run_id, opts \\ []) do
    threshold = Keyword.get(opts, :threshold, 0.3)
    {:ok, events} = EventStore.replay(run_id)

    if length(events) < 10 do
      {:ok, %{drift_score: 0.0, status: :too_early, message: "Not enough events to measure drift"}}
    else
      # Get early conversation context
      early_events =
        events
        |> Enum.filter(fn e -> e.event_type in ["user_message", "llm_response"] end)
        |> Enum.take(5)

      # Get recent conversation context
      recent_events =
        events
        |> Enum.filter(fn e -> e.event_type in ["user_message", "llm_response"] end)
        |> Enum.take(-5)

      early_text = events_to_text(early_events)
      recent_text = events_to_text(recent_events)

      # Try to compute drift via embeddings
      case compute_drift(early_text, recent_text, opts) do
        {:ok, drift_score} ->
          status = if drift_score > threshold, do: :drifted, else: :on_track

          {:ok, %{
            drift_score: Float.round(drift_score, 4),
            status: status,
            threshold: threshold,
            early_context_preview: String.slice(early_text, 0, 200),
            recent_context_preview: String.slice(recent_text, 0, 200),
            message:
              if status == :drifted do
                "Agent may have drifted from original task (score: #{Float.round(drift_score, 2)})"
              else
                "Agent appears to be on track (score: #{Float.round(drift_score, 2)})"
              end
          }}

        {:error, _reason} ->
          # Fallback: simple heuristic based on topic overlap
          drift_score = heuristic_drift(early_text, recent_text)
          status = if drift_score > threshold, do: :drifted, else: :on_track

          {:ok, %{
            drift_score: Float.round(drift_score, 4),
            status: status,
            threshold: threshold,
            method: :heuristic,
            message: "Estimated drift (embedding unavailable): #{Float.round(drift_score, 2)}"
          }}
      end
    end
  end

  @doc """
  Replay a specific decision — shows what the LLM saw and what it decided.

  Returns the context snapshot (messages) and the LLM's response for
  a given event, providing a complete picture of why the agent made
  a specific choice.
  """
  def decision_replay(run_id, event_id) do
    # Find the event
    {:ok, events} = EventStore.replay(run_id)

    event = Enum.find(events, fn e -> e.id == event_id end)

    if event do
      # Find the corresponding context snapshot
      context_result = EventStore.context_at(run_id, event_id: event_id)

      # Find the next response event (what the LLM decided)
      response_event =
        events
        |> Enum.drop_while(fn e -> e.id != event_id end)
        |> Enum.find(fn e -> e.event_type in ["llm_response", "tool_start"] end)

      {:ok, %{
        event: format_timeline_entry(event),
        context: case context_result do
          {:ok, snapshot} -> snapshot
          _ -> nil
        end,
        decision: if(response_event, do: format_timeline_entry(response_event)),
        sequence: event.sequence,
        timestamp: event.inserted_at
      }}
    else
      {:error, :event_not_found}
    end
  end

  @doc """
  Get a summary of an agent run — key metrics and highlights.
  """
  def run_summary(run_id) do
    {:ok, events} = EventStore.replay(run_id)
    checkpoints = Checkpoint.list(run_id)

    tool_events = Enum.filter(events, fn e -> e.event_type in ["tool_start", "tool_result", "tool_error"] end)
    error_events = Enum.filter(events, fn e -> e.event_type in ["tool_error", "agent_error"] end)
    llm_events = Enum.filter(events, fn e -> e.event_type in ["llm_request", "llm_response"] end)
    compaction_events = Enum.filter(events, fn e -> e.event_type == "context_compacted" end)

    total_tokens = events |> Enum.map(& &1.token_count) |> Enum.sum()

    first_event = List.first(events)
    last_event = List.last(events)
    duration =
      if first_event && last_event do
        DateTime.diff(last_event.inserted_at, first_event.inserted_at, :second)
      end

    {:ok, %{
      run_id: run_id,
      total_events: length(events),
      total_tokens: total_tokens,
      llm_calls: div(length(llm_events), 2),
      tool_calls: div(length(tool_events), 2),
      errors: length(error_events),
      context_compactions: length(compaction_events),
      checkpoints: length(checkpoints),
      duration_seconds: duration,
      started_at: first_event && first_event.inserted_at,
      completed_at: last_event && last_event.inserted_at,
      status:
        cond do
          Enum.any?(events, fn e -> e.event_type == "agent_complete" end) -> :completed
          Enum.any?(events, fn e -> e.event_type == "agent_error" end) -> :errored
          true -> :in_progress
        end
    }}
  end

  # Private helpers

  defp format_timeline_entry(event) do
    %{
      sequence: event.sequence,
      type: event.event_type,
      description: describe_event(event),
      tokens: event.token_count,
      payload: event.payload,
      timestamp: event.inserted_at
    }
  end

  defp describe_event(event) do
    case event.event_type do
      "user_message" ->
        content = event.payload["content"] || ""
        "User: #{String.slice(content, 0, 100)}"

      "llm_request" ->
        "LLM call (#{event.payload["model"]}, #{event.payload["message_count"]} msgs, ~#{event.payload["total_tokens"]} tokens)"

      "llm_response" ->
        tools = event.payload["tool_calls"] || 0
        if tools > 0 do
          "LLM responded with #{tools} tool call(s)"
        else
          content = event.payload["content"] || ""
          "LLM: #{String.slice(content, 0, 100)}"
        end

      "tool_start" ->
        "→ Calling #{event.payload["tool_name"]}"

      "tool_result" ->
        "← #{event.payload["tool_name"]} completed (#{event.payload["duration_ms"]}ms)"

      "tool_error" ->
        "✗ #{event.payload["tool_name"]} failed: #{event.payload["error"]}"

      "approval_requested" ->
        "⏸ Awaiting approval for #{event.payload["tool_name"]}"

      "context_compacted" ->
        before = event.payload["before_tokens"] || 0
        after_tokens = event.payload["after_tokens"] || 0
        "Context compacted: #{before} → #{after_tokens} tokens (#{event.payload["strategy"]})"

      "checkpoint_created" ->
        "📸 Checkpoint saved (seq: #{event.payload["sequence"]})"

      "agent_complete" ->
        "✓ Agent completed (#{event.payload["total_turns"]} turns)"

      "agent_error" ->
        "✗ Agent error: #{event.payload["error"]}"

      "agent_resumed" ->
        "↻ Agent resumed from checkpoint #{event.payload["checkpoint_id"]}"

      other ->
        other
    end
  end

  defp maybe_filter_types(events, nil), do: events

  defp maybe_filter_types(events, types) when is_list(types) do
    type_strs = Enum.map(types, &to_string/1)
    Enum.filter(events, fn e -> e.event_type in type_strs end)
  end

  defp events_to_text(events) do
    events
    |> Enum.map(fn e ->
      content = e.payload["content"] || ""
      "#{e.event_type}: #{content}"
    end)
    |> Enum.join("\n")
  end

  defp compute_drift(early_text, recent_text, opts) do
    adapter = Keyword.get(opts, :embed_adapter, Sigil.LLM.OpenAI)
    api_key = Keyword.get(opts, :api_key) ||
      Application.get_env(:sigil, :openai_api_key) ||
      System.get_env("OPENAI_API_KEY")

    if api_key do
      with {:ok, early_vec} <- Sigil.LLM.embed(adapter, early_text, api_key: api_key),
           {:ok, recent_vec} <- Sigil.LLM.embed(adapter, recent_text, api_key: api_key) do
        similarity = cosine_similarity(early_vec, recent_vec)
        # Convert similarity to drift (1.0 = identical, 0.0 = completely different)
        drift = 1.0 - similarity
        {:ok, drift}
      end
    else
      {:error, :no_api_key}
    end
  end

  defp cosine_similarity(a, b) when length(a) == length(b) do
    dot = Enum.zip(a, b) |> Enum.map(fn {x, y} -> x * y end) |> Enum.sum()
    norm_a = :math.sqrt(Enum.map(a, &(&1 * &1)) |> Enum.sum())
    norm_b = :math.sqrt(Enum.map(b, &(&1 * &1)) |> Enum.sum())

    if norm_a == 0 or norm_b == 0 do
      0.0
    else
      dot / (norm_a * norm_b)
    end
  end

  defp cosine_similarity(_, _), do: 0.0

  defp heuristic_drift(early_text, recent_text) do
    # Simple word overlap heuristic
    early_words = early_text |> String.downcase() |> String.split(~r/\W+/) |> MapSet.new()
    recent_words = recent_text |> String.downcase() |> String.split(~r/\W+/) |> MapSet.new()

    if MapSet.size(early_words) == 0 or MapSet.size(recent_words) == 0 do
      0.0
    else
      overlap = MapSet.intersection(early_words, recent_words) |> MapSet.size()
      union = MapSet.union(early_words, recent_words) |> MapSet.size()

      # Jaccard distance = 1 - (intersection / union)
      1.0 - (overlap / union)
    end
  end
end
