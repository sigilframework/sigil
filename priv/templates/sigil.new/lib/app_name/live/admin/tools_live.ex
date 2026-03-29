defmodule Journal.Admin.ToolsLive do
  @moduledoc "Read-only dashboard showing registered tools and their configuration status."
  use Sigil.Live

  @impl true
  def mount(_params, socket) do
    tools = Journal.ToolRegistry.all_with_info()

    # Look up which agents use each tool from the DB
    agents = Journal.Agents.list_agents()

    tools_with_agents =
      Enum.map(tools, fn tool ->
        used_by =
          agents
          |> Enum.filter(fn agent -> tool.slug in (agent.tools || []) end)
          |> Enum.map(& &1.name)

        Map.put(tool, :agents, used_by)
      end)

    {:ok, Sigil.Live.assign(socket, tools: tools_with_agents)}
  end

  @impl true
  def render(assigns) do
    tool_cards =
      assigns.tools
      |> Enum.sort_by(& &1.slug)
      |> Enum.map_join("\n", fn tool ->
        status_badge = status_badge(tool.status)
        category_badge = category_badge(tool.category)

        agent_tags =
          if tool.agents == [] do
            "<span class=\"text-xs text-stone-400 italic\">Not assigned to any agent</span>"
          else
            Enum.map_join(tool.agents, " ", fn agent ->
              "<span class=\"inline-flex items-center rounded-md bg-stone-100 dark:bg-stone-800 px-2 py-0.5 text-xs font-medium text-stone-600 dark:text-stone-400\">#{agent}</span>"
            end)
          end

        params_html =
          if tool.params != %{} do
            props = tool.params["properties"] || %{}

            param_rows =
              Enum.map_join(props, "\n", fn {name, spec} ->
                required_dot =
                  if name in (tool.params["required"] || []),
                    do: "<span class=\"text-amber-500\">*</span>",
                    else: ""

                """
                <div class="flex items-start gap-2 text-xs">
                  <code class="font-mono text-stone-700 dark:text-stone-300 bg-stone-100 dark:bg-stone-800 px-1.5 py-0.5 rounded">#{name}</code>#{required_dot}
                  <span class="text-stone-500">#{spec["description"] || spec["type"] || ""}</span>
                </div>
                """
              end)

            """
            <div class="mt-3 pt-3 border-t border-stone-100 dark:border-stone-800">
              <p class="text-xs font-medium text-stone-500 uppercase tracking-wider mb-2">Parameters</p>
              <div class="space-y-1.5">#{param_rows}</div>
            </div>
            """
          else
            ""
          end

        """
        <div class="rounded-xl border border-stone-200 dark:border-stone-800 bg-white dark:bg-stone-950 p-5 transition-all hover:border-stone-300 dark:hover:border-stone-700">
          <div class="flex items-start justify-between gap-3">
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2.5 flex-wrap">
                <h3 class="text-sm font-semibold text-stone-900 dark:text-stone-100">#{tool.name}</h3>
                #{category_badge}
                #{status_badge}
              </div>
              <p class="mt-1.5 text-sm text-stone-600 dark:text-stone-400 leading-relaxed">#{tool.description}</p>
              <div class="mt-3 flex items-center gap-1.5">
                <span class="text-xs text-stone-400">Used by:</span>
                #{agent_tags}
              </div>
            </div>
          </div>
          #{params_html}
        </div>
        """
      end)

    """
    <div class="flex flex-1 min-h-0">
      <div class="flex-1 overflow-y-auto">
        <div class="max-w-3xl mx-auto p-6">
          <div class="flex items-center justify-between mb-6">
            <div>
              <h1 class="text-xl font-bold text-stone-900 dark:text-stone-100">Tools</h1>
              <p class="text-sm text-stone-500 mt-1">Capabilities available to agents. Assign tools to agents on the <a href="/admin/agents" class="underline hover:text-stone-700 dark:hover:text-stone-300">Agents</a> page.</p>
            </div>
          </div>

          <div class="space-y-4">
            #{tool_cards}
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  # --- Helpers ---

  defp status_badge(:active) do
    "<span class=\"inline-flex items-center gap-1 rounded-full bg-emerald-50 dark:bg-emerald-400/10 px-2 py-0.5 text-xs font-medium text-emerald-700 dark:text-emerald-400\"><span class=\"h-1.5 w-1.5 rounded-full bg-emerald-500\"></span>Active</span>"
  end

  defp status_badge(:demo) do
    "<span class=\"inline-flex items-center gap-1 rounded-full bg-amber-50 dark:bg-amber-400/10 px-2 py-0.5 text-xs font-medium text-amber-700 dark:text-amber-400\"><span class=\"h-1.5 w-1.5 rounded-full bg-amber-500\"></span>Demo Mode</span>"
  end

  defp category_badge(:built_in) do
    "<span class=\"inline-flex items-center rounded-full bg-stone-100 dark:bg-stone-800 px-2 py-0.5 text-xs font-medium text-stone-500\">Built-in</span>"
  end

  defp category_badge(:integration) do
    "<span class=\"inline-flex items-center rounded-full bg-indigo-50 dark:bg-indigo-400/10 px-2 py-0.5 text-xs font-medium text-indigo-600 dark:text-indigo-400\">Integration</span>"
  end
end
