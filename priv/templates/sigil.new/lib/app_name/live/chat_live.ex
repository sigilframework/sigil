defmodule Journal.ChatLive do
  @moduledoc """
  Chat UI backed by a `Sigil.Agent.Team`.

  A team of agents handles user messages:
  - **Dispatch** classifies intent (fast Haiku call)
  - **Blog Assistant** searches and discusses journal content
  - **Scheduler** pre-screens users and books meetings

  The user sees a single seamless conversation. Routing is invisible.
  """
  use Sigil.Live
  import Sigil.HTML, only: [escape: 1]

  @impl true
  def mount(params, socket) do
    api_key = Application.get_env(:sigil, :anthropic_api_key)
    ai_available = is_binary(api_key) and api_key != ""

    agent_config =
      case params do
        %{"slug" => slug} -> Journal.Agents.get_agent_by_slug!(slug)
        _ -> List.first(Journal.Agents.list_active_agents())
      end

    slug = if agent_config, do: agent_config.slug, else: "default"
    tags = Journal.Blog.list_tags()
    recent_posts = Journal.Blog.list_published_posts() |> Enum.take(3)

    # Load ALL active agent configs from DB — team is fully DB-driven
    agent_configs = Journal.Agents.list_active_agents()

    # Only start conversations and teams if AI is available
    {conversation, messages, team, session_writes} =
      if ai_available do
        session = params["_session"] || %{}
        session_key = "conv_#{slug}"
        existing_conv_id = session[session_key]

        {conv, msgs} = resume_or_create_conversation(existing_conv_id, agent_config)
        t = start_team(agent_configs, conv)
        Journal.ConversationPubSub.subscribe(conv.id)
        sw = Map.put(%{}, session_key, conv.id)
        {conv, msgs, t, sw}
      else
        {nil, [], nil, %{}}
      end

    {:ok,
     Sigil.Live.assign(socket,
       ai_available: ai_available,
       agent_config: agent_config,
       agent_configs: agent_configs,
       team: team,
       tags: tags,
       recent_posts: recent_posts,
       conversation_id: conversation && conversation.id,
       messages: messages,
       loading: false,
       __session__: session_writes
     )}
  end

  @impl true
  def render(assigns) do
    messages_html =
      Enum.map_join(assigns.messages, "\n", fn msg ->
        if msg.role in ["ai", "admin"] do
          cleaned = Sigil.LLM.clean_content(msg.content)
          content_html = if cleaned == "" and assigns.loading do
            """
            <span class="inline-flex items-center gap-0.5 text-stone-400">
              <span class="animate-bounce inline-block" style="animation-delay: 0ms; animation-duration: 1s">●</span>
              <span class="animate-bounce inline-block" style="animation-delay: 200ms; animation-duration: 1s">●</span>
              <span class="animate-bounce inline-block" style="animation-delay: 400ms; animation-duration: 1s">●</span>
            </span>
            """
          else
            escape(cleaned)
          end

          """
          <div class="flex items-start gap-3 max-w-2xl">
            <div class="flex-shrink-0 mt-0.5 h-7 w-7 rounded-full bg-stone-900 dark:bg-stone-200 flex items-center justify-center">
              <svg class="h-3.5 w-3.5 text-white dark:text-stone-900" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M9.813 15.904 9 18.75l-.813-2.846a4.5 4.5 0 0 0-3.09-3.09L2.25 12l2.846-.813a4.5 4.5 0 0 0 3.09-3.09L9 5.25l.813 2.846a4.5 4.5 0 0 0 3.09 3.09L15.75 12l-2.846.813a4.5 4.5 0 0 0-3.09 3.09ZM18.259 8.715 18 9.75l-.259-1.035a3.375 3.375 0 0 0-2.455-2.456L14.25 6l1.036-.259a3.375 3.375 0 0 0 2.455-2.456L18 2.25l.259 1.035a3.375 3.375 0 0 0 2.455 2.456L21.75 6l-1.036.259a3.375 3.375 0 0 0-2.455 2.456Z" /></svg>
            </div>
            <div class="text-sm leading-relaxed text-stone-700 dark:text-stone-300 pt-0.5">#{content_html}</div>
          </div>
          """
        else
          """
          <div class="flex items-start gap-3 max-w-2xl ml-auto justify-end">
            <div class="text-sm leading-relaxed text-stone-900 dark:text-stone-100 bg-stone-100 dark:bg-stone-800 rounded-2xl px-4 py-2.5">#{escape(msg.content)}</div>
          </div>
          """
        end
      end)

    agent_name =
      if assigns.agent_config, do: escape(assigns.agent_config.name), else: "Assistant"

    sidebar =
      Journal.Components.SideNav.render(%{
        tags: assigns[:tags] || [],
        recent_posts: assigns[:recent_posts] || [],
        current_user: assigns[:current_user]
      })

    """
    <div class="flex min-h-screen flex-col lg:flex-row">
      #{sidebar}

      <!-- Chat Main -->
      <main class="flex-1 flex flex-col h-screen min-w-0">
        <!-- Header -->
        <div class="border-b border-stone-200 dark:border-stone-800 px-6 py-4 flex-shrink-0">
          <div class="flex items-center gap-3">
            <div class="h-8 w-8 rounded-full bg-stone-900 dark:bg-stone-200 flex items-center justify-center">
              <svg class="h-4 w-4 text-white dark:text-stone-900" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M9.813 15.904 9 18.75l-.813-2.846a4.5 4.5 0 0 0-3.09-3.09L2.25 12l2.846-.813a4.5 4.5 0 0 0 3.09-3.09L9 5.25l.813 2.846a4.5 4.5 0 0 0 3.09 3.09L15.75 12l-2.846.813a4.5 4.5 0 0 0-3.09 3.09ZM18.259 8.715 18 9.75l-.259-1.035a3.375 3.375 0 0 0-2.455-2.456L14.25 6l1.036-.259a3.375 3.375 0 0 0 2.455-2.456L18 2.25l.259 1.035a3.375 3.375 0 0 0 2.455 2.456L21.75 6l-1.036.259a3.375 3.375 0 0 0-2.455 2.456Z" /></svg>
            </div>
            <div>
              <h1 class="font-medium text-sm text-stone-900 dark:text-stone-100">#{agent_name}</h1>
              <p class="text-xs text-stone-500">Ask me anything about the journal</p>
            </div>
          </div>
        </div>

        <!-- Messages -->
        <div class="flex-1 overflow-y-auto" id="chatLog" data-sigil-scroll="chatLog">
          <div class="max-w-3xl mx-auto px-6 py-8 space-y-6">
            #{if assigns.ai_available, do: messages_html, else: ai_unavailable_banner()}
          </div>
        </div>

        <!-- Input -->
        <div class="border-t border-stone-200 dark:border-stone-800 flex-shrink-0">
          <div class="max-w-3xl mx-auto px-6 py-4">
            <form class="relative" sigil-submit="send_message">
              <input type="text" name="message" placeholder="#{if assigns.ai_available, do: "Message #{agent_name}...", else: "AI chat is not configured"}" 
                autocomplete="off" #{unless assigns.ai_available, do: "disabled", else: ""}
                class="w-full rounded-xl border border-stone-300 dark:border-stone-700 bg-white dark:bg-stone-900 pl-4 pr-12 py-3 text-sm text-stone-900 dark:text-stone-100 placeholder-stone-400 dark:placeholder-stone-500 outline-none focus:border-stone-400 dark:focus:border-stone-600 focus:ring-1 focus:ring-stone-400/30 dark:focus:ring-stone-600/30 transition-colors disabled:opacity-50 disabled:cursor-not-allowed" />
              <button type="submit" #{unless assigns.ai_available, do: "disabled", else: ""} class="absolute right-2 top-1/2 -translate-y-1/2 rounded-lg bg-stone-900 dark:bg-stone-100 p-1.5 text-white dark:text-stone-900 hover:bg-stone-700 dark:hover:bg-stone-300 transition-colors disabled:opacity-50 disabled:cursor-not-allowed">
                <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M6 12 3.269 3.125A59.769 59.769 0 0 1 21.485 12 59.768 59.768 0 0 1 3.27 20.875L5.999 12Zm0 0h7.5" /></svg>
              </button>
            </form>
          </div>
        </div>
      </main>
    </div>
    """
  end

  # --- Events ---

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) when message != "" do
    conv_id = socket.assigns.conversation_id

    # Persist user message to DB (for admin visibility)
    Journal.Conversations.add_message(conv_id, "user", message)
    Journal.ConversationPubSub.broadcast(conv_id, {:new_message, %{role: "user", content: message}})

    # Auto-title from first user message
    if length(socket.assigns.messages) <= 1 do
      case Journal.Conversations.get_conversation!(conv_id) do
        conv -> Journal.Conversations.maybe_set_title(conv, message)
      end
    end

    # Add user message + thinking placeholder
    messages = socket.assigns.messages ++ [
      %{role: "user", content: message},
      %{role: "ai", content: ""}
    ]
    socket = Sigil.Live.assign(socket, messages: messages, loading: true)

    # Dispatch: classify intent and route to the right agent
    dispatch_and_send(socket, message)
  end

  def handle_event("send_message", _params, socket), do: {:noreply, socket}
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  # --- Agent process messages ---

  @impl true
  def handle_info({:sigil_complete, response}, socket) do
    content = extract_response_text(response)

    messages = socket.assigns.messages
    last = List.last(messages)

    messages =
      if last && last.role == "ai" do
        List.replace_at(messages, -1, %{role: "ai", content: content})
      else
        messages ++ [%{role: "ai", content: content}]
      end

    {:noreply, Sigil.Live.assign(socket, messages: messages, loading: false)}
  end

  def handle_info({:sigil_error, reason}, socket) do
    error_text = "Sorry, something went wrong. Please try again."

    require Logger
    Logger.error("[ChatLive] Agent error: #{inspect(reason)}")

    messages = socket.assigns.messages
    last = List.last(messages)

    messages =
      if last && last.role == "ai" do
        List.replace_at(messages, -1, %{role: "ai", content: error_text})
      else
        messages ++ [%{role: "ai", content: error_text}]
      end

    {:noreply, Sigil.Live.assign(socket, messages: messages, loading: false)}
  end

  def handle_info({:sigil_tool_start, tool_name, _input}, socket) do
    messages = socket.assigns.messages
    last = List.last(messages)

    status_text =
      case tool_name do
        "check_calendar" -> "Checking the calendar…"
        "book_meeting" -> "Booking your meeting…"
        _ -> "Working…"
      end

    if last && last.role == "ai" && last.content == "" do
      updated = %{last | content: status_text}
      messages = List.replace_at(messages, -1, updated)
      {:noreply, Sigil.Live.assign(socket, messages: messages)}
    else
      {:noreply, socket}
    end
  end

  # Admin sent a response
  def handle_info({:new_message, %{role: "admin", content: content}}, socket) do
    messages = socket.assigns.messages ++ [%{role: "admin", content: content}]
    {:noreply, Sigil.Live.assign(socket, messages: messages, loading: false)}
  end

  # AI response persisted by agent on_complete — already shown via :sigil_complete
  def handle_info({:new_message, %{role: "ai", content: _}}, socket) do
    {:noreply, socket}
  end

  def handle_info({:trigger_ai_response, message}, socket) do
    messages = socket.assigns.messages ++ [%{role: "ai", content: ""}]
    socket = Sigil.Live.assign(socket, messages: messages, loading: true)
    dispatch_and_send(socket, message)
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # --- Dispatch & Routing ---

  defp dispatch_and_send(socket, message) do
    team = socket.assigns.team
    agent_configs = socket.assigns.agent_configs
    recent_context = Enum.take(socket.assigns.messages, -6)

    # Run dispatch in a Task to avoid blocking the LiveView process
    live_pid = self()

    Task.start(fn ->
      # Classify intent — returns a slug string
      target_slug = Journal.Dispatch.classify(message, recent_context, agent_configs)

      # Get the agent PID from the team (slugs are used as atom keys)
      agent_key = String.to_atom(target_slug)
      agent_pid = Sigil.Agent.Team.get_agent(team, agent_key)

      if agent_pid && Process.alive?(agent_pid) do
        Sigil.Agent.stream(agent_pid, message, live_pid)
      else
        send(live_pid, {:sigil_error, :agent_not_available})
      end
    end)

    {:noreply, Sigil.Live.assign(socket, loading: true)}
  end

  # --- Team Management ---

  defp start_team(agent_configs, conversation) do
    conv_id = if conversation, do: conversation.id, else: nil
    api_key = Application.get_env(:sigil, :anthropic_api_key)
    team_name = :"journal_#{conv_id || System.unique_integer([:positive])}"

    # Check if team already exists (for reconnection)
    case Sigil.Agent.Team.lookup(team_name) do
      {:ok, team} ->
        team

      {:error, _} ->
        # Build team members from DB configs — all using GenericAgent
        agents =
          Enum.map(agent_configs, fn config ->
            opts = [
              api_key: api_key,
              conversation_id: conv_id,
              model: config.model || "claude-sonnet-4-20250514",
              system_prompt: config.system_prompt,
              tools: config.tools || []
            ]

            {String.to_atom(config.slug), Journal.GenericAgent, opts}
          end)

        {:ok, team} =
          Sigil.Agent.Team.start(%{
            name: team_name,
            agents: agents,
            shared_memory: true
          })

        team
    end
  end

  # --- Helpers ---

  defp extract_response_text(%{content: content}), do: extract_text(content)
  defp extract_response_text(other), do: inspect(other)

  defp extract_text(content) when is_binary(content), do: content

  defp extract_text(blocks) when is_list(blocks) do
    Enum.map_join(blocks, "\n", fn
      %{"text" => text} -> text
      %{text: text} -> text
      _ -> ""
    end)
  end

  defp extract_text(other), do: to_string(other)

  defp welcome_message(nil), do: "Welcome! No assistant is currently configured."
  defp welcome_message(config), do: "Hi! I'm #{config.name}. Ask me anything about the journal, or let me know if you'd like to connect."

  defp resume_or_create_conversation(existing_conv_id, agent_config) do
    conversation =
      if existing_conv_id do
        try do
          conv = Journal.Conversations.get_conversation!(existing_conv_id)
          if conv.status == "active", do: conv, else: nil
        rescue
          Ecto.NoResultsError -> nil
        end
      end

    if conversation do
      db_messages = Enum.map(conversation.messages, &%{role: &1.role, content: &1.content})
      messages = [%{role: "ai", content: welcome_message(agent_config)} | db_messages]
      {conversation, messages}
    else
      agent_id = if agent_config, do: agent_config.id, else: nil

      {:ok, conv} =
        Journal.Conversations.create_conversation(%{
          agent_config_id: agent_id,
          status: "active"
        })

      {conv, [%{role: "ai", content: welcome_message(agent_config)}]}
    end
  end

  defp ai_unavailable_banner do
    """
    <div class="max-w-md mx-auto text-center py-12">
      <div class="inline-flex items-center justify-center h-12 w-12 rounded-full bg-amber-100 dark:bg-amber-900/30 mb-4">
        <svg class="h-6 w-6 text-amber-600 dark:text-amber-400" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126ZM12 15.75h.007v.008H12v-.008Z" />
        </svg>
      </div>
      <h3 class="text-sm font-semibold text-stone-900 dark:text-stone-100 mb-2">AI Chat Not Configured</h3>
      <p class="text-sm text-stone-500 mb-4">To enable the AI assistant, add your API key to the <code class="text-xs bg-stone-100 dark:bg-stone-800 px-1.5 py-0.5 rounded">.env</code> file:</p>
      <div class="bg-stone-100 dark:bg-stone-800 rounded-lg px-4 py-3 text-left">
        <code class="text-xs text-stone-600 dark:text-stone-400">ANTHROPIC_API_KEY=sk-ant-...</code>
      </div>
      <p class="text-xs text-stone-400 mt-3">Then restart the server.</p>
    </div>
    """
  end
end
