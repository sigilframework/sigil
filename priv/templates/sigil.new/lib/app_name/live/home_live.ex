defmodule MyApp.HomeLive do
  use Sigil.Live
  import Sigil.HTML, only: [escape: 1]

  @impl true
  def mount(_params, socket) do
    posts = MyApp.Blog.list_published_posts()
    tags = MyApp.Blog.list_tags()

    {:ok,
     Sigil.Live.assign(socket,
       posts: posts,
       tags: tags
     )}
  end

  @impl true
  def render(assigns) do
    posts_html =
      Enum.map_join(assigns.posts, "\n", fn post ->
        date = format_date(post.published_at || post.inserted_at)
        excerpt = strip_markdown(post.body) |> String.slice(0, 300)

        tags_pills =
          Enum.map_join(post.tags, "", fn t ->
            "<span class=\"inline-flex items-center rounded-full bg-stone-100 dark:bg-stone-800 px-2.5 py-0.5 text-xs font-medium text-stone-600 dark:text-stone-400\">#{t}</span>"
          end)

        """
        <article class="group">
          <div class="flex items-center gap-x-3 text-xs text-stone-500">
            <time>#{date}</time>
          </div>
          <h3 class="mt-3 font-serif text-3xl sm:text-4xl lg:text-5xl font-medium leading-[0.95] tracking-tight text-stone-900 dark:text-stone-100 group-hover:text-stone-600 dark:group-hover:text-stone-300 transition-colors">
            <a href="/entry/#{post.id}">#{escape(post.title)}</a>
          </h3>
          <p class="mt-4 text-base leading-7 text-stone-600 dark:text-stone-400 line-clamp-3">#{escape(excerpt)}</p>
          <div class="mt-4 flex flex-wrap gap-2">#{tags_pills}</div>
        </article>
        """
      end)

    sidebar =
      MyApp.Components.SideNav.render(%{
        tags: assigns.tags,
        recent_posts: Enum.take(assigns.posts, 3),
        current_user: assigns[:current_user]
      })

    """
    <div class="flex min-h-screen flex-col lg:flex-row">
      #{sidebar}

      <!-- Main — 2/3 -->
      <main class="flex-1 min-w-0 flex flex-col">
        <div class="flex-1 mx-auto max-w-3xl w-full px-6 py-8 lg:px-10 lg:py-12">
          <p class="text-xs font-semibold uppercase tracking-widest text-stone-500 mb-8">Recent entries</p>
          <div class="space-y-16">
            #{posts_html}
          </div>
        </div>

        <!-- Persistent Chat Input -->
        <div class="border-t border-stone-200 dark:border-stone-800 bg-white/80 dark:bg-stone-950/80 backdrop-blur-sm sticky bottom-0">
          <div class="max-w-3xl mx-auto px-6 py-4">
            <a href="/chat/blog-assistant" class="group relative flex items-center w-full rounded-xl border border-stone-300 dark:border-stone-700 bg-white dark:bg-stone-900 px-4 py-3 hover:border-stone-400 dark:hover:border-stone-600 hover:shadow-sm transition-all cursor-text">
              <div class="flex-shrink-0 h-5 w-5 text-stone-400 dark:text-stone-500 mr-3">
                <svg fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M9.813 15.904 9 18.75l-.813-2.846a4.5 4.5 0 0 0-3.09-3.09L2.25 12l2.846-.813a4.5 4.5 0 0 0 3.09-3.09L9 5.25l.813 2.846a4.5 4.5 0 0 0 3.09 3.09L15.75 12l-2.846.813a4.5 4.5 0 0 0-3.09 3.09ZM18.259 8.715 18 9.75l-.259-1.035a3.375 3.375 0 0 0-2.455-2.456L14.25 6l1.036-.259a3.375 3.375 0 0 0 2.455-2.456L18 2.25l.259 1.035a3.375 3.375 0 0 0 2.455 2.456L21.75 6l-1.036.259a3.375 3.375 0 0 0-2.455 2.456Z" /></svg>
              </div>
              <span class="text-sm text-stone-400 dark:text-stone-500 group-hover:text-stone-500 dark:group-hover:text-stone-400 transition-colors">Message Blog Assistant...</span>
              <div class="ml-auto flex-shrink-0 rounded-lg bg-stone-900 dark:bg-stone-100 p-1.5 text-white dark:text-stone-900">
                <svg class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M6 12 3.269 3.125A59.769 59.769 0 0 1 21.485 12 59.768 59.768 0 0 1 3.27 20.875L5.999 12Zm0 0h7.5" /></svg>
              </div>
            </a>
          </div>
        </div>
      </main>
    </div>
    """
  end

  @impl true
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp format_date(nil), do: ""
  defp format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%B %d, %Y")
  defp format_date(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%B %d, %Y")


  defp strip_markdown(nil), do: ""

  defp strip_markdown(text) do
    text
    # headings
    |> String.replace(~r/^\#{1,6}\s+/m, "")
    # bold
    |> String.replace(~r/\*\*(.+?)\*\*/s, "\\1")
    # italic
    |> String.replace(~r/\*(.+?)\*/s, "\\1")
    # strikethrough
    |> String.replace(~r/~~(.+?)~~/s, "\\1")
    # inline code
    |> String.replace(~r/`(.+?)`/s, "\\1")
    # images
    |> String.replace(~r/!\[.*?\]\(.*?\)/, "")
    # links (keep text)
    |> String.replace(~r/\[(.+?)\]\(.*?\)/, "\\1")
    # unordered lists
    |> String.replace(~r/^[-*+]\s+/m, "")
    # ordered lists
    |> String.replace(~r/^\d+\.\s+/m, "")
    # blockquotes
    |> String.replace(~r/^>\s+/m, "")
    # horizontal rules
    |> String.replace(~r/^---+$/m, "")
    # code blocks
    |> String.replace(~r/```[\s\S]*?```/, "")
    # collapse whitespace
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.trim()
  end
end
