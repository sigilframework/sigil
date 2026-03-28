defmodule Sigil.Memory.Summarizer do
  @moduledoc """
  LLM-powered conversation summarization for context compression.

  Uses a dedicated LLM call (with a fast, cheap model by default) to
  compress old conversation history while preserving decision-relevant
  context. This is the core of Sigil's long-running context window
  management.

  ## Strategies

  - `:extractive` — Pull out key facts, decisions, and outcomes
  - `:progressive` — Tiered: recent=verbatim, medium=summary, old=key facts
  - `:task_aware` — Summarize relative to the agent's current objective

  ## Usage

      {:ok, summary} = Summarizer.summarize(old_messages,
        llm: {Sigil.LLM.OpenAI, model: "gpt-4o-mini"},
        api_key: "sk-..."
      )

      {:ok, compacted, cache} = Summarizer.progressive_compress(
        messages, budget, cache: existing_cache
      )
  """

  alias Sigil.Memory.{Budget, Tokenizer}

  @extractive_prompt """
  You are a conversation summarizer for an AI agent system. Your job is to
  compress conversation history into a concise summary while preserving ALL
  of the following:

  1. Key decisions made and their reasoning
  2. Important facts and data points discovered
  3. Current state of any ongoing tasks or workflows
  4. User preferences, constraints, and requirements expressed
  5. Tool results that are needed for future decisions
  6. Any errors or issues encountered and how they were resolved

  Rules:
  - Be concise but NEVER drop decision-relevant information
  - Use bullet points for clarity
  - Preserve specific numbers, names, dates, and identifiers exactly
  - If a tool returned important data, include the key fields
  - Note which tools were called and what they accomplished
  """

  @key_facts_prompt """
  Extract ONLY the essential facts from this conversation as a bullet-point list.
  Each bullet should be a single, self-contained fact. Include:
  - Decisions made (what was decided and why)
  - Key data points (numbers, names, dates, IDs)
  - Task status (what's done, what's pending)
  - Constraints or preferences stated by the user

  Be extremely concise. Each fact should be one short line.
  """

  @doc """
  Summarize a list of messages into a concise text summary.

  ## Options

  - `:llm` — `{adapter, opts}` tuple for the LLM to use (default: gpt-4o-mini)
  - `:api_key` — API key for the summarization LLM
  - `:strategy` — `:extractive` (default) or `:key_facts`
  - `:system_prompt` — The agent's system prompt (for task-aware summarization)
  - `:max_summary_tokens` — Maximum tokens for the summary output (default: 1000)
  """
  def summarize(messages, opts \\ []) when is_list(messages) do
    if messages == [] do
      {:ok, ""}
    else
      strategy = Keyword.get(opts, :strategy, :extractive)
      do_summarize(messages, strategy, opts)
    end
  end

  @doc """
  Progressive compression: tiered summarization that balances
  detail and context window usage.

  Given messages and a budget, divides the message history into zones:

  - **Zone 1** (most recent): Verbatim — no compression
  - **Zone 2** (medium age): Summarized — ~4:1 compression
  - **Zone 3** (oldest): Key facts only — ~10:1 compression

  Summaries are cached so only new messages need processing on
  subsequent calls.

  ## Options

  - `:cache` — Previous summaries cache (from agent state)
  - `:zone1_pct` — Percentage of budget for verbatim zone (default: 0.5)
  - `:zone2_pct` — Percentage of budget for summary zone (default: 0.35)
  - `:zone3_pct` — Percentage of budget for key facts zone (default: 0.15)
  - Plus all options from `summarize/2`
  """
  def progressive_compress(messages, %Budget{} = budget, opts \\ []) do
    cache = Keyword.get(opts, :cache, %{})
    available = Budget.available(budget)

    # Zone allocation
    zone1_pct = Keyword.get(opts, :zone1_pct, 0.50)
    zone2_pct = Keyword.get(opts, :zone2_pct, 0.35)
    zone3_pct = Keyword.get(opts, :zone3_pct, 0.15)

    zone1_budget = trunc(available * zone1_pct)
    zone2_budget = trunc(available * zone2_pct)
    zone3_budget = trunc(available * zone3_pct)

    {system_msgs, other_msgs} = split_system(messages)
    total = length(other_msgs)

    if total == 0 do
      {:ok, messages, cache}
    else
      # Determine zone boundaries
      # Zone 1 gets the most recent messages that fit in zone1_budget
      {zone1_msgs, remaining} = take_recent_within_budget(other_msgs, zone1_budget)

      if remaining == [] do
        # Everything fits in zone 1 — no compression needed
        {:ok, messages, cache}
      else
        # Split remaining into zone 2 (recent half) and zone 3 (older half)
        zone2_count = div(length(remaining), 2)
        {zone3_msgs, zone2_msgs} = Enum.split(remaining, length(remaining) - zone2_count)

        # Compress zone 2 — summarize
        zone2_result =
          compress_zone(zone2_msgs, :extractive, zone2_budget, cache, :zone2, opts)

        # Compress zone 3 — key facts only
        zone3_result =
          compress_zone(zone3_msgs, :key_facts, zone3_budget, cache, :zone3, opts)

        case {zone3_result, zone2_result} do
          {{:ok, zone3_content, cache1}, {:ok, zone2_content, cache2}} ->
            merged_cache = Map.merge(cache, Map.merge(cache1, cache2))

            compacted =
              system_msgs ++
                build_summary_messages(zone3_content, zone2_content) ++
                zone1_msgs

            {:ok, compacted, merged_cache}

          {{:error, reason}, _} ->
            {:error, reason}

          {_, {:error, reason}} ->
            {:error, reason}
        end
      end
    end
  end

  # Private — summarization

  defp do_summarize(messages, :extractive, opts) do
    llm_summarize(messages, @extractive_prompt, opts)
  end

  defp do_summarize(messages, :key_facts, opts) do
    llm_summarize(messages, @key_facts_prompt, opts)
  end

  defp do_summarize(messages, :task_aware, opts) do
    system_prompt = Keyword.get(opts, :system_prompt, "")

    task_prompt = """
    #{@extractive_prompt}

    The agent's current task/role is:
    #{system_prompt}

    Focus your summary on information relevant to this specific task.
    """

    llm_summarize(messages, task_prompt, opts)
  end

  defp llm_summarize(messages, system_prompt, opts) do
    {adapter, llm_opts} = summarization_llm(opts)
    api_key = resolve_api_key(opts)
    max_tokens = Keyword.get(opts, :max_summary_tokens, 1_000)

    # Format the messages as a conversation transcript for the summarizer
    transcript = format_transcript(messages)

    summarize_messages = [
      %{role: "user", content: "Summarize this conversation:\n\n#{transcript}"}
    ]

    call_opts =
      llm_opts
      |> Keyword.put(:system, system_prompt)
      |> Keyword.put(:api_key, api_key)
      |> Keyword.put(:max_tokens, max_tokens)
      |> Keyword.put(:temperature, 0.3)

    case Sigil.LLM.chat(adapter, summarize_messages, call_opts) do
      {:ok, response} ->
        {:ok, response.content}

      {:error, reason} ->
        {:error, {:summarization_failed, reason}}
    end
  end

  # Private — progressive compression helpers

  defp take_recent_within_budget(messages, token_budget) do
    # Take messages from the end until we exceed the budget
    messages
    |> Enum.reverse()
    |> Enum.reduce_while({[], 0}, fn msg, {taken, tokens} ->
      msg_tokens = Tokenizer.count_messages([msg])

      if tokens + msg_tokens <= token_budget do
        {:cont, {[msg | taken], tokens + msg_tokens}}
      else
        {:halt, {taken, tokens}}
      end
    end)
    |> then(fn {taken, _tokens} ->
      # Messages not taken are the "remaining" (older messages)
      remaining_count = length(messages) - length(taken)
      {remaining, _} = Enum.split(messages, remaining_count)
      {taken, remaining}
    end)
  end

  defp compress_zone([], _strategy, _budget, cache, _zone_key, _opts) do
    {:ok, nil, cache}
  end

  defp compress_zone(messages, strategy, _budget, cache, zone_key, opts) do
    # Check cache — use hash of message contents as cache key
    cache_key = {zone_key, message_hash(messages)}

    case Map.get(cache, cache_key) do
      nil ->
        # Not cached — summarize
        case do_summarize(messages, strategy, opts) do
          {:ok, summary} ->
            {:ok, summary, Map.put(cache, cache_key, summary)}

          error ->
            error
        end

      cached_summary ->
        {:ok, cached_summary, cache}
    end
  end

  defp build_summary_messages(nil, nil), do: []

  defp build_summary_messages(zone3_content, nil) do
    [%{role: "system", content: "[Key facts from early conversation]\n#{zone3_content}"}]
  end

  defp build_summary_messages(nil, zone2_content) do
    [%{role: "system", content: "[Summary of earlier conversation]\n#{zone2_content}"}]
  end

  defp build_summary_messages(zone3_content, zone2_content) do
    [
      %{role: "system", content: "[Key facts from early conversation]\n#{zone3_content}"},
      %{role: "system", content: "[Summary of recent conversation]\n#{zone2_content}"}
    ]
  end

  defp message_hash(messages) do
    messages
    |> Enum.map(fn msg -> "#{msg.role}:#{inspect(msg.content)}" end)
    |> Enum.join("|")
    |> then(&:erlang.phash2/1)
  end

  defp format_transcript(messages) do
    messages
    |> Enum.map(fn msg ->
      role = to_string(msg.role) |> String.upcase()
      content = extract_text_content(msg.content)
      "[#{role}]: #{content}"
    end)
    |> Enum.join("\n\n")
  end

  defp extract_text_content(content) when is_binary(content), do: content

  defp extract_text_content(blocks) when is_list(blocks) do
    Enum.map_join(blocks, "\n", fn
      %{text: text} ->
        text

      %{"text" => text} ->
        text

      %{content: content} ->
        to_string(content)

      %{"content" => content} ->
        to_string(content)

      %{type: "tool_use", name: name} ->
        "[Called tool: #{name}]"

      %{"type" => "tool_use", "name" => name} ->
        "[Called tool: #{name}]"

      %{type: "tool_result", content: content} ->
        "[Tool result: #{String.slice(to_string(content), 0, 200)}]"

      other ->
        inspect(other)
    end)
  end

  defp extract_text_content(other), do: to_string(other)

  defp split_system(messages) do
    Enum.split_with(messages, fn msg ->
      msg.role == "system" or msg.role == :system
    end)
  end

  # Default summarization LLM — use the agent's own adapter or a cheap model
  defp summarization_llm(opts) do
    case Keyword.get(opts, :llm) do
      nil ->
        # Try to use the agent's own adapter (passed from agent loop)
        case Keyword.get(opts, :agent_llm) do
          {adapter, adapter_opts} ->
            # Use a cheaper model variant if available
            {adapter, Keyword.put(adapter_opts, :max_tokens, 1_000)}

          nil ->
            # Last resort: pick based on available API keys
            cond do
              Application.get_env(:sigil, :anthropic_api_key) ||
                  System.get_env("ANTHROPIC_API_KEY") ->
                {Sigil.LLM.Anthropic, [model: "claude-haiku-3-20250422"]}

              Application.get_env(:sigil, :openai_api_key) || System.get_env("OPENAI_API_KEY") ->
                {Sigil.LLM.OpenAI, [model: "gpt-4o-mini"]}

              true ->
                {Sigil.LLM.Anthropic, [model: "claude-haiku-3-20250422"]}
            end
        end

      {adapter, llm_opts} ->
        {adapter, llm_opts}
    end
  end

  defp resolve_api_key(opts) do
    Keyword.get(opts, :api_key) ||
      Keyword.get(opts, :summarization_api_key) ||
      Application.get_env(:sigil, :openai_api_key) ||
      Application.get_env(:sigil, :anthropic_api_key) ||
      System.get_env("OPENAI_API_KEY") ||
      System.get_env("ANTHROPIC_API_KEY")
  end
end
