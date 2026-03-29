defmodule Journal.Components.SideNav do
  @moduledoc "Shared sidebar navigation component used by HomeLive and ChatLive."
  import Sigil.HTML, only: [escape: 1]

  def render(assigns) do
    tags_html =
      Enum.map_join(assigns[:tags] || [], "", fn tag ->
        "<span class=\"inline-flex items-center rounded-full border border-stone-300 dark:border-stone-700 bg-stone-100 dark:bg-stone-900 px-3 py-1 text-sm text-stone-600 dark:text-stone-400 hover:border-stone-400 dark:hover:border-stone-600 transition-colors cursor-default\">#{escape(tag)}</span>"
      end)

    recent_posts_html =
      (assigns[:recent_posts] || [])
      |> Enum.take(3)
      |> Enum.map_join("\n", fn post ->
        "<a href=\"/entry/#{post.id}\" class=\"block truncate text-sm text-stone-600 dark:text-stone-400 hover:text-stone-900 dark:hover:text-stone-200 transition-colors\">#{escape(post.title)}</a>"
      end)

    auth_link =
      if assigns[:current_user] do
        "<a href=\"/admin\" class=\"block text-xs text-stone-400 hover:text-stone-600 dark:hover:text-stone-300 transition-colors\">Admin</a>"
      else
        "<a href=\"/login\" class=\"block text-xs text-stone-400 hover:text-stone-600 dark:hover:text-stone-300 transition-colors\">Login</a>"
      end

    """
    <aside class="w-full lg:w-1/3 lg:max-w-md xl:max-w-lg border-b lg:border-b-0 lg:border-r border-stone-200 dark:border-stone-800 bg-stone-100/50 dark:bg-stone-900/40 lg:sticky lg:top-0 lg:h-screen lg:overflow-y-auto">
      <div class="px-6 py-8 lg:px-8 lg:py-10 flex flex-col min-h-full">
        <div class="space-y-8">
          <!-- Masthead -->
          <header class="pb-6 border-b border-stone-200 dark:border-stone-800">
            <a href="/" class="flex items-center gap-x-5">
              <img src="https://images.unsplash.com/photo-1519244703995-f4e0f30006d5?ixlib=rb-1.2.1&ixid=eyJhcHBfaWQiOjEyMDd9&auto=format&fit=facearea&facepad=2&w=256&h=256&q=80" alt="" class="size-14 rounded-full ring-2 ring-stone-300 dark:ring-stone-700" />
              <div>
                <h3 class="text-base font-semibold tracking-tight text-stone-900 dark:text-stone-100">Adam's Journal</h3>
                <p class="text-sm text-stone-500">Notes on strategy, systems, work, and life</p>
              </div>
            </a>
          </header>

          <!-- AI Assistant -->
          <section>
            <a href="/chat/blog-assistant" class="group flex items-center gap-3 rounded-xl border border-stone-200 dark:border-stone-800 bg-white dark:bg-stone-900/50 px-4 py-3 hover:bg-stone-100 dark:hover:bg-stone-800/50 hover:border-stone-300 dark:hover:border-stone-700 transition-all">
              <span class="flex h-8 w-8 items-center justify-center rounded-lg bg-stone-100 dark:bg-stone-800 text-base">💬</span>
              <div>
                <span class="text-sm font-medium text-stone-800 dark:text-stone-200 group-hover:text-stone-900 dark:group-hover:text-stone-100">AI Assistant</span>
                <p class="text-xs text-stone-500">Ask a question or get in touch</p>
              </div>
            </a>
          </section>

          <!-- Recent Entries -->
          <section>
            <h2 class="text-xs font-semibold uppercase tracking-widest text-stone-500 mb-3">Recent</h2>
            <div class="space-y-2">
              #{recent_posts_html}
            </div>
          </section>

          <!-- Tags -->
          <section>
            <h2 class="text-xs font-semibold uppercase tracking-widest text-stone-500 mb-3">Tags</h2>
            <div class="flex flex-wrap gap-2">
              #{tags_html}
            </div>
          </section>
        </div>

        <!-- Footer — pinned to bottom -->
        <footer class="pt-6 mt-auto border-t border-stone-200 dark:border-stone-800 flex items-center justify-between">
          <a href="https://github.com/sigilframework/sigil" target="_blank" class="block text-xs text-stone-400 hover:text-stone-600 dark:hover:text-stone-300 transition-colors">Made with ❤️ by Sigil Framework</a>
          <div>#{auth_link}</div>
        </footer>
      </div>
    </aside>
    """
  end

end
