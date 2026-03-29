defmodule Mix.Tasks.Sigil.New do
  @moduledoc """
  Generate a new Sigil application.

  ## Usage

      mix sigil.new my_app
      mix sigil.new my_app --no-git

  This scaffolds a complete AI-powered application with:
  - Blog with rich text editor
  - AI chat interface with multi-agent routing
  - Admin dashboard (agents, tools, posts, conversations)
  - DB-driven agent configuration (zero agent code)
  - Calendar integration tools
  - Deployment files (Dockerfile, render.yaml)

  ## Requirements

  - Elixir 1.15+
  - PostgreSQL
  """
  use Mix.Task

  @switches [git: :boolean]
  @default_opts [git: true]

  @impl true
  def run(argv) do
    case OptionParser.parse!(argv, strict: @switches) do
      {opts, [path]} ->
        opts = Keyword.merge(@default_opts, opts)
        app_name = Path.basename(path)
        app_module = Macro.camelize(app_name)

        if app_name =~ ~r/^[a-z][a-z0-9_]*$/ do
          generate(path, app_name, app_module, opts)
        else
          Mix.shell().error("""
          App name must start with a lowercase letter and contain only
          lowercase letters, numbers, and underscores.

          Got: #{app_name}
          """)
        end

      {_, []} ->
        Mix.shell().info("""
        Usage: mix sigil.new my_app

        Scaffolds a complete AI-powered application.
        """)

      {_, _} ->
        Mix.shell().error("Expected a single argument (the app name)")
    end
  end

  defp generate(path, app_name, app_module, opts) do
    Mix.shell().info("""

    ⚡ Creating Sigil app: #{app_module}

    """)

    bindings = %{
      app_name: app_name,
      app_module: app_module,
      secret_key_base: random_string(64),
      signing_salt: random_string(8)
    }

    # Generate all files
    files = template_files(bindings)

    for {file_path, content} <- files do
      full_path = Path.join(path, file_path)
      File.mkdir_p!(Path.dirname(full_path))
      File.write!(full_path, content)
      Mix.shell().info("  #{IO.ANSI.green()}✓#{IO.ANSI.reset()} #{file_path}")
    end

    # Copy static assets
    copy_static_assets(path)

    # Create .env.example
    env_example = """
    # Required — get yours at https://console.anthropic.com
    ANTHROPIC_API_KEY=sk-ant-...

    # Optional: Google Calendar integration
    # GOOGLE_CALENDAR_ID=your-calendar@group.calendar.google.com
    # GOOGLE_CREDENTIALS_JSON={"type":"service_account",...}
    """

    File.write!(Path.join(path, ".env.example"), env_example)
    Mix.shell().info("  #{IO.ANSI.green()}✓#{IO.ANSI.reset()} .env.example")

    # Prompt for API key
    api_key = prompt_api_key()

    if api_key && api_key != "" do
      File.write!(Path.join(path, ".env"), "ANTHROPIC_API_KEY=#{api_key}\n")
      Mix.shell().info("  #{IO.ANSI.green()}✓#{IO.ANSI.reset()} .env (API key saved)")
    else
      File.write!(Path.join(path, ".env"), "ANTHROPIC_API_KEY=\n")

      Mix.shell().info(
        "  #{IO.ANSI.yellow()}○#{IO.ANSI.reset()} .env (no API key — add it later)"
      )
    end

    # Initialize git
    if opts[:git] do
      System.cmd("git", ["init", path], stderr_to_stdout: true)
      Mix.shell().info("  #{IO.ANSI.green()}✓#{IO.ANSI.reset()} Initialized git repository")
    end

    Mix.shell().info("""

    ✅ #{app_module} created successfully!

    Next steps:

        cd #{path}
        mix setup        # Install deps, create DB, run migrations, seed
        mix sigil.server  # Start at http://localhost:4000

    #{if api_key == "" || is_nil(api_key), do: "    ⚠️  Set your API key: edit .env and add ANTHROPIC_API_KEY\n", else: ""}Deploy to Render (one click):

        Push to GitHub, then click the "Deploy to Render" button in your README.

    Admin login: admin@example.com / admin123

    """)
  end

  # --- Template Files ---

  defp template_files(b) do
    [
      {"mix.exs", mix_exs(b)},
      {"config/config.exs", config_exs(b)},
      {"config/runtime.exs", runtime_exs(b)},
      {"lib/#{b.app_name}/application.ex", application_ex(b)},
      {"lib/#{b.app_name}/repo.ex", repo_ex(b)},
      {"lib/#{b.app_name}/router.ex", router_ex(b)},
      {"lib/#{b.app_name}/layout.ex", layout_ex(b)},
      {"lib/#{b.app_name}/auth_controller.ex", auth_controller_ex(b)},
      {"lib/#{b.app_name}/upload_controller.ex", upload_controller_ex(b)},
      {"lib/#{b.app_name}/blog.ex", blog_ex(b)},
      {"lib/#{b.app_name}/agents.ex", agents_ex(b)},
      {"lib/#{b.app_name}/conversations.ex", conversations_ex(b)},
      {"lib/#{b.app_name}/conversation_pubsub.ex", conversation_pubsub_ex(b)},
      {"lib/#{b.app_name}/dispatch.ex", dispatch_ex(b)},
      {"lib/#{b.app_name}/generic_agent.ex", generic_agent_ex(b)},
      {"lib/#{b.app_name}/tool_registry.ex", tool_registry_ex(b)},
      {"lib/#{b.app_name}/schemas/post.ex", schema_post_ex(b)},
      {"lib/#{b.app_name}/schemas/agent_config.ex", schema_agent_config_ex(b)},
      {"lib/#{b.app_name}/schemas/conversation.ex", schema_conversation_ex(b)},
      {"lib/#{b.app_name}/schemas/message.ex", schema_message_ex(b)},
      {"lib/#{b.app_name}/tools/check_calendar.ex", tool_check_calendar_ex(b)},
      {"lib/#{b.app_name}/tools/book_meeting.ex", tool_book_meeting_ex(b)},
      {"lib/#{b.app_name}/live/home_live.ex", live_home_ex(b)},
      {"lib/#{b.app_name}/live/entry_live.ex", live_entry_ex(b)},
      {"lib/#{b.app_name}/live/chat_live.ex", live_chat_ex(b)},
      {"lib/#{b.app_name}/live/login_live.ex", live_login_ex(b)},
      {"lib/#{b.app_name}/live/admin/dashboard_live.ex", live_admin_dashboard_ex(b)},
      {"lib/#{b.app_name}/live/admin/posts_live.ex", live_admin_posts_ex(b)},
      {"lib/#{b.app_name}/live/admin/agents_live.ex", live_admin_agents_ex(b)},
      {"lib/#{b.app_name}/live/admin/conversations_live.ex", live_admin_conversations_ex(b)},
      {"lib/#{b.app_name}/live/admin/tools_live.ex", live_admin_tools_ex(b)},
      {"lib/#{b.app_name}/components/side_nav.ex", component_side_nav_ex(b)},
      {"priv/repo/migrations/20260328000000_init_schema.exs", migration_ex(b)},
      {"priv/repo/seeds.exs", seeds_ex(b)},
      {"config/dev.exs", config_dev_exs(b)},
      {"config/prod.exs", config_prod_exs(b)},
      {"config/test.exs", config_test_exs(b)},
      {"Dockerfile", dockerfile(b)},
      {"render.yaml", render_yaml(b)},
      {".gitignore", gitignore()},
      {".formatter.exs", formatter()},
      {"README.md", readme(b)}
    ]
  end

  # --- Helpers ---

  defp random_string(length) do
    :crypto.strong_rand_bytes(length) |> Base.url_encode64() |> binary_part(0, length)
  end

  # --- Source file templates ---
  # Each function reads the corresponding template file from priv/templates/
  # and replaces module/app names.

  # Rather than duplicating the entire codebase inline, we read from
  # the installed templates directory. For the initial release, we
  # embed the templates directly.

  defp mix_exs(b) do
    """
    defmodule #{b.app_module}.MixProject do
      use Mix.Project

      def project do
        [
          app: :#{b.app_name},
          version: "0.1.0",
          elixir: "~> 1.15",
          start_permanent: Mix.env() == :prod,
          elixirc_paths: elixirc_paths(Mix.env()),
          aliases: aliases(),
          deps: deps()
        ]
      end

      def application do
        [
          extra_applications: [:logger, :crypto],
          mod: {#{b.app_module}.Application, []}
        ]
      end

      defp elixirc_paths(:test), do: ["lib", "test/support"]
      defp elixirc_paths(_), do: ["lib"]

      defp aliases do
        [
          setup: ["deps.get", "ecto.setup"],
          "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
          "ecto.reset": ["ecto.drop", "ecto.setup"]
        ]
      end

      defp deps do
        [
          {:sigil, "~> 0.1.0"},
          {:bandit, "~> 1.6"},
          {:plug, "~> 1.16"},
          {:websock_adapter, "~> 0.5"},
          {:ecto_sql, "~> 3.12"},
          {:postgrex, "~> 0.19"},
          {:jason, "~> 1.4"},
          {:bcrypt_elixir, "~> 3.0"},
          {:earmark, "~> 1.4"},
          {:file_system, "~> 1.0", only: :dev}
        ]
      end
    end
    """
  end

  defp config_exs(b) do
    """
    import Config

    config :#{b.app_name}, #{b.app_module}.Repo,
      database: "#{b.app_name}_dev",
      username: "postgres",
      password: "postgres",
      hostname: "localhost",
      pool_size: 10

    config :#{b.app_name},
      ecto_repos: [#{b.app_module}.Repo]

    config :sigil,
      secret_key_base: "#{b.secret_key_base}",
      repo: #{b.app_module}.Repo,
      auth_repo: #{b.app_module}.Repo,
      otp_app: :#{b.app_name}

    import_config "\#{config_env()}.exs"
    """
  end

  defp runtime_exs(b) do
    ~s"""
    import Config

    if config_env() == :prod do
      database_url =
        System.get_env("DATABASE_URL") ||
          raise "DATABASE_URL not set"

      config :#{b.app_name}, #{b.app_module}.Repo,
        url: database_url,
        pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
        ssl: true,
        ssl_opts: [verify: :verify_none]

      secret_key_base =
        System.get_env("SECRET_KEY_BASE") ||
          raise "SECRET_KEY_BASE not set"

      config :sigil,
        secret_key_base: secret_key_base
    end

    # API Keys (all environments)
    config :sigil,
      anthropic_api_key: System.get_env("ANTHROPIC_API_KEY")

    # Google Calendar (optional)
    if System.get_env("GOOGLE_CALENDAR_ID") do
      config :#{b.app_name}, :google_calendar,
        calendar_id: System.get_env("GOOGLE_CALENDAR_ID"),
        credentials: System.get_env("GOOGLE_CREDENTIALS_JSON")
    end
    """
  end

  defp config_dev_exs(b) do
    """
    import Config

    config :#{b.app_name}, #{b.app_module}.Repo,
      database: "#{b.app_name}_dev",
      username: "postgres",
      password: "postgres",
      hostname: "localhost",
      show_sensitive_data_on_connection_error: true,
      pool_size: 10

    config :logger, :console, format: "[$level] $message\\n"
    """
  end

  defp config_prod_exs(b) do
    _ = b

    """
    import Config

    config :logger, level: :info
    """
  end

  defp config_test_exs(b) do
    """
    import Config

    config :#{b.app_name}, #{b.app_module}.Repo,
      database: "#{b.app_name}_test",
      username: "postgres",
      password: "postgres",
      hostname: "localhost",
      pool: Ecto.Adapters.SQL.Sandbox
    """
  end

  # For the remaining templates, we read from priv/templates/sigil.new
  # and substitute module names. This keeps the generator in sync with
  # the reference app.

  defp application_ex(b), do: from_journal("application.ex", b)
  defp repo_ex(b), do: from_journal("repo.ex", b)
  defp router_ex(b), do: from_journal("router.ex", b)
  defp layout_ex(b), do: from_journal("layout.ex", b)
  defp auth_controller_ex(b), do: from_journal("auth_controller.ex", b)
  defp upload_controller_ex(b), do: from_journal("upload_controller.ex", b)
  defp blog_ex(b), do: from_journal("blog.ex", b)
  defp agents_ex(b), do: from_journal("agents.ex", b)
  defp conversations_ex(b), do: from_journal("conversations.ex", b)
  defp conversation_pubsub_ex(b), do: from_journal("conversation_pubsub.ex", b)
  defp dispatch_ex(b), do: from_journal("dispatch.ex", b)
  defp generic_agent_ex(b), do: from_journal("generic_agent.ex", b)
  defp tool_registry_ex(b), do: from_journal("tool_registry.ex", b)
  defp schema_post_ex(b), do: from_journal("schemas/post.ex", b)
  defp schema_agent_config_ex(b), do: from_journal("schemas/agent_config.ex", b)
  defp schema_conversation_ex(b), do: from_journal("schemas/conversation.ex", b)
  defp schema_message_ex(b), do: from_journal("schemas/message.ex", b)
  defp tool_check_calendar_ex(b), do: from_journal("tools/check_calendar.ex", b)
  defp tool_book_meeting_ex(b), do: from_journal("tools/book_meeting.ex", b)
  defp live_home_ex(b), do: from_journal("live/home_live.ex", b)
  defp live_entry_ex(b), do: from_journal("live/entry_live.ex", b)
  defp live_chat_ex(b), do: from_journal("live/chat_live.ex", b)
  defp live_login_ex(b), do: from_journal("live/login_live.ex", b)
  defp live_admin_dashboard_ex(b), do: from_journal("live/admin/dashboard_live.ex", b)
  defp live_admin_posts_ex(b), do: from_journal("live/admin/posts_live.ex", b)
  defp live_admin_agents_ex(b), do: from_journal("live/admin/agents_live.ex", b)
  defp live_admin_conversations_ex(b), do: from_journal("live/admin/conversations_live.ex", b)
  defp live_admin_tools_ex(b), do: from_journal("live/admin/tools_live.ex", b)
  defp component_side_nav_ex(b), do: from_journal("components/side_nav.ex", b)

  defp migration_ex(b) do
    from_file("priv/repo/migrations/20260328000000_init_schema.exs", b)
  end

  defp seeds_ex(b) do
    from_file("priv/repo/seeds.exs", b)
  end

  # Read a source file from the templates directory, substitute names
  defp templates_dir do
    Application.app_dir(:sigil, "priv/templates/sigil.new")
  end

  defp from_journal(relative_path, b) do
    path = Path.join([templates_dir(), "lib", "app_name", relative_path])
    read_and_substitute(path, b)
  end

  defp from_file(relative_path, b) do
    path = Path.join(templates_dir(), relative_path)
    read_and_substitute(path, b)
  end

  defp read_and_substitute(path, b) do
    app_title =
      b.app_module
      |> String.replace(~r/([a-z])([A-Z])/, "\\1 \\2")

    File.read!(path)
    # Branding — must run BEFORE module replacements because
    # "Adam's Journal," would otherwise match "Journal," first
    |> String.replace("Adam's Journal", app_title)
    |> String.replace("Adam's journal", String.downcase(app_title))
    |> String.replace("Adam's calendar", "the calendar")
    |> String.replace("Adam's scheduling assistant", "the scheduling assistant")
    |> String.replace("connect with Adam", "connect")
    |> String.replace("with Adam", "")
    |> String.replace("Adam isn't", "We aren't")
    |> String.replace("You represent Adam — be welcoming", "Be welcoming")
    |> String.replace("adam@example.com", "admin@example.com")
    |> String.replace("password123", "admin123")
    |> String.replace("Back to journal", "Back")
    # Module names
    |> String.replace("Journal.", b.app_module <> ".")
    |> String.replace("Journal do", b.app_module <> " do")
    |> String.replace("Journal,", b.app_module <> ",")
    # Atom names
    |> String.replace(":journal,", ":" <> b.app_name <> ",")
    |> String.replace(":journal)", ":" <> b.app_name <> ")")
    # Database names
    |> String.replace("journal_dev", b.app_name <> "_dev")
    |> String.replace("journal_test", b.app_name <> "_test")
  end

  # --- Deployment templates ---

  defp dockerfile(b) do
    """
    # Build stage
    FROM elixir:1.17-slim AS build

    RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*

    WORKDIR /app

    ENV MIX_ENV=prod

    # Install hex and rebar
    RUN mix local.hex --force && mix local.rebar --force

    # Install dependencies
    COPY mix.exs mix.lock ./
    RUN mix deps.get --only prod
    RUN mix deps.compile

    # Compile application
    COPY config config
    COPY lib lib
    COPY priv priv
    RUN mix compile

    # Build release
    RUN mix release

    # Runtime stage
    FROM debian:bookworm-slim AS runtime

    RUN apt-get update && \\
        apt-get install -y libssl3 libncurses6 locales ca-certificates && \\
        rm -rf /var/lib/apt/lists/*

    RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
    ENV LANG=en_US.UTF-8

    WORKDIR /app

    COPY --from=build /app/_build/prod/rel/#{b.app_name} ./

    ENV PORT=4000
    EXPOSE 4000

    CMD ["bin/#{b.app_name}", "start"]
    """
  end

  defp render_yaml(b) do
    """
    # render.yaml — Deploy to Render with one click
    # https://render.com/docs/infrastructure-as-code

    services:
      - type: web
        name: #{String.replace(b.app_name, "_", "-")}
        runtime: docker
        plan: free
        healthCheckPath: /
        envVars:
          - key: SECRET_KEY_BASE
            generateValue: true
          - key: ANTHROPIC_API_KEY
            sync: false
          - key: DATABASE_URL
            fromDatabase:
              name: #{String.replace(b.app_name, "_", "-")}-db
              property: connectionString

    databases:
      - name: #{String.replace(b.app_name, "_", "-")}-db
        plan: free
        databaseName: #{b.app_name}_prod
    """
  end

  defp gitignore do
    """
    /_build/
    /deps/
    /doc/
    /.fetch
    /priv/static/uploads/
    erl_crash.dump
    *.ez
    *.beam
    /config/*.secret.exs
    .env
    .elixir_ls/
    """
  end

  defp formatter do
    """
    [
      inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
    ]
    """
  end

  defp readme(b) do
    app_title = b.app_module |> String.replace(~r/([A-Z])/, " \\1") |> String.trim()

    """
    # #{app_title}

    Built with [Sigil](https://github.com/sigilframework/sigil) — the full-stack framework for AI products.

    ## Getting Started

    ```bash
    mix setup        # Install deps, create DB, seed data
    mix sigil.server  # Start at http://localhost:4000
    ```

    **Admin:** http://localhost:4000/admin
    **Login:** admin@example.com / admin123

    ## Deploy to Render

    [![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy)

    Set `ANTHROPIC_API_KEY` in your Render environment variables.

    ## Configuration

    | Variable | Required | Description |
    |----------|----------|-------------|
    | `ANTHROPIC_API_KEY` | Yes | Your Anthropic API key |
    | `GOOGLE_CALENDAR_ID` | No | Google Calendar ID for scheduling |
    | `GOOGLE_CREDENTIALS_JSON` | No | Google service account credentials |

    ## License

    MIT
    """
  end

  # --- Static assets ---

  defp copy_static_assets(path) do
    source = Path.join(templates_dir(), "priv/static")

    if File.exists?(source) do
      dest = Path.join(path, "priv/static")
      File.cp_r!(source, dest)
      Mix.shell().info("  #{IO.ANSI.green()}✓#{IO.ANSI.reset()} priv/static/ (assets)")
    end
  end

  defp prompt_api_key do
    Mix.shell().info("")

    Mix.shell().info(
      "  #{IO.ANSI.cyan()}?#{IO.ANSI.reset()} Anthropic API key (for AI chat — get one at https://console.anthropic.com)"
    )

    case Mix.shell().prompt("    Paste your key (or press Enter to skip)") do
      nil -> nil
      key -> String.trim(key)
    end
  end
end
