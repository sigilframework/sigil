defmodule Journal.Admin.ConversationsLive do
  use Sigil.Live
  import Sigil.HTML, only: [escape: 1]

  @impl true
  def mount(params, socket) do
    conversations = Journal.Conversations.list_conversations(limit: 50)
    selected_id = params["id"]

    {selected, messages, agent_name} =
      if selected_id do
        load_conversation(selected_id)
      else
        {nil, [], nil}
      end

    # Subscribe to real-time updates if viewing a conversation
    if selected_id, do: Journal.ConversationPubSub.subscribe(selected_id)

    {:ok,
     Sigil.Live.assign(socket,
       conversations: conversations,
       selected: selected,
       selected_id: selected_id,
       messages: messages,
       agent_name: agent_name
     )}
  end

  @impl true
  def render(assigns) do
    sidebar_items =
      Enum.map_join(assigns.conversations, "\n", fn conv ->
        title = conv.title || "Untitled"
        msg_count = length(conv.messages)
        ago = time_ago(conv.updated_at)
        active_class = if assigns.selected_id == conv.id,
          do: "bg-stone-100 dark:bg-stone-800 border-l-2 border-stone-900 dark:border-stone-100",
          else: "hover:bg-stone-50 dark:hover:bg-stone-900/30 border-l-2 border-transparent"

        status_dot = if conv.status == "active",
          do: "<span class=\"h-1.5 w-1.5 rounded-full bg-emerald-500 flex-shrink-0\"></span>",
          else: "<span class=\"h-1.5 w-1.5 rounded-full bg-stone-400 flex-shrink-0\"></span>"

        """
        <a href="/admin/conversations/#{conv.id}" class="block px-4 py-3 #{active_class} transition-colors">
          <div class="flex items-center justify-between gap-2">
            <span class="text-sm font-medium text-stone-900 dark:text-stone-100 truncate">#{escape(title)}</span>
            #{status_dot}
          </div>
          <div class="text-xs text-stone-500 mt-0.5">#{msg_count} msgs · #{ago}</div>
        </a>
        """
      end)

    detail_html =
      if assigns.selected do
        render_detail(assigns)
      else
        """
        <div class="flex items-center justify-center h-full text-stone-400 dark:text-stone-600">
          <div class="text-center">
            <svg class="mx-auto h-12 w-12 mb-3" fill="none" viewBox="0 0 24 24" stroke-width="1" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M20.25 8.511c.884.284 1.5 1.128 1.5 2.097v4.286c0 1.136-.847 2.1-1.98 2.193-.34.027-.68.052-1.02.072v3.091l-3-3c-1.354 0-2.694-.055-4.02-.163a2.115 2.115 0 0 1-.825-.242m9.345-8.334a2.126 2.126 0 0 0-.476-.095 48.64 48.64 0 0 0-8.048 0c-1.131.094-1.976 1.057-1.976 2.192v4.286c0 .837.46 1.58 1.155 1.951m9.345-8.334V6.637c0-1.621-1.152-3.026-2.76-3.235A48.455 48.455 0 0 0 11.25 3c-2.115 0-4.198.137-6.24.402-1.608.209-2.76 1.614-2.76 3.235v6.226c0 1.621 1.152 3.026 2.76 3.235.577.075 1.157.14 1.74.194V21l4.155-4.155" /></svg>
            <p class="text-sm font-medium">Select a conversation</p>
            <p class="text-xs mt-1">Click an item on the left to view details</p>
          </div>
        </div>
        """
      end

    """
    <div class="flex" style="height: calc(100vh - 3.5rem)">
      <aside class="w-72 border-r border-stone-200 dark:border-stone-800 flex flex-col bg-white dark:bg-stone-950">
        <div class="p-4 border-b border-stone-200 dark:border-stone-800">
          <h2 class="text-sm font-semibold text-stone-900 dark:text-stone-100 uppercase tracking-wider">Conversations</h2>
        </div>
        <div class="flex-1 overflow-y-auto divide-y divide-stone-100 dark:divide-stone-900">
          #{sidebar_items}
        </div>
      </aside>
      <div class="flex-1 flex flex-col" style="height: calc(100vh - 3.5rem)">
        #{detail_html}
      </div>
    </div>
    """
  end

  defp render_detail(assigns) do
    conv = assigns.selected
    messages_html =
      Enum.map_join(assigns.messages, "\n", fn msg ->
        if msg.role == "user" do
          """
          <div class="flex justify-end">
            <div class="max-w-lg rounded-2xl rounded-br-sm bg-stone-900 dark:bg-stone-100 px-4 py-3 text-sm text-white dark:text-stone-900">#{escape(msg.content)}</div>
          </div>
          """
        else
          label = if msg.role == "admin", do: "Admin", else: "AI"
          badge_class = if msg.role == "admin",
            do: "bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400",
            else: "bg-stone-100 text-stone-600 dark:bg-stone-800 dark:text-stone-400"
          """
          <div class="flex items-start gap-3 max-w-lg">
            <div class="flex-shrink-0 mt-0.5 h-7 w-7 rounded-full bg-stone-200 dark:bg-stone-700 flex items-center justify-center">
              <svg class="h-3.5 w-3.5 text-stone-600 dark:text-stone-300" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M9.813 15.904 9 18.75l-.813-2.846a4.5 4.5 0 0 0-3.09-3.09L2.25 12l2.846-.813a4.5 4.5 0 0 0 3.09-3.09L9 5.25l.813 2.846a4.5 4.5 0 0 0 3.09 3.09L15.75 12l-2.846.813a4.5 4.5 0 0 0-3.09 3.09Z" /></svg>
            </div>
            <div>
              <span class="inline-flex items-center rounded-full #{badge_class} px-2 py-0.5 text-xs font-medium mb-1">#{label}</span>
              <div class="rounded-2xl rounded-bl-sm bg-stone-100 dark:bg-stone-800 px-4 py-3 text-sm text-stone-800 dark:text-stone-200">#{escape(msg.content)}</div>
            </div>
          </div>
          """
        end
      end)

    status_dot = if conv.status == "active",
      do: "<span class=\"h-2 w-2 rounded-full bg-emerald-500 inline-block\"></span>",
      else: "<span class=\"h-2 w-2 rounded-full bg-stone-400 inline-block\"></span>"

    """
    <!-- Header -->
    <div class="flex-shrink-0 border-b border-stone-200 dark:border-stone-800 bg-white dark:bg-stone-950 px-6 py-3">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-base font-semibold text-stone-900 dark:text-stone-100 flex items-center gap-2">#{escape(conv.title || "Untitled")} #{status_dot}</h1>
          <p class="text-xs text-stone-500">#{escape(assigns.agent_name || "Unknown")} · #{length(assigns.messages)} messages</p>
        </div>
      </div>
    </div>
    <!-- Messages -->
    <div class="flex-1 overflow-y-auto min-h-0 px-6 py-6" data-sigil-scroll="adminChat">
      <div class="space-y-4 max-w-3xl mx-auto">#{messages_html}</div>
    </div>
    <!-- Input -->
    <div class="border-t border-stone-200 dark:border-stone-800 bg-white dark:bg-stone-950 p-4 flex-shrink-0">
      <form sigil-event="admin_send" class="flex items-center gap-3">
        <input type="text" name="message" placeholder="Send as admin..." autocomplete="off"
               class="flex-1 rounded-xl border border-stone-300 dark:border-stone-700 bg-white dark:bg-stone-900 px-4 py-2.5 text-sm text-stone-900 dark:text-stone-100 placeholder-stone-400 focus:outline-none focus:ring-2 focus:ring-stone-500 focus:border-transparent" />
        <button type="submit" class="rounded-xl bg-stone-600 hover:bg-stone-700 text-white px-4 py-2.5 text-sm font-medium transition-colors">Send as Admin</button>
      </form>
    </div>
    """
  end

  # --- Events ---

  @impl true
  def handle_event("admin_send", %{"message" => message}, socket) when message != "" do
    conv_id = socket.assigns.selected_id
    Journal.Conversations.add_message(conv_id, "admin", message)
    Journal.ConversationPubSub.broadcast(conv_id, {:new_message, %{role: "admin", content: message}})
    messages = socket.assigns.messages ++ [%{role: "admin", content: message}]
    {:noreply, Sigil.Live.assign(socket, messages: messages)}
  end

  def handle_event("admin_send", _params, socket), do: {:noreply, socket}
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  # --- Real-time handlers ---

  @impl true
  def handle_info({:new_message, msg}, socket) do
    messages = socket.assigns.messages ++ [msg]
    {:noreply, Sigil.Live.assign(socket, messages: messages)}
  end

  def handle_info({:agent_chunk, text}, socket) do
    messages = socket.assigns.messages
    last = List.last(messages)
    if last && last.role in ["ai", "admin"] do
      updated = %{last | content: (last.content || "") <> text}
      messages = List.replace_at(messages, -1, updated)
      {:noreply, Sigil.Live.assign(socket, messages: messages)}
    else
      messages = messages ++ [%{role: "ai", content: text}]
      {:noreply, Sigil.Live.assign(socket, messages: messages)}
    end
  end

  def handle_info(:agent_done, socket), do: {:noreply, socket}
  def handle_info(_msg, socket), do: {:noreply, socket}

  # --- Helpers ---

  defp load_conversation(id) do
    conv = Journal.Conversations.get_conversation!(id)
    messages = Enum.map(conv.messages, &%{role: &1.role, content: &1.content})
    agent_name = if conv.agent_config, do: conv.agent_config.name, else: "Unknown"
    {conv, messages, agent_name}
  end

  defp time_ago(%NaiveDateTime{} = dt) do
    diff = NaiveDateTime.diff(NaiveDateTime.utc_now(), dt, :second)
    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      diff < 604_800 -> "#{div(diff, 86400)}d ago"
      true -> "#{div(diff, 604_800)}w ago"
    end
  end
end
