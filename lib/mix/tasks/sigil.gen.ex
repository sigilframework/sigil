defmodule Mix.Tasks.Sigil.Gen do
  @moduledoc """
  Generate code from a natural language prompt using AI.

  ## Usage

      mix sigil.gen "blog with posts that have a title, body, and published date"
      mix sigil.gen "user profile page with avatar upload"
      mix sigil.gen "contact form that sends email"

  This will:
  1. Send your prompt to the configured LLM
  2. Generate Ecto schemas, migrations, Live views, and routes
  3. Show you the files it will create
  4. Ask for confirmation before writing

  ## Configuration

  Set your LLM adapter and API key in config:

      config :sigil, :gen,
        adapter: Sigil.LLM.Anthropic,
        model: "claude-sonnet-4-20250514",
        api_key: System.get_env("ANTHROPIC_API_KEY")
  """
  use Mix.Task

  @impl true
  def run([]) do
    Mix.shell().error("Usage: mix sigil.gen \"description of what to build\"")
  end

  def run(argv) do
    prompt = Enum.join(argv, " ")
    Mix.shell().info("\n⚡ Generating code for: #{prompt}\n")

    # Ensure the app is started (for HTTP client)
    Mix.Task.run("app.start", ["--no-start"])
    Application.ensure_all_started(:req)

    config = gen_config()

    case generate_code(prompt, config) do
      {:ok, files} ->
        display_files(files)

        if Mix.shell().yes?("\nWrite #{length(files)} file(s)?") do
          write_files(files)
          Mix.shell().info("\n✅ Done! Files written successfully.")
          suggest_next_steps(files)
        else
          Mix.shell().info("\n❌ Cancelled.")
        end

      {:error, reason} ->
        Mix.shell().error("\n❌ Generation failed: #{inspect(reason)}")
    end
  end

  defp generate_code(prompt, config) do
    adapter = Keyword.fetch!(config, :adapter)
    api_key = Keyword.fetch!(config, :api_key)
    model = Keyword.get(config, :model, "claude-sonnet-4-20250514")

    # Detect app context
    app_module = detect_app_module()

    messages = [
      %{role: "user", content: build_prompt(prompt, app_module)}
    ]

    opts = [
      model: model,
      api_key: api_key,
      system: system_prompt(app_module),
      max_tokens: 8000
    ]

    Mix.shell().info("  Calling #{inspect(adapter)}...")

    case Sigil.LLM.chat(adapter, messages, opts) do
      {:ok, response} ->
        files = parse_files(response.content)
        {:ok, files}

      {:error, _} = error ->
        error
    end
  end

  defp system_prompt(app_module) do
    """
    You are a code generator for the Sigil framework (Elixir).
    Generate production-ready code for the user's request.

    RULES:
    1. Output ONLY code files in the format: === FILE: path/to/file.ex ===
    2. Use the app module name: #{app_module}
    3. The web module is: #{app_module}Web
    4. Generate these file types as needed:
       - Ecto schemas in lib/#{Macro.underscore(app_module)}/schemas/
       - Ecto migrations in priv/repo/migrations/
       - Live views in lib/#{Macro.underscore(app_module)}_web/pages/
       - Router entries as comments at the top saying "ADD TO ROUTER:"
    5. Use Sigil.Live (not Phoenix.LiveView)
       - `use Sigil.Live` for views
       - `Sigil.Live.assign(socket, key, value)` for assigns
       - `sigil-click="event_name"` for click handlers
       - `sigil-submit="event_name"` for form submissions
       - `sigil-change="event_name"` for input changes
    6. Use Ecto.Schema and Ecto.Changeset for data models
    7. Create a context module in lib/#{Macro.underscore(app_module)}/ for business logic
    8. Migration filenames must start with a timestamp: YYYYMMDDHHMMSS_name.exs
    9. Use current timestamp: #{timestamp()}
    10. Do NOT generate HTML layouts — the app already has one
    11. Do NOT include markdown, explanations, or anything outside of code files

    EXAMPLE OUTPUT FORMAT:
    === FILE: lib/my_app/blog.ex ===
    defmodule MyApp.Blog do
      # context code...
    end

    === FILE: lib/my_app/schemas/post.ex ===
    defmodule MyApp.Schemas.Post do
      use Ecto.Schema
      # schema code...
    end
    """
  end

  defp build_prompt(user_prompt, app_module) do
    """
    Generate Sigil framework code for:

    #{user_prompt}

    App module: #{app_module}
    Generate all necessary files: schemas, migrations, context, and Live views.
    """
  end

  defp parse_files(content) do
    # Split on === FILE: path === markers
    content
    |> String.split(~r/===\s*FILE:\s*/)
    |> Enum.drop(1)
    |> Enum.map(fn chunk ->
      case String.split(chunk, ~r/\s*===\s*\n/, parts: 2) do
        [path, code] ->
          path = String.trim(path)
          code = String.trim_trailing(code)
          {path, code}

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp display_files(files) do
    Mix.shell().info("\n📁 Files to generate:\n")

    for {path, code} <- files do
      lines = code |> String.split("\n") |> length()
      Mix.shell().info("  #{IO.ANSI.green()}✓#{IO.ANSI.reset()} #{path} (#{lines} lines)")
    end
  end

  defp write_files(files) do
    for {path, code} <- files do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, code <> "\n")
      Mix.shell().info("  #{IO.ANSI.green()}✓#{IO.ANSI.reset()} Written: #{path}")
    end
  end

  defp suggest_next_steps(files) do
    has_migration = Enum.any?(files, fn {path, _} -> String.contains?(path, "migration") end)
    has_router = Enum.any?(files, fn {_, code} -> String.contains?(code, "ADD TO ROUTER") end)

    Mix.shell().info("\n📋 Next steps:")

    if has_migration do
      Mix.shell().info("  1. Run: mix ecto.migrate")
    end

    if has_router do
      Mix.shell().info("  2. Add the routes shown above to your router")
    end

    Mix.shell().info(
      "  #{if has_migration or has_router, do: "3", else: "1"}. Restart your server: mix sigil.server"
    )
  end

  defp detect_app_module do
    case Mix.Project.get() do
      nil ->
        "MyApp"

      mod ->
        mod.project()[:app]
        |> Atom.to_string()
        |> Macro.camelize()
    end
  end

  defp timestamp do
    {{y, m, d}, {h, mi, s}} = :calendar.universal_time()

    :io_lib.format("~4..0B~2..0B~2..0B~2..0B~2..0B~2..0B", [y, m, d, h, mi, s])
    |> IO.iodata_to_binary()
  end

  defp gen_config do
    Application.get_env(:sigil, :gen,
      adapter: Sigil.LLM.Anthropic,
      model: "claude-sonnet-4-20250514",
      api_key: System.get_env("ANTHROPIC_API_KEY")
    )
  end
end
