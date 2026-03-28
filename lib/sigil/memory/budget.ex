defmodule Sigil.Memory.Budget do
  @moduledoc """
  Context window budget allocator.

  Treats the LLM's context window as a managed resource. Different
  subsystems (system prompt, tool definitions, conversation history,
  response buffer) each get a slice of the budget, with guarantees
  that the total never exceeds the model's context window.

  ## Usage

      budget = Budget.new(model: "claude-sonnet-4-20250514")
      budget = Budget.reserve(budget, :system, system_prompt)
      budget = Budget.reserve(budget, :tools, tool_definitions)

      Budget.available(budget)
      #=> 190_000

      Budget.fits?(budget, messages)
      #=> true

  ## Budget Categories

  - `:system` — System prompt (reserved once at init)
  - `:tools` — Tool definitions sent with each request
  - `:response` — Reserved for the model's response (default: 4096)
  - `:history` — Everything else: conversation messages
  """

  alias Sigil.Memory.Tokenizer

  defstruct [
    :model,
    :total,
    :response_buffer,
    reservations: %{},
    tokenizer_opts: []
  ]

  @type t :: %__MODULE__{
          model: String.t(),
          total: non_neg_integer(),
          response_buffer: non_neg_integer(),
          reservations: %{atom() => non_neg_integer()},
          tokenizer_opts: keyword()
        }

  # Known model context window sizes
  @context_windows %{
    "claude-sonnet-4-20250514" => 200_000,
    "claude-3-5-sonnet-20241022" => 200_000,
    "claude-3-5-haiku-20241022" => 200_000,
    "claude-3-opus-20240229" => 200_000,
    "claude-3-haiku-20240307" => 200_000,
    "gpt-4o" => 128_000,
    "gpt-4o-2024-11-20" => 128_000,
    "gpt-4o-mini" => 128_000,
    "gpt-4-turbo" => 128_000,
    "gpt-4" => 8_192,
    "gpt-3.5-turbo" => 16_385,
    "o1" => 200_000,
    "o1-mini" => 128_000
  }

  @default_response_buffer 4_096
  @safety_margin_pct 0.02

  @doc """
  Create a new budget for the given model.

  ## Options

  - `:model` — Model name (required)
  - `:context_window` — Override the context window size
  - `:response_buffer` — Tokens reserved for the response (default: 4096)
  - `:tokenizer_opts` — Options passed to the tokenizer
  """
  def new(opts \\ []) do
    model = Keyword.get(opts, :model, "claude-sonnet-4-20250514")
    total = Keyword.get(opts, :context_window, context_window(model))
    response_buffer = Keyword.get(opts, :response_buffer, @default_response_buffer)
    tokenizer_opts = Keyword.get(opts, :tokenizer_opts, [])

    %__MODULE__{
      model: model,
      total: total,
      response_buffer: response_buffer,
      reservations: %{response: response_buffer},
      tokenizer_opts: tokenizer_opts
    }
  end

  @doc """
  Reserve tokens for a category.

  Content is tokenized and the count is stored. Calling `reserve/3`
  again for the same category replaces the previous reservation.
  """
  def reserve(%__MODULE__{} = budget, category, content) when is_atom(category) do
    tokens = count_content(content, budget.tokenizer_opts)
    %{budget | reservations: Map.put(budget.reservations, category, tokens)}
  end

  @doc """
  Reserve a specific number of tokens for a category (no tokenization).
  """
  def reserve_tokens(%__MODULE__{} = budget, category, token_count)
      when is_atom(category) and is_integer(token_count) do
    %{budget | reservations: Map.put(budget.reservations, category, token_count)}
  end

  @doc """
  Get the number of tokens available for conversation history.

  This is the total context window minus all reservations (system,
  tools, response buffer) and a safety margin.
  """
  def available(%__MODULE__{} = budget) do
    reserved = budget.reservations |> Map.values() |> Enum.sum()
    safety = trunc(budget.total * @safety_margin_pct)
    max(0, budget.total - reserved - safety)
  end

  @doc """
  Check if a list of messages fits within the available budget.
  """
  def fits?(%__MODULE__{} = budget, messages) when is_list(messages) do
    message_tokens = Tokenizer.count_messages(messages, budget.tokenizer_opts)
    message_tokens <= available(budget)
  end

  @doc """
  Count how many tokens a list of messages would use.
  """
  def count_messages(%__MODULE__{} = budget, messages) do
    Tokenizer.count_messages(messages, budget.tokenizer_opts)
  end

  @doc """
  Get the reserved tokens for each category.
  """
  def reservations(%__MODULE__{} = budget), do: budget.reservations

  @doc """
  Get a summary of the budget allocation.
  """
  def summary(%__MODULE__{} = budget) do
    reserved = budget.reservations |> Map.values() |> Enum.sum()
    safety = trunc(budget.total * @safety_margin_pct)

    %{
      model: budget.model,
      total: budget.total,
      reservations: budget.reservations,
      total_reserved: reserved,
      safety_margin: safety,
      available_for_history: available(budget),
      utilization_pct: Float.round(reserved / budget.total * 100, 1)
    }
  end

  @doc "Get the context window size for a model."
  def context_window(model) do
    # Try exact match first, then prefix match
    case Map.get(@context_windows, model) do
      nil -> find_by_prefix(model)
      size -> size
    end
  end

  # Private

  defp find_by_prefix(model) do
    @context_windows
    |> Enum.find(fn {key, _} -> String.starts_with?(model, key) end)
    |> case do
      {_, size} -> size
      nil -> 100_000
    end
  end

  defp count_content(content, opts) when is_binary(content) do
    Tokenizer.count(content, opts)
  end

  defp count_content(tools, opts) when is_list(tools) do
    # For tool definitions, estimate based on JSON serialization
    tools
    |> Enum.map(fn
      tool when is_atom(tool) ->
        # Tool module — serialize its schema
        schema =
          Jason.encode!(%{
            name: tool.name(),
            description: tool.description(),
            input_schema: tool.params()
          })

        Tokenizer.count(schema, opts)

      text when is_binary(text) ->
        Tokenizer.count(text, opts)

      other ->
        Tokenizer.count(inspect(other), opts)
    end)
    |> Enum.sum()
  end

  defp count_content(content, opts) do
    Tokenizer.count(to_string(content), opts)
  end
end
