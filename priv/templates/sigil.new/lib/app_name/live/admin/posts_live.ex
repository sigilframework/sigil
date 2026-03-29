defmodule Journal.Admin.PostsLive do
  use Sigil.Live
  import Sigil.HTML, only: [escape: 1, escape_attr: 1]

  @impl true
  def mount(params, socket) do
    posts = Journal.Blog.list_posts()

    {post, editing, show_form} =
      case params do
        %{"id" => id} -> {Journal.Blog.get_post!(id), true, true}
        _ -> {nil, nil, false}
      end

    # Check if "new" route by path
    is_new =
      !post && params["_path"] != nil && String.ends_with?(to_string(params["_path"]), "/new")

    show_form = show_form || is_new
    editing = if is_new, do: false, else: editing

    form_assigns =
      if post do
        %{
          title: post.title,
          body: post.body,
          tags: Enum.join(post.tags, ", "),
          published: post.published,
          published_at: post.published_at
        }
      else
        if show_form do
          %{title: "", body: "", tags: "", published: false, published_at: nil}
        else
          nil
        end
      end

    {:ok,
     Sigil.Live.assign(socket,
       posts: posts,
       selected_post: post,
       editing: editing,
       form: form_assigns
     )}
  end

  @impl true
  def render(assigns) do
    sidebar_items =
      Enum.map_join(assigns.posts, "\n", fn post ->
        active_class =
          if assigns.selected_post && assigns.selected_post.id == post.id,
            do:
              "bg-stone-100 dark:bg-stone-800 border-l-2 border-stone-900 dark:border-stone-100",
            else: "hover:bg-stone-50 dark:hover:bg-stone-900/30 border-l-2 border-transparent"

        badge =
          if post.published,
            do: "<span class=\"h-1.5 w-1.5 rounded-full bg-emerald-500 flex-shrink-0\"></span>",
            else: "<span class=\"h-1.5 w-1.5 rounded-full bg-stone-400 flex-shrink-0\"></span>"

        """
        <a href="/admin/posts/#{post.id}/edit" class="block px-4 py-3 #{active_class} transition-colors">
          <div class="flex items-center justify-between gap-2">
            <span class="text-sm font-medium text-stone-900 dark:text-stone-100 truncate">#{escape(post.title || "Untitled")}</span>
            #{badge}
          </div>
          <div class="text-xs text-stone-500 mt-0.5">#{if post.published, do: "Published", else: "Draft"}</div>
        </a>
        """
      end)

    detail_html =
      if assigns.form do
        render_form(assigns)
      else
        """
        <div class="flex items-center justify-center h-full text-stone-400 dark:text-stone-600">
          <div class="text-center">
            <svg class="mx-auto h-12 w-12 mb-3" fill="none" viewBox="0 0 24 24" stroke-width="1" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M19.5 14.25v-2.625a3.375 3.375 0 0 0-3.375-3.375h-1.5A1.125 1.125 0 0 1 13.5 7.125v-1.5a3.375 3.375 0 0 0-3.375-3.375H8.25m0 12.75h7.5m-7.5 3H12M10.5 2.25H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 0 0-9-9Z" /></svg>
            <p class="text-sm font-medium">Select a post</p>
            <p class="text-xs mt-1">Click an item to edit, or create a new one</p>
          </div>
        </div>
        """
      end

    """
    <div class="flex flex-1 min-h-0">
      <aside class="w-72 border-r border-stone-200 dark:border-stone-800 flex flex-col bg-white dark:bg-stone-950">
        <div class="p-4 border-b border-stone-200 dark:border-stone-800 flex items-center justify-between">
          <h2 class="text-sm font-semibold text-stone-900 dark:text-stone-100 uppercase tracking-wider">Posts</h2>
          <a href="/admin/posts/new" class="text-xs font-medium text-stone-500 hover:text-stone-900 dark:hover:text-stone-100 transition-colors">+ New</a>
        </div>
        <div class="flex-1 overflow-y-auto divide-y divide-stone-100 dark:divide-stone-900">
          #{sidebar_items}
        </div>
      </aside>
      <main class="flex-1 overflow-y-auto">
        #{detail_html}
      </main>
    </div>
    """
  end

  defp render_form(assigns) do
    form = assigns.form
    title_label = if assigns.editing, do: "Edit Post", else: "New Post"
    escaped_body = escape_attr(form.body || "")

    # Toggle switch colors/position based on published state
    toggle_bg = if form.published, do: "bg-emerald-500", else: "bg-stone-300 dark:bg-stone-600"
    toggle_knob = if form.published, do: "translate-x-5", else: "translate-x-0"
    toggle_label = if form.published, do: "Published", else: "Draft"

    toggle_label_color =
      if form.published, do: "text-emerald-600 dark:text-emerald-400", else: "text-stone-500"

    # Format published_at for date input
    published_at_value =
      case form.published_at do
        %DateTime{} = dt -> Calendar.strftime(dt, "%Y-%m-%d")
        %NaiveDateTime{} = dt -> Calendar.strftime(dt, "%Y-%m-%d")
        nil -> ""
        other -> to_string(other)
      end

    """
    <!-- Quill CSS -->
    <link href="https://cdn.jsdelivr.net/npm/quill@2.0.3/dist/quill.bubble.css" rel="stylesheet" />

    <div class="max-w-4xl p-6">
      <div class="flex items-center justify-between">
        <h1 class="text-xl font-bold text-stone-900 dark:text-stone-100">#{title_label}</h1>
        <div class="flex items-center gap-4">
          <span id="save-status" class="text-xs font-medium"></span>
          <span class="text-sm font-medium #{toggle_label_color}">#{toggle_label}</span>
          <button type="button" sigil-click="toggle_published" class="relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent #{toggle_bg} transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-emerald-500 focus:ring-offset-2 dark:focus:ring-offset-stone-950" role="switch" aria-checked="#{form.published}" aria-label="Toggle published status">
            <span class="pointer-events-none relative inline-block h-5 w-5 #{toggle_knob} transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out"></span>
          </button>
          <span id="word-count" class="text-xs text-stone-400 tabular-nums"></span>
        </div>
      </div>

       <div class="flex flex-col sm:flex-row gap-4 pt-4">
          <div class="flex-1">
            <label for="tags" class="block text-xs font-medium text-stone-500 uppercase tracking-wider mb-1.5">Tags</label>
            <input type="text" id="tags" name="tags" value="#{escape(form.tags)}" placeholder="strategy, leadership, work"
              class="block w-full rounded-lg border border-stone-300 dark:border-stone-700 bg-white dark:bg-stone-900 px-3 py-2 text-sm text-stone-900 dark:text-stone-100 placeholder-stone-400 outline-none focus:border-stone-500 focus:ring-1 focus:ring-stone-500 transition-colors" />
          </div>
          <div>
            <label for="published_at" class="block text-xs font-medium text-stone-500 uppercase tracking-wider mb-1.5">Display Date</label>
            <input type="date" id="published_at" name="published_at" value="#{published_at_value}"
              class="block rounded-lg border border-stone-300 dark:border-stone-700 bg-white dark:bg-stone-900 px-3 py-2 text-sm text-stone-900 dark:text-stone-100 outline-none focus:border-stone-500 focus:ring-1 focus:ring-stone-500 transition-colors" />
          </div>
        </div>

      <div class="mt-6 space-y-6" id="post-form">
        <div>
          <input type="text" id="title" name="title" value="#{escape(form.title)}" required placeholder="Post title..."
            class="block w-full border-0 bg-transparent px-0 text-3xl font-serif font-medium text-stone-900 dark:text-stone-100 placeholder-stone-300 dark:placeholder-stone-600 outline-none focus:ring-0" />
          <div class="mt-2 h-px bg-stone-200 dark:bg-stone-800"></div>
        </div>

        <input type="hidden" id="body-input" name="body" value="#{escaped_body}" />
        <input type="hidden" id="published-input" name="published" value="#{form.published}" data-sigil-server />

        <div>
          <div id="sigil-editor" data-markdown="#{escaped_body}"
            class="min-h-[400px] text-lg leading-relaxed text-stone-800 dark:text-stone-200 prose prose-stone dark:prose-invert max-w-none
              [&_.ql-editor]:px-0 [&_.ql-editor]:py-0 [&_.ql-editor]:min-h-[400px]
              [&_.ql-editor.ql-blank::before]:text-stone-300 [&_.ql-editor.ql-blank::before]:dark:text-stone-600 [&_.ql-editor.ql-blank::before]:not-italic">
          </div>
        </div>

        <!-- Hidden auto-save trigger (clicked by editor.js) -->
        <button id="auto-save-trigger" sigil-click="auto_save" style="display:none"></button>

        #{if assigns.editing do
          "<div class=\"flex items-center justify-end gap-3 pt-4 border-t border-stone-200 dark:border-stone-800\">
            <button type=\"button\" onclick=\"if(confirm('Delete this post? This cannot be undone.')){this.removeAttribute('onclick');this.setAttribute('sigil-click','delete_post');this.click()}\" class=\"rounded-lg border border-red-300 dark:border-red-500/30 px-3.5 py-2 text-sm font-medium text-red-600 dark:text-red-400 hover:bg-red-50 dark:hover:bg-red-500/10 transition-colors\">Delete</button>
          </div>"
        else
          ""
        end}
      </div>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/quill@2.0.3/dist/quill.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/marked@15.0.4/marked.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/turndown@7.2.0/dist/turndown.js"></script>
    <script src="/assets/editor.js"></script>
    """
  end

  # --- Events ---

  @impl true
  def handle_event("auto_save", params, socket) do
    attrs = parse_post_params(params)

    result =
      if socket.assigns.editing do
        Journal.Blog.update_post(socket.assigns.selected_post, attrs)
      else
        Journal.Blog.create_post(attrs)
      end

    case result do
      {:ok, post} ->
        # Truly silent — update internal state without changing rendered assigns
        # This prevents Quill editor destruction from DOM replacement
        socket = put_in(socket.assigns[:selected_post], post)
        socket = put_in(socket.assigns[:editing], true)
        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, socket}
    end
  end

  # Removed dead `save_post` handler — auto_save replaces it

  def handle_event("delete_post", _params, socket) do
    if socket.assigns.selected_post, do: Journal.Blog.delete_post(socket.assigns.selected_post)
    posts = Journal.Blog.list_posts()

    {:noreply,
     Sigil.Live.assign(socket,
       posts: posts,
       selected_post: nil,
       editing: nil,
       form: nil
     )}
  end

  def handle_event("toggle_published", _params, socket) do
    form = socket.assigns.form
    new_published = !form.published

    # Persist toggle state to DB immediately
    if socket.assigns.selected_post do
      Journal.Blog.update_post(socket.assigns.selected_post, %{published: new_published})
    end

    {:noreply, Sigil.Live.assign(socket, form: %{form | published: new_published})}
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  # --- Helpers ---

  defp parse_post_params(params) do
    tags =
      (params["tags"] || "")
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    published_at =
      case params["published_at"] do
        "" -> nil
        nil -> nil
        date_str ->
          case Date.from_iso8601(date_str) do
            {:ok, date} -> DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
            _ -> nil
          end
      end

    %{
      title: params["title"],
      body: params["body"] || "",
      tags: tags,
      published: params["published"] == "true",
      published_at: published_at
    }
  end

end
