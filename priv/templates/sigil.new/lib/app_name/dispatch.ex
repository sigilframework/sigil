defmodule MyApp.Dispatch do
  @moduledoc """
  Lightweight intent classifier that routes user messages to the
  appropriate agent based on what's configured in the database.

  Uses a fast Haiku-class LLM call (<500ms) to classify intent.
  Dynamically builds the classification prompt from active agent configs.
  """

  @doc """
  Classify a user message and return the slug of the agent that should handle it.

  Takes the message, recent context, and a list of agent configs.
  Returns the slug string of the matched agent.
  """
  def classify(message, recent_context \\ [], agents) do
    # If only one agent, skip the LLM call
    if length(agents) <= 1 do
      case agents do
        [agent | _] -> agent.slug
        [] -> "blog-assistant"
      end
    else
      classify_with_llm(message, recent_context, agents)
    end
  end

  defp classify_with_llm(message, recent_context, agents) do
    api_key = Application.get_env(:sigil, :anthropic_api_key)

    # Build classification prompt dynamically from agent configs
    agent_descriptions =
      Enum.map_join(agents, "\n\n", fn agent ->
        # Extract first sentence of system prompt as description
        desc =
          (agent.system_prompt || "")
          |> String.split(~r/[.\n]/, parts: 2)
          |> List.first()
          |> String.trim()

        "- `#{agent.slug}` — #{desc}"
      end)

    default_slug = List.first(agents).slug

    system_prompt = """
    You are an intent classifier for a chat interface.

    Given a user message, classify the intent into exactly ONE of these agents:

    #{agent_descriptions}

    When in doubt, return `#{default_slug}`.

    Respond with ONLY the agent slug, nothing else.
    """

    context_text =
      if recent_context != [] do
        recent =
          recent_context
          |> Enum.take(-4)
          |> Enum.map_join("\n", fn msg ->
            role = String.upcase(to_string(msg.role))
            "#{role}: #{msg.content}"
          end)

        "Recent conversation:\n#{recent}\n\n"
      else
        ""
      end

    user_content = "#{context_text}Current user message: #{message}"
    messages = [%{role: "user", content: user_content}]

    opts = [
      api_key: api_key,
      model: "claude-3-5-haiku-20241022",
      system: system_prompt,
      max_tokens: 30,
      temperature: 0.0
    ]

    case Sigil.LLM.Anthropic.chat(messages, opts) do
      {:ok, response} ->
        content = response.content |> String.trim() |> String.downcase()

        # Find the matching agent slug
        matched =
          Enum.find(agents, fn agent ->
            String.contains?(content, agent.slug)
          end)

        if matched, do: matched.slug, else: default_slug

      {:error, _reason} ->
        default_slug
    end
  end
end
