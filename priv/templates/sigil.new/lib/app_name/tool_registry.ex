defmodule MyApp.ToolRegistry do
  @moduledoc """
  Maps tool slugs to their modules. This is the single source of truth
  for what tools exist in the application.

  Tools are defined in code (they must be — they contain logic), but
  registered here so the admin UI can assign them to agents.
  """

  @tools %{
    "check_calendar" => MyApp.Tools.CheckCalendar,
    "book_meeting" => MyApp.Tools.BookMeeting
  }

  @doc "All available tools as a map of slug => module."
  def all, do: @tools

  @doc "Get a tool module by slug."
  def get(slug), do: Map.get(@tools, slug)

  @doc "Resolve a list of tool slugs to their modules."
  def resolve(slugs) when is_list(slugs) do
    slugs
    |> Enum.map(&get/1)
    |> Enum.reject(&is_nil/1)
  end

  def resolve(_), do: []

  @doc "All tools with metadata for the admin UI."
  def all_with_info do
    Enum.map(@tools, fn {slug, mod} ->
      config = config_for(slug)

      %{
        slug: slug,
        module: mod,
        name: mod.name(),
        description: mod.description(),
        params: mod.params(),
        category: config[:category] || :built_in,
        config_key: config[:config_key],
        status: check_status(config[:config_key])
      }
    end)
  end

  # Per-tool metadata (category, config requirements)
  defp config_for("check_calendar"), do: [category: :integration, config_key: {:my_app, :google_calendar}]
  defp config_for("book_meeting"), do: [category: :integration, config_key: {:my_app, :google_calendar}]
  defp config_for(_), do: [category: :built_in, config_key: nil]

  defp check_status(nil), do: :active
  defp check_status({app, key}) do
    config = Application.get_env(app, key)
    if config && config[:credentials], do: :active, else: :demo
  end
end
