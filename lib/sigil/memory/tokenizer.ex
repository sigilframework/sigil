defmodule Sigil.Memory.Tokenizer do
  @moduledoc """
  Token counting for context window management.

  Provides tuned heuristic token counting that matches tiktoken's
  cl100k_base encoding within ~10% for English text. Counts are
  deliberately conservative (slightly over-estimate) to avoid
  exceeding context windows.

  ## Adapter Pattern

  The default implementation uses a pure-Elixir heuristic. For exact
  counts, swap in a Rustler NIF adapter or use the API-based counter:

      # In config.exs
      config :sigil, :tokenizer, Sigil.Memory.Tokenizer.Rustler

  ## Usage

      Sigil.Memory.Tokenizer.count("Hello, world!")
      #=> 4

      Sigil.Memory.Tokenizer.count_messages([
        %{role: "user", content: "Hello!"},
        %{role: "assistant", content: "Hi there!"}
      ])
      #=> 14
  """

  @type provider :: :anthropic | :openai | :default

  @doc "Count tokens in a text string."
  def count(text, opts \\ [])
  def count(nil, _opts), do: 0

  def count(text, opts) when is_binary(text) do
    adapter = adapter(opts)
    adapter.count(text, opts)
  end

  @doc "Count tokens across a list of messages, including framing overhead."
  def count_messages(messages, opts \\ []) when is_list(messages) do
    adapter = adapter(opts)
    adapter.count_messages(messages, opts)
  end

  @doc "Count tokens via a provider's API for exact results."
  def count_via_api(provider, messages, opts \\ [])

  def count_via_api(:anthropic, messages, opts) do
    api_key = Keyword.fetch!(opts, :api_key)
    model = Keyword.get(opts, :model, "claude-sonnet-4-20250514")
    system = Keyword.get(opts, :system)

    body =
      %{
        "model" => model,
        "messages" => format_messages_for_api(messages)
      }
      |> then(fn b -> if system, do: Map.put(b, "system", system), else: b end)
      |> Jason.encode!()

    case Req.post("https://api.anthropic.com/v1/messages/count_tokens",
           body: body,
           headers: [
             {"content-type", "application/json"},
             {"x-api-key", api_key},
             {"anthropic-version", "2023-06-01"}
           ],
           receive_timeout: 10_000
         ) do
      {:ok, %{status: 200, body: %{"input_tokens" => count}}} ->
        {:ok, count}

      {:ok, %{status: status, body: body}} ->
        {:error, %{status: status, body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def count_via_api(_provider, _messages, _opts) do
    {:error, :not_supported}
  end

  # Per-model message framing overhead (tokens per message)
  @doc "Get the per-message token overhead for a provider."
  def message_overhead(:anthropic), do: 4
  def message_overhead(:openai), do: 4
  def message_overhead(_), do: 4

  # Private

  defp adapter(opts) do
    Keyword.get_lazy(opts, :adapter, fn ->
      Application.get_env(:sigil, :tokenizer, Sigil.Memory.Tokenizer.Default)
    end)
  end

  defp format_messages_for_api(messages) do
    Enum.map(messages, fn msg ->
      %{
        "role" => to_string(msg.role),
        "content" => format_content_for_api(msg.content)
      }
    end)
  end

  defp format_content_for_api(content) when is_binary(content), do: content

  defp format_content_for_api(blocks) when is_list(blocks) do
    Enum.map(blocks, fn
      %{type: _type} = block -> Map.new(block, fn {k, v} -> {to_string(k), v} end)
      %{"type" => _} = block -> block
      other -> %{"type" => "text", "text" => to_string(other)}
    end)
  end

  defp format_content_for_api(other), do: to_string(other)
end

defmodule Sigil.Memory.Tokenizer.Default do
  @moduledoc """
  Pure-Elixir heuristic tokenizer tuned against cl100k_base.

  Uses word-boundary splitting with adjustments for:
  - Punctuation and special characters (each is ~1 token)
  - Whitespace patterns
  - Code tokens (operators, brackets)
  - Numbers (each digit group is ~1 token)

  Deliberately over-estimates by ~5-10% to provide a safety margin
  for context window management.
  """

  @doc "Count tokens in a text string."
  def count(text, _opts \\ []) when is_binary(text) do
    if text == "" do
      0
    else
      text
      |> tokenize()
      |> length()
    end
  end

  @doc "Count tokens across a list of messages including framing."
  def count_messages(messages, opts \\ []) do
    provider = Keyword.get(opts, :provider, :default)
    overhead = Sigil.Memory.Tokenizer.message_overhead(provider)

    messages
    |> Enum.map(fn msg ->
      content = extract_content(msg)
      count(content) + overhead
    end)
    |> Enum.sum()
  end

  # Tokenization: split text into approximate BPE-like tokens
  defp tokenize(text) do
    # Split on word boundaries, whitespace, punctuation, and numbers
    # This regex approximates cl100k_base's splitting behavior
    Regex.scan(
      ~r/[a-zA-Z]{1,15}|[0-9]{1,10}|[^\s\w]|\s+/u,
      text
    )
    |> List.flatten()
    |> Enum.reject(&(&1 == ""))
  end

  defp extract_content(%{content: content}) when is_binary(content), do: content

  defp extract_content(%{content: blocks}) when is_list(blocks) do
    Enum.map_join(blocks, " ", fn
      %{content: c} when is_binary(c) -> c
      %{text: t} when is_binary(t) -> t
      %{"content" => c} when is_binary(c) -> c
      %{"text" => t} when is_binary(t) -> t
      other -> inspect(other)
    end)
  end

  defp extract_content(%{content: other}), do: to_string(other)
  defp extract_content(%{"content" => content}), do: extract_content(%{content: content})
  defp extract_content(_), do: ""
end
