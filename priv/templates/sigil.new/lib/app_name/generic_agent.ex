defmodule Journal.GenericAgent do
  @moduledoc """
  A single agent module that drives ALL agent configs from the database.

  Instead of writing a separate Elixir module per agent, this generic
  agent reads its configuration (system prompt, model, tools) from the
  DB and assembles itself at startup.

  This is the Sigil advantage: zero agent code. Configure everything
  through the admin UI.
  """
  use Sigil.Agent

  @impl true
  def init_agent(opts) do
    # Resolve tool slugs from DB into actual tool modules
    tool_slugs = opts[:tools] || []
    tool_modules = Journal.ToolRegistry.resolve(tool_slugs)

    # Build system prompt: admin-editable base + blog content as context
    base_prompt = opts[:system_prompt] || "You are a helpful assistant."
    system = base_prompt <> "\n\n" <> blog_context()

    %{
      llm: {Sigil.LLM.Anthropic, model: opts[:model] || "claude-sonnet-4-20250514"},
      tools: tool_modules,
      system: system,
      memory: :progressive,
      max_turns: 15
    }
  end

  # Inject published blog posts as context — the agent just *knows*
  defp blog_context do
    posts = Journal.Blog.list_published_posts()

    if posts == [] do
      ""
    else
      post_content =
        Enum.map_join(posts, "\n\n---\n\n", fn post ->
          tags = if post.tags && post.tags != [], do: " [#{Enum.join(post.tags, ", ")}]", else: ""
          "### #{post.title}#{tags}\n\n#{post.body}"
        end)

      """
      ## Journal Content

      Below are the published entries from Adam's journal. Reference these naturally when relevant.

      #{post_content}
      """
    end
  end

  @impl true
  def on_complete(response, state) do
    conv_id = state.opts[:conversation_id]

    if conv_id do
      content = extract_text(response.content)
      Journal.Conversations.add_message(conv_id, "ai", content)
      Journal.ConversationPubSub.broadcast(conv_id, {:new_message, %{role: "ai", content: content}})
    end

    {:ok, response, state}
  end

  defp extract_text(content) when is_binary(content), do: content

  defp extract_text(blocks) when is_list(blocks) do
    Enum.map_join(blocks, "\n", fn
      %{"text" => text} -> text
      %{text: text} -> text
      _ -> ""
    end)
  end

  defp extract_text(other), do: to_string(other)
end
