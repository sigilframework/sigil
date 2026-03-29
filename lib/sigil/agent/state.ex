defmodule Sigil.Agent.State do
  @moduledoc """
  Typed struct for agent GenServer state.

  Using a struct catches typos at compile time and makes the state
  shape explicit. All agent state mutations go through this struct.
  """

  @enforce_keys [:module, :config, :run_id]
  defstruct [
    :module,
    :config,
    :run_id,
    :budget,
    :resumed_from,
    messages: [],
    opts: [],
    turn_count: 0,
    status: :ready,
    event_sequence: 0,
    token_usage: %{input_tokens: 0, output_tokens: 0, total_tokens: 0},
    checkpoint_policy: %{},
    summaries_cache: %{},
    checkpoint_after_tool: false,
    checkpoint_before_compaction: false
  ]

  @type t :: %__MODULE__{
          module: module(),
          config: map(),
          run_id: String.t(),
          budget: Sigil.Memory.Budget.t() | nil,
          resumed_from: String.t() | nil,
          messages: list(),
          opts: keyword(),
          turn_count: non_neg_integer(),
          status: :ready | :running,
          event_sequence: non_neg_integer(),
          token_usage: %{
            input_tokens: non_neg_integer(),
            output_tokens: non_neg_integer(),
            total_tokens: non_neg_integer()
          },
          checkpoint_policy: map(),
          summaries_cache: map(),
          checkpoint_after_tool: boolean(),
          checkpoint_before_compaction: boolean()
        }
end
