defmodule Sigil.Agent.Telemetry do
  @moduledoc """
  Structured telemetry events emitted during agent execution.

  Integrates with Erlang's `:telemetry` library for external
  monitoring via Prometheus, Grafana, DataDog, etc.

  ## Events

  All events are prefixed with `[:sigil, :agent]`:

  - `[:sigil, :agent, :turn]` — Each think→act→observe cycle
  - `[:sigil, :agent, :llm_call]` — LLM API call completed
  - `[:sigil, :agent, :tool_call]` — Tool execution completed
  - `[:sigil, :agent, :context_compact]` — Context window compressed
  - `[:sigil, :agent, :checkpoint]` — State checkpointed
  - `[:sigil, :agent, :resume]` — Agent resumed from checkpoint
  - `[:sigil, :agent, :drift]` — Context drift detected above threshold
  - `[:sigil, :agent, :budget_warning]` — Approaching context window limit
  - `[:sigil, :agent, :complete]` — Agent run completed
  - `[:sigil, :agent, :error]` — Agent error occurred

  ## Attaching Handlers

      :telemetry.attach_many("sigil-metrics", [
        [:sigil, :agent, :turn],
        [:sigil, :agent, :llm_call],
        [:sigil, :agent, :tool_call],
        [:sigil, :agent, :context_compact],
        [:sigil, :agent, :budget_warning]
      ], &MyApp.Metrics.handle_event/4, nil)
  """

  @doc "Emit a turn completion event."
  def emit_turn(run_id, turn, metadata \\ %{}) do
    :telemetry.execute(
      [:sigil, :agent, :turn],
      %{turn: turn},
      Map.merge(%{run_id: run_id}, metadata)
    )
  end

  @doc "Emit an LLM call event."
  def emit_llm_call(run_id, metadata) do
    :telemetry.execute(
      [:sigil, :agent, :llm_call],
      %{
        input_tokens: metadata[:input_tokens] || 0,
        output_tokens: metadata[:output_tokens] || 0,
        duration_ms: metadata[:duration_ms] || 0
      },
      %{
        run_id: run_id,
        model: metadata[:model],
        adapter: metadata[:adapter]
      }
    )
  end

  @doc "Emit a tool call event."
  def emit_tool_call(run_id, tool_name, metadata) do
    :telemetry.execute(
      [:sigil, :agent, :tool_call],
      %{duration_ms: metadata[:duration_ms] || 0},
      %{
        run_id: run_id,
        tool_name: tool_name,
        status: metadata[:status] || :ok
      }
    )
  end

  @doc "Emit a context compaction event."
  def emit_compact(run_id, before_tokens, after_tokens, strategy \\ :unknown) do
    :telemetry.execute(
      [:sigil, :agent, :context_compact],
      %{
        before_tokens: before_tokens,
        after_tokens: after_tokens,
        tokens_saved: before_tokens - after_tokens,
        compression_ratio:
          if before_tokens > 0 do
            Float.round(after_tokens / before_tokens, 3)
          else
            1.0
          end
      },
      %{run_id: run_id, strategy: strategy}
    )
  end

  @doc "Emit a checkpoint event."
  def emit_checkpoint(run_id, checkpoint_id, sequence) do
    :telemetry.execute(
      [:sigil, :agent, :checkpoint],
      %{sequence: sequence},
      %{run_id: run_id, checkpoint_id: checkpoint_id}
    )
  end

  @doc "Emit a resume event."
  def emit_resume(run_id, checkpoint_id, events_replayed) do
    :telemetry.execute(
      [:sigil, :agent, :resume],
      %{events_replayed: events_replayed},
      %{run_id: run_id, checkpoint_id: checkpoint_id}
    )
  end

  @doc "Emit a context drift event."
  def emit_drift(run_id, drift_score, threshold \\ 0.3) do
    :telemetry.execute(
      [:sigil, :agent, :drift],
      %{drift_score: drift_score, threshold: threshold},
      %{
        run_id: run_id,
        status: if(drift_score > threshold, do: :drifted, else: :on_track)
      }
    )
  end

  @doc "Emit a budget warning when approaching context window limits."
  def emit_budget_warning(run_id, remaining_pct, total_budget) do
    :telemetry.execute(
      [:sigil, :agent, :budget_warning],
      %{
        remaining_pct: remaining_pct,
        total_budget: total_budget
      },
      %{run_id: run_id}
    )
  end

  @doc "Emit an agent completion event."
  def emit_complete(run_id, metadata) do
    :telemetry.execute(
      [:sigil, :agent, :complete],
      %{
        total_turns: metadata[:total_turns] || 0,
        total_tokens: metadata[:total_tokens] || 0,
        duration_seconds: metadata[:duration_seconds] || 0
      },
      %{run_id: run_id}
    )
  end

  @doc "Emit an agent error event."
  def emit_error(run_id, error, metadata \\ %{}) do
    :telemetry.execute(
      [:sigil, :agent, :error],
      %{},
      Map.merge(%{run_id: run_id, error: error}, metadata)
    )
  end
end
