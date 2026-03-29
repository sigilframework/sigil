defmodule MyApp.Admin.AgentsLive do
  use Sigil.Live
  import Sigil.HTML, only: [escape: 1]

  @impl true
  def mount(params, socket) do
    agents = MyApp.Agents.list_agents()

    {agent, editing, show_form} =
      case params do
        %{"id" => id} -> {MyApp.Agents.get_agent!(id), true, true}
        _ -> {nil, nil, false}
      end

    is_new = !agent && params["_path"] != nil && String.ends_with?(params["_path"], "/new")
    show_form = show_form || is_new
    editing = if is_new, do: false, else: editing

    form_assigns =
      if agent do
        %{name: agent.name, slug: agent.slug, system_prompt: agent.system_prompt, model: agent.model, active: agent.active, tools: agent.tools || []}
      else
        if show_form do
          %{name: "", slug: "", system_prompt: "", model: "claude-sonnet-4-20250514", active: true, tools: []}
        else
          nil
        end
      end

    {:ok,
     Sigil.Live.assign(socket,
       agents: agents,
       selected_agent: agent,
       editing: editing,
       form: form_assigns,
       saved: false,
       error: nil
     )}
  end

  @impl true
  def render(assigns) do
    sidebar_items =
      Enum.map_join(assigns.agents, "\n", fn agent ->
        active_class =
          if assigns.selected_agent && assigns.selected_agent.id == agent.id,
            do: "bg-stone-100 dark:bg-stone-800 border-l-2 border-stone-900 dark:border-stone-100",
            else: "hover:bg-stone-50 dark:hover:bg-stone-900/30 border-l-2 border-transparent"

        dot = if agent.active,
          do: "<span class=\"h-1.5 w-1.5 rounded-full bg-emerald-500 flex-shrink-0\"></span>",
          else: "<span class=\"h-1.5 w-1.5 rounded-full bg-stone-400 flex-shrink-0\"></span>"

        """
        <a href="/admin/agents/#{agent.id}/edit" class="block px-4 py-3 #{active_class} transition-colors">
          <div class="flex items-center justify-between gap-2">
            <span class="text-sm font-medium text-stone-900 dark:text-stone-100 truncate">#{escape(agent.name)}</span>
            #{dot}
          </div>
          <div class="text-xs text-stone-500 mt-0.5"><code class="text-[11px]">#{agent.slug}</code> · #{agent.model |> String.split("-") |> Enum.take(2) |> Enum.join(" ")}</div>
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
            <svg class="mx-auto h-12 w-12 mb-3" fill="none" viewBox="0 0 24 24" stroke-width="1" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M9.813 15.904 9 18.75l-.813-2.846a4.5 4.5 0 0 0-3.09-3.09L2.25 12l2.846-.813a4.5 4.5 0 0 0 3.09-3.09L9 5.25l.813 2.846a4.5 4.5 0 0 0 3.09 3.09L15.75 12l-2.846.813a4.5 4.5 0 0 0-3.09 3.09Z" /></svg>
            <p class="text-sm font-medium">Select an agent</p>
            <p class="text-xs mt-1">Click an item to edit, or create a new one</p>
          </div>
        </div>
        """
      end

    """
    <div class="flex flex-1 min-h-0">
      <aside class="w-72 border-r border-stone-200 dark:border-stone-800 flex flex-col bg-white dark:bg-stone-950">
        <div class="p-4 border-b border-stone-200 dark:border-stone-800 flex items-center justify-between">
          <h2 class="text-sm font-semibold text-stone-900 dark:text-stone-100 uppercase tracking-wider">Agents</h2>
          <a href="/admin/agents/new" class="text-xs font-medium text-stone-500 hover:text-stone-900 dark:hover:text-stone-100 transition-colors">+ New</a>
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
    title = if assigns.editing, do: "Edit Agent", else: "New Agent"
    action_text = if assigns.editing, do: "Update", else: "Create"
    checked = if form.active, do: "checked", else: ""

    saved_html = if assigns.saved,
      do: "<div class=\"rounded-lg bg-emerald-50 dark:bg-emerald-400/10 border border-emerald-200 dark:border-emerald-400/20 px-4 py-3 text-sm text-emerald-700 dark:text-emerald-400\">Agent saved!</div>",
      else: ""

    error_html = if assigns.error,
      do: "<div class=\"rounded-lg bg-red-50 dark:bg-red-500/10 border border-red-200 dark:border-red-500/20 px-4 py-3 text-sm text-red-600 dark:text-red-400\">#{assigns.error}</div>",
      else: ""

    delete_html = if assigns.editing,
      do: "<button type=\"button\" sigil-click=\"delete_agent\" class=\"rounded-lg border border-red-300 dark:border-red-500/30 px-3.5 py-2 text-sm font-medium text-red-600 dark:text-red-400 hover:bg-red-50 dark:hover:bg-red-500/10 transition-colors\">Delete</button>",
      else: ""

    model_options =
      available_models()
      |> Enum.map_join("\n", fn {value, label} ->
        selected = if form.model == value, do: "selected", else: ""
        "<option value=\"#{value}\" #{selected}>#{label}</option>"
      end)

    """
    <div class="max-w-2xl p-6">
      <h1 class="text-xl font-bold text-stone-900 dark:text-stone-100">#{title}</h1>

      <div class="mt-4 space-y-3">#{saved_html}#{error_html}</div>

      <form sigil-submit="save_agent" class="mt-6 space-y-6">
        <div>
          <label for="name" class="block text-sm font-medium text-stone-700 dark:text-stone-300">Name</label>
          <input type="text" id="name" name="name" value="#{escape(form.name)}" required placeholder="Blog Assistant"
            class="mt-2 block w-full rounded-lg border border-stone-300 dark:border-stone-700 bg-white dark:bg-stone-900 px-3 py-2 text-sm text-stone-900 dark:text-stone-100 placeholder-stone-400 outline-none focus:border-stone-500 focus:ring-1 focus:ring-stone-500 transition-colors" />
        </div>

        <div>
          <label for="slug" class="block text-sm font-medium text-stone-700 dark:text-stone-300">Slug <span class="text-stone-500 font-normal">(auto-generated if blank)</span></label>
          <input type="text" id="slug" name="slug" value="#{escape(form.slug)}" placeholder="blog-assistant"
            class="mt-2 block w-full rounded-lg border border-stone-300 dark:border-stone-700 bg-white dark:bg-stone-900 px-3 py-2 text-sm text-stone-900 dark:text-stone-100 placeholder-stone-400 outline-none focus:border-stone-500 focus:ring-1 focus:ring-stone-500 transition-colors" />
        </div>

        <div>
          <label for="model" class="block text-sm font-medium text-stone-700 dark:text-stone-300">Model</label>
          <select id="model" name="model"
            class="mt-2 block w-full rounded-lg border border-stone-300 dark:border-stone-700 bg-white dark:bg-stone-900 px-3 py-2 text-sm text-stone-900 dark:text-stone-100 outline-none focus:border-stone-500 focus:ring-1 focus:ring-stone-500 appearance-none transition-colors">
            #{model_options}
          </select>
        </div>

        <div>
          <label for="system_prompt" class="block text-sm font-medium text-stone-700 dark:text-stone-300">System Prompt</label>
          <textarea id="system_prompt" name="system_prompt" rows="10" placeholder="You are a helpful assistant..."
            class="mt-2 block w-full rounded-lg border border-stone-300 dark:border-stone-700 bg-white dark:bg-stone-900 px-3 py-2 text-sm text-stone-900 dark:text-stone-100 placeholder-stone-400 outline-none focus:border-stone-500 focus:ring-1 focus:ring-stone-500 resize-y transition-colors">#{escape(form.system_prompt)}</textarea>
        </div>

        <div>
          <label class="block text-sm font-medium text-stone-700 dark:text-stone-300 mb-2">Tools</label>
          <div class="space-y-2 rounded-lg border border-stone-200 dark:border-stone-700 p-3 bg-stone-50 dark:bg-stone-900/50">
            #{render_tool_checkboxes(form.tools)}
          </div>
          <p class="mt-1.5 text-xs text-stone-400">Select which tools this agent can use</p>
        </div>

        <div class="flex items-center gap-3">
          <input type="checkbox" id="active" name="active" value="true" #{checked}
            class="h-4 w-4 rounded border-stone-300 dark:border-stone-600 text-emerald-500 focus:ring-emerald-500" />
          <label for="active" class="text-sm text-stone-700 dark:text-stone-300">Published</label>
        </div>

        <div class="flex items-center justify-end gap-3 pt-4 border-t border-stone-200 dark:border-stone-800">
          #{delete_html}
          <button type="submit" class="rounded-lg bg-stone-900 dark:bg-stone-100 px-3.5 py-2 text-sm font-semibold text-white dark:text-stone-900 hover:bg-stone-800 dark:hover:bg-stone-200 transition-colors">#{action_text}</button>
        </div>
      </form>
    </div>
    """
  end

  # --- Events ---

  @impl true
  def handle_event("save_agent", params, socket) do
    # Collect checked tools from form params
    selected_tools =
      MyApp.ToolRegistry.all()
      |> Map.keys()
      |> Enum.filter(fn slug -> params["tool_#{slug}"] == "true" end)

    attrs = %{
      name: params["name"],
      slug: case String.trim(params["slug"] || "") do "" -> nil; s -> s end,
      system_prompt: params["system_prompt"] || "",
      model: params["model"] || "claude-sonnet-4-20250514",
      active: params["active"] == "true",
      tools: selected_tools
    }

    result =
      if socket.assigns.editing do
        MyApp.Agents.update_agent(socket.assigns.selected_agent, attrs)
      else
        MyApp.Agents.create_agent(attrs)
      end

    case result do
      {:ok, agent} ->
        {:noreply, Sigil.Live.assign(socket, __navigate__: "/admin/agents/#{agent.id}/edit")}

      {:error, changeset} ->
        {:noreply, Sigil.Live.assign(socket, error: inspect(changeset.errors), saved: false)}
    end
  end

  def handle_event("delete_agent", _params, socket) do
    if socket.assigns.selected_agent, do: MyApp.Agents.delete_agent(socket.assigns.selected_agent)
    agents = MyApp.Agents.list_agents()
    {:noreply, Sigil.Live.assign(socket, agents: agents, selected_agent: nil, editing: nil, form: nil, saved: false, error: nil)}
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  # --- Helpers ---

  defp available_models do
    [
      {"claude-sonnet-4-20250514", "Claude Sonnet 4 (balanced)"},
      {"claude-3-5-sonnet-20241022", "Claude 3.5 Sonnet"},
      {"claude-3-5-haiku-20241022", "Claude 3.5 Haiku (fast, cheap)"},
      {"claude-3-opus-20240229", "Claude 3 Opus (powerful)"},
      {"claude-3-haiku-20240307", "Claude 3 Haiku"},
      {"gpt-4o", "GPT-4o"},
      {"gpt-4o-mini", "GPT-4o Mini (fast, cheap)"},
      {"gpt-4-turbo", "GPT-4 Turbo"},
      {"o1", "o1 (reasoning)"},
      {"o1-mini", "o1 Mini"}
    ]
  end

  defp render_tool_checkboxes(selected_tools) do
    MyApp.ToolRegistry.all_with_info()
    |> Enum.sort_by(& &1.slug)
    |> Enum.map_join("\n", fn tool ->
      checked = if tool.slug in selected_tools, do: "checked", else: ""
      field_name = "tool_#{tool.slug}"

      """
      <label class="flex items-start gap-2.5 cursor-pointer">
        <input type="checkbox" name="#{field_name}" value="true" #{checked}
          class="mt-0.5 h-4 w-4 rounded border-stone-300 dark:border-stone-600 text-emerald-500 focus:ring-emerald-500" />
        <div>
          <span class="text-sm font-medium text-stone-700 dark:text-stone-300">#{tool.name}</span>
          <p class="text-xs text-stone-500 mt-0.5">#{tool.description}</p>
        </div>
      </label>
      """
    end)
  end
end
