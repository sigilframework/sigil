defmodule MyApp.Admin.DashboardLive do
  use Sigil.Live
  import Sigil.HTML, only: [escape: 1]

  @impl true
  def mount(_params, socket) do
    posts = MyApp.Blog.list_posts()
    conversations = MyApp.Conversations.list_conversations(limit: 5)

    published_count = Enum.count(posts, & &1.published)
    draft_count = Enum.count(posts, &(!&1.published))
    active_count = MyApp.Conversations.count_active()

    {:ok,
     Sigil.Live.assign(socket,
       published_count: published_count,
       draft_count: draft_count,
       conversation_count: active_count,
       recent_conversations: conversations
     )}
  end

  @impl true
  def render(assigns) do
    conversations_html =
      if assigns.recent_conversations == [] do
        """
        <tr>
          <td colspan="3" class="px-4 py-8 text-center text-sm text-stone-400 dark:text-stone-500">
            No conversations yet. Visitors can start one from the chat assistant.
          </td>
        </tr>
        """
      else
        Enum.map_join(assigns.recent_conversations, "\n", fn conv ->
          msg_count = length(conv.messages)
          preview = conv.title || "Untitled conversation"
          date = format_date(conv.inserted_at)

          """
          <tr class="hover:bg-stone-50 dark:hover:bg-stone-900/30 transition-colors">
            <td class="whitespace-nowrap py-4 pl-4 pr-3 text-sm">
              <span class="font-medium text-stone-900 dark:text-stone-100">#{escape(preview)}</span>
            </td>
            <td class="whitespace-nowrap px-3 py-4 text-sm text-stone-500">#{msg_count} messages</td>
            <td class="whitespace-nowrap px-3 py-4 text-sm text-stone-500">#{date}</td>
          </tr>
          """
        end)
      end

    """
    <div class="mx-auto max-w-5xl px-6 py-8 overflow-y-auto h-full">
      <h1 class="text-2xl font-bold text-stone-900 dark:text-stone-100">Dashboard</h1>

      <!-- Stats -->
      <div class="mt-6 grid grid-cols-3 gap-4">
        #{stat_card(assigns.conversation_count, "Active Conversations")}
        #{stat_card(assigns.published_count, "Posts")}
        #{stat_card(assigns.draft_count, "Drafts")}
      </div>

      <!-- Recent Conversations -->
      <div class="mt-10">
        <div class="flex items-center justify-between">
          <h2 class="text-lg font-semibold text-stone-900 dark:text-stone-100">Recent Conversations</h2>
          <a href="/admin/conversations" class="text-sm text-stone-500 hover:text-stone-900 dark:hover:text-stone-100 transition-colors">View all →</a>
        </div>
        <div class="mt-4 overflow-hidden rounded-xl border border-stone-200 dark:border-stone-800">
          <table class="min-w-full divide-y divide-stone-200 dark:divide-stone-800">
            <thead class="bg-stone-100/50 dark:bg-stone-900/50">
              <tr>
                <th scope="col" class="py-3.5 pl-4 pr-3 text-left text-xs font-semibold uppercase tracking-wider text-stone-500">Preview</th>
                <th scope="col" class="px-3 py-3.5 text-left text-xs font-semibold uppercase tracking-wider text-stone-500">Messages</th>
                <th scope="col" class="px-3 py-3.5 text-left text-xs font-semibold uppercase tracking-wider text-stone-500">Started</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-stone-200 dark:divide-stone-800">
              #{conversations_html}
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp stat_card(value, label) do
    """
    <div class="rounded-xl border border-stone-200 dark:border-stone-800 bg-white dark:bg-stone-900/50 p-5 text-center">
      <p class="text-3xl font-bold text-stone-900 dark:text-stone-100">#{value}</p>
      <p class="mt-1 text-xs font-medium uppercase tracking-wider text-stone-500">#{label}</p>
    </div>
    """
  end

  defp format_date(%NaiveDateTime{} = dt) do
    ago = time_ago(dt)
    abs_time = Calendar.strftime(dt, "%b %d at %H:%M")
    "#{ago} · #{abs_time}"
  end
  defp format_date(_), do: ""

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
