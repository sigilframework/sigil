defmodule Mix.Tasks.Sigil.SyncTemplates do
  @moduledoc """
  Sync a generated app's source files back into the framework templates.

  ## Usage

      mix sigil.sync_templates ../test_app

  This reverses the module name substitution that `mix sigil.new` performed,
  converting the app's module names back to `Journal.*` and copying the files
  into `priv/templates/sigil.new/`.

  ## What gets synced

  - `lib/<app_name>/**` → `priv/templates/sigil.new/lib/app_name/`
  - `priv/repo/seeds.exs` → `priv/templates/sigil.new/priv/repo/seeds.exs`
  - `priv/repo/migrations/` → `priv/templates/sigil.new/priv/repo/migrations/`
  - `priv/static/css/` → `priv/templates/sigil.new/priv/static/css/`
  - `priv/static/editor.js` → `priv/templates/sigil.new/priv/static/editor.js`

  ## What does NOT get synced

  Config files, mix.exs, Dockerfile, README, and other files that are
  generated inline by the generator (not from templates).
  """
  use Mix.Task

  @impl true
  def run(argv) do
    case argv do
      [path] ->
        sync(path)

      _ ->
        Mix.shell().error("""
        Usage: mix sigil.sync_templates <path_to_generated_app>

        Example: mix sigil.sync_templates ../test_app
        """)
    end
  end

  defp sync(app_path) do
    app_path = Path.expand(app_path)

    unless File.exists?(Path.join(app_path, "mix.exs")) do
      Mix.shell().error("No mix.exs found at #{app_path}. Is this a Sigil app?")
      exit({:shutdown, 1})
    end

    # Detect app name and module from the generated app
    {app_name, app_module} = detect_app(app_path)
    app_title = app_module |> String.replace(~r/([a-z])([A-Z])/, "\\1 \\2")

    Mix.shell().info("""

    🔄 Syncing templates from: #{app_path}
       App: #{app_module} (#{app_name})

    """)

    templates_dir = Path.join(File.cwd!(), "priv/templates/sigil.new")

    # Sync lib files
    source_lib = Path.join(app_path, "lib/#{app_name}")
    target_lib = Path.join(templates_dir, "lib/app_name")

    if File.exists?(source_lib) do
      sync_directory(source_lib, target_lib, app_name, app_module, app_title)
    else
      Mix.shell().error("No lib/#{app_name}/ directory found")
    end

    # Sync seeds
    sync_file(
      Path.join(app_path, "priv/repo/seeds.exs"),
      Path.join(templates_dir, "priv/repo/seeds.exs"),
      app_name,
      app_module,
      app_title
    )

    # Sync migrations
    source_migrations = Path.join(app_path, "priv/repo/migrations")
    target_migrations = Path.join(templates_dir, "priv/repo/migrations")

    if File.exists?(source_migrations) do
      # Clear old migrations and copy new ones
      if File.exists?(target_migrations), do: File.rm_rf!(target_migrations)
      File.mkdir_p!(target_migrations)

      source_migrations
      |> File.ls!()
      |> Enum.each(fn file ->
        sync_file(
          Path.join(source_migrations, file),
          Path.join(target_migrations, file),
          app_name,
          app_module,
          app_title
        )
      end)
    end

    # Sync static assets (binary copy, no substitution)
    sync_static(app_path, templates_dir, "priv/static/css")
    sync_static_file(app_path, templates_dir, "priv/static/editor.js")

    Mix.shell().info("""

    ✅ Templates synced!

       Verify with: mix sigil.new /tmp/verify_app
    """)
  end

  defp detect_app(app_path) do
    mix_content = File.read!(Path.join(app_path, "mix.exs"))

    app_name =
      case Regex.run(~r/app: :(\w+)/, mix_content) do
        [_, name] -> name
        _ -> Mix.raise("Could not detect app name from mix.exs")
      end

    app_module =
      case Regex.run(~r/defmodule (\w+)\.MixProject/, mix_content) do
        [_, mod] -> mod
        _ -> Mix.raise("Could not detect app module from mix.exs")
      end

    {app_name, app_module}
  end

  defp sync_directory(source_dir, target_dir, app_name, app_module, app_title) do
    source_dir
    |> Path.join("**/*.ex")
    |> Path.wildcard()
    |> Enum.each(fn source_file ->
      relative = Path.relative_to(source_file, source_dir)
      target_file = Path.join(target_dir, relative)
      sync_file(source_file, target_file, app_name, app_module, app_title)
    end)
  end

  defp sync_file(source, target, app_name, app_module, app_title) do
    if File.exists?(source) do
      content =
        File.read!(source)
        |> reverse_substitute(app_name, app_module, app_title)

      File.mkdir_p!(Path.dirname(target))
      File.write!(target, content)

      relative = Path.relative_to(target, File.cwd!())
      Mix.shell().info("  #{IO.ANSI.green()}✓#{IO.ANSI.reset()} #{relative}")
    end
  end

  defp sync_static(app_path, templates_dir, relative_dir) do
    source = Path.join(app_path, relative_dir)
    target = Path.join(templates_dir, relative_dir)

    if File.exists?(source) do
      if File.exists?(target), do: File.rm_rf!(target)
      File.cp_r!(source, target)
      Mix.shell().info("  #{IO.ANSI.green()}✓#{IO.ANSI.reset()} #{relative_dir}/ (binary copy)")
    end
  end

  defp sync_static_file(app_path, templates_dir, relative_path) do
    source = Path.join(app_path, relative_path)
    target = Path.join(templates_dir, relative_path)

    if File.exists?(source) do
      File.mkdir_p!(Path.dirname(target))
      File.cp!(source, target)
      Mix.shell().info("  #{IO.ANSI.green()}✓#{IO.ANSI.reset()} #{relative_path} (binary copy)")
    end
  end

  # Reverse the substitutions that mix sigil.new performed.
  # Order matters — more specific replacements first.
  defp reverse_substitute(content, app_name, app_module, app_title) do
    content
    # Module names → Journal
    |> String.replace(app_module <> ".", "Journal.")
    |> String.replace(app_module <> " do", "Journal do")
    |> String.replace(app_module <> ",", "Journal,")
    # Atom names → :journal
    |> String.replace(":" <> app_name <> ",", ":journal,")
    |> String.replace(":" <> app_name <> ")", ":journal)")
    # Database names
    |> String.replace(app_name <> "_dev", "journal_dev")
    |> String.replace(app_name <> "_test", "journal_test")
    |> String.replace(app_name <> "_prod", "journal_prod")
    # Branding → Journal defaults
    # (Only reverse the generic substitutions from sigil.new.
    #  Adam-specific branding stays if the user kept it.)
    |> String.replace(app_title, "Adam's Journal")
    |> String.replace(String.downcase(app_title), "Adam's journal")
  end
end
