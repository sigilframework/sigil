defmodule MyApp.EntryLive do
  use Sigil.Live
  import Sigil.HTML, only: [escape: 1]

  @impl true
  def mount(params, socket) do
    post = MyApp.Blog.get_post!(params["id"])
    {prev_post, next_post} = MyApp.Blog.adjacent_posts(post)
    {:ok, Sigil.Live.assign(socket, post: post, prev_post: prev_post, next_post: next_post)}
  end

  @impl true
  def render(assigns) do
    post = assigns.post
    date = format_date(post.published_at || post.inserted_at)

    tags_pills =
      Enum.map_join(post.tags, "", fn t ->
        "<span class=\"inline-flex items-center rounded-full bg-stone-100 dark:bg-stone-800 px-2.5 py-0.5 text-xs font-medium text-stone-600 dark:text-stone-400\">#{t}</span>"
      end)

    # Render markdown to HTML
    body_html =
      case Earmark.as_html(post.body || "", %Earmark.Options{smartypants: true}) do
        {:ok, html, _} -> html
        {:error, html, _} -> html
      end

    """
    <div class="mx-auto max-w-3xl px-6 py-8 lg:px-8 lg:py-16">

      <!-- Masthead (clickable back to home) -->
      <header class="flex flex-col items-center gap-2 mb-10 pb-8 border-b border-stone-200 dark:border-stone-800">
        <a href="/" class="group flex flex-col items-center gap-2.5">
          <img src="https://images.unsplash.com/photo-1519244703995-f4e0f30006d5?ixlib=rb-1.2.1&ixid=eyJhcHBfaWQiOjEyMDd9&auto=format&fit=facearea&facepad=2&w=256&h=256&q=80" alt="" class="size-10 rounded-full ring-2 ring-stone-200 dark:ring-stone-700 group-hover:ring-stone-400 dark:group-hover:ring-stone-500 transition-all" />
          <span class="font-serif text-lg font-medium tracking-tight text-stone-500 dark:text-stone-400 group-hover:text-stone-900 dark:group-hover:text-stone-100 transition-colors">My App</span>
        </a>
      </header>

      <article>
        <!-- Date left, tags right -->
        <div class="flex items-center justify-between">
          <time class="text-xs text-stone-500">#{date}</time>
          <div class="flex flex-wrap gap-1.5">#{tags_pills}</div>
        </div>

        <!-- Title -->
        <h1 class="mt-4 font-serif text-4xl sm:text-5xl lg:text-6xl font-medium tracking-tight leading-[0.95] text-stone-900 dark:text-stone-100">#{escape(post.title)}</h1>

        <!-- Rendered markdown content -->
        <div class="mt-10 pt-10 border-t border-stone-200 dark:border-stone-800
          prose prose-lg prose-stone dark:prose-invert max-w-none
          prose-headings:font-serif prose-headings:tracking-tight
          prose-h2:text-2xl prose-h2:mt-10 prose-h2:mb-4
          prose-h3:text-xl prose-h3:mt-8 prose-h3:mb-3
          prose-p:leading-8 prose-p:text-stone-700 dark:prose-p:text-stone-300
          prose-blockquote:border-stone-300 dark:prose-blockquote:border-stone-600 prose-blockquote:text-stone-600 dark:prose-blockquote:text-stone-400
          prose-a:text-stone-900 dark:prose-a:text-stone-100 prose-a:underline prose-a:underline-offset-2
          prose-img:rounded-xl prose-img:my-8 prose-img:max-h-[500px] prose-img:w-auto prose-img:mx-auto
          prose-pre:bg-stone-100 dark:prose-pre:bg-stone-800 prose-pre:rounded-lg
          prose-code:text-stone-800 dark:prose-code:text-stone-200 prose-code:bg-stone-100 dark:prose-code:bg-stone-800 prose-code:rounded prose-code:px-1.5 prose-code:py-0.5 prose-code:text-sm">
          #{body_html}
        </div>
      </article>

      <!-- Prev / Next Navigation -->
      #{render_nav(assigns.prev_post, assigns.next_post)}
    </div>
    """
  end

  defp render_nav(nil, nil), do: ""

  defp render_nav(prev, next) do
    prev_html =
      if prev do
        """
        <a href="/entry/#{prev.id}" class="group flex items-center gap-3 max-w-[45%]">
          <svg class="h-5 w-5 shrink-0 text-stone-400 group-hover:text-stone-600 dark:group-hover:text-stone-300 transition-colors" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M10.5 19.5 3 12m0 0 7.5-7.5M3 12h18" /></svg>
          <div class="min-w-0">
            <span class="block text-xs text-stone-400 uppercase tracking-wider">Previous</span>
            <span class="block text-sm font-medium text-stone-700 dark:text-stone-300 group-hover:text-stone-900 dark:group-hover:text-stone-100 truncate transition-colors">#{escape(prev.title)}</span>
          </div>
        </a>
        """
      else
        "<div></div>"
      end

    next_html =
      if next do
        """
        <a href="/entry/#{next.id}" class="group flex items-center gap-3 max-w-[45%] ml-auto text-right">
          <div class="min-w-0">
            <span class="block text-xs text-stone-400 uppercase tracking-wider">Next</span>
            <span class="block text-sm font-medium text-stone-700 dark:text-stone-300 group-hover:text-stone-900 dark:group-hover:text-stone-100 truncate transition-colors">#{escape(next.title)}</span>
          </div>
          <svg class="h-5 w-5 shrink-0 text-stone-400 group-hover:text-stone-600 dark:group-hover:text-stone-300 transition-colors" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M13.5 4.5 21 12m0 0-7.5 7.5M21 12H3" /></svg>
        </a>
        """
      else
        "<div></div>"
      end

    """
    <nav class="mt-16 pt-8 border-t border-stone-200 dark:border-stone-800 flex items-start justify-between gap-4">
      #{prev_html}
      #{next_html}
    </nav>
    """
  end

  @impl true
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp format_date(nil), do: ""
  defp format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%B %d, %Y")
  defp format_date(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%B %d, %Y")

end
