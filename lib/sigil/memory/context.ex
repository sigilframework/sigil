defmodule Sigil.Memory.Context do
  @moduledoc """
  Context window management strategies.

  When conversation history exceeds the LLM's context window,
  these strategies decide what to keep and what to discard.
  All strategies are budget-aware — they use real token counting
  and respect the `Sigil.Memory.Budget` allocation.

  ## Strategies

  - `:sliding_window` — Drop oldest messages until tokens fit within budget
  - `:summarize_oldest` — Summarize old messages with the LLM
  - `:progressive` — Tiered compression: recent=verbatim, medium=summary, old=key facts
  - `:drop_tool_results` — Truncate verbose tool outputs the AI has already processed
  - `:custom` — User provides a custom `compact/2` function

  ## Usage

      budget = Sigil.Memory.Budget.new(model: "claude-sonnet-4-20250514")

      messages = Sigil.Memory.Context.compact(messages,
        strategy: :progressive,
        budget: budget
      )
  """

  alias Sigil.Memory.{Budget, Tokenizer, Summarizer}

  @default_max_messages 50

  @doc "Compact messages using the given strategy."
  def compact(messages, opts \\ []) do
    strategy = Keyword.get(opts, :strategy, :sliding_window)

    case strategy do
      :sliding_window -> sliding_window(messages, opts)
      :drop_tool_results -> drop_tool_results(messages, opts)
      :summarize_oldest -> summarize_oldest(messages, opts)
      :progressive -> progressive(messages, opts)
      :custom -> custom_compact(messages, opts)
      _ -> messages
    end
  end

  @doc "Count tokens in messages using the real tokenizer."
  def count_tokens(messages, opts \\ []) do
    Tokenizer.count_messages(messages, opts)
  end

  @doc "Check if messages fit within the given budget."
  def fits?(messages, %Budget{} = budget) do
    Budget.fits?(budget, messages)
  end

  def fits?(messages, opts) when is_list(opts) do
    budget = Keyword.get(opts, :budget)
    if budget, do: Budget.fits?(budget, messages), else: true
  end

  # Strategies

  defp sliding_window(messages, opts) do
    budget = Keyword.get(opts, :budget)

    if budget do
      # Token-based: drop oldest messages until we fit
      slide_to_fit(messages, budget)
    else
      # Fallback: message-count based
      max = Keyword.get(opts, :max_messages, @default_max_messages)
      slide_by_count(messages, max)
    end
  end

  defp slide_to_fit(messages, budget) do
    {system_msgs, other_msgs} = split_system(messages)

    # Already fits?
    if Budget.fits?(budget, messages) do
      messages
    else
      # Drop oldest non-system messages one at a time until it fits
      drop_until_fits(system_msgs, other_msgs, budget)
    end
  end

  defp drop_until_fits(system_msgs, [], _budget), do: system_msgs

  defp drop_until_fits(system_msgs, [_dropped | rest] = _others, budget) do
    candidate = system_msgs ++ rest

    if Budget.fits?(budget, candidate) do
      candidate
    else
      drop_until_fits(system_msgs, rest, budget)
    end
  end

  defp slide_by_count(messages, max) do
    if length(messages) > max do
      {system_msgs, other_msgs} = split_system(messages)
      system_msgs ++ Enum.take(other_msgs, -max)
    else
      messages
    end
  end

  defp drop_tool_results(messages, opts) do
    max_tool_result_tokens = Keyword.get(opts, :max_tool_result_tokens, 200)

    messages
    |> Enum.map(fn msg ->
      case msg do
        %{role: role, content: content} when role in ["tool", :tool] ->
          truncate_tool_content(msg, content, max_tool_result_tokens)

        %{content: blocks} when is_list(blocks) ->
          new_blocks =
            Enum.map(blocks, fn
              %{type: "tool_result", content: content} = block ->
                tokens = Tokenizer.count(to_string(content))

                if tokens > max_tool_result_tokens do
                  truncated =
                    content
                    |> to_string()
                    |> String.slice(0, max_tool_result_tokens * 3)

                  %{block | content: truncated <> "\n[truncated — #{tokens} tokens]"}
                else
                  block
                end

              other ->
                other
            end)

          %{msg | content: new_blocks}

        _ ->
          msg
      end
    end)
  end

  defp truncate_tool_content(msg, content, max_tokens) do
    content_str = to_string(content)
    tokens = Tokenizer.count(content_str)

    if tokens > max_tokens do
      truncated = String.slice(content_str, 0, max_tokens * 3)
      %{msg | content: truncated <> "\n[truncated — #{tokens} tokens]"}
    else
      msg
    end
  end

  defp summarize_oldest(messages, opts) do
    budget = Keyword.get(opts, :budget)
    max = Keyword.get(opts, :max_messages, @default_max_messages)

    needs_compaction? =
      if budget do
        not Budget.fits?(budget, messages)
      else
        length(messages) > max
      end

    if needs_compaction? do
      {system_msgs, other_msgs} = split_system(messages)

      # Determine how many messages to summarize
      # Keep the most recent half, summarize the older half
      keep_count = div(length(other_msgs), 2)
      {old, recent} = Enum.split(other_msgs, length(other_msgs) - keep_count)

      if old == [] do
        messages
      else
        case Summarizer.summarize(old, opts) do
          {:ok, summary_text} ->
            summary_msg = %{
              role: "system",
              content: "[Summary of earlier conversation]\n#{summary_text}"
            }

            result = system_msgs ++ [summary_msg | recent]

            # If still doesn't fit, recurse
            still_too_large? =
              if budget, do: not Budget.fits?(budget, result), else: false

            if still_too_large? do
              summarize_oldest(result, opts)
            else
              result
            end

          {:error, _reason} ->
            # Fallback to sliding window if summarization fails
            sliding_window(messages, opts)
        end
      end
    else
      messages
    end
  end

  defp progressive(messages, opts) do
    budget = Keyword.get(opts, :budget)
    cache = Keyword.get(opts, :summaries_cache, %{})

    if budget && not Budget.fits?(budget, messages) do
      case Summarizer.progressive_compress(messages, budget, Keyword.put(opts, :cache, cache)) do
        {:ok, compacted, new_cache} ->
          # Return compacted messages — caller should update cache in agent state
          if Keyword.get(opts, :return_cache, false) do
            {:ok, compacted, new_cache}
          else
            compacted
          end

        {:error, _reason} ->
          sliding_window(messages, opts)
      end
    else
      if Keyword.get(opts, :return_cache, false) do
        {:ok, messages, cache}
      else
        messages
      end
    end
  end

  defp custom_compact(messages, opts) do
    case Keyword.get(opts, :compact_fn) do
      nil -> messages
      fun when is_function(fun, 2) -> fun.(messages, opts)
    end
  end

  # Helpers

  defp split_system(messages) do
    Enum.split_with(messages, fn msg ->
      msg.role == "system" or msg.role == :system
    end)
  end
end
