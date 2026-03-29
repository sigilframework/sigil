defmodule Sigil.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/sigilframework/sigil"

  def project do
    [
      app: :sigil,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env()),

      # Hex
      description:
        "Full-stack framework for AI products — agents, memory, real-time UI, and admin in Elixir",
      package: package(),
      source_url: @source_url,
      homepage_url: "https://sigilframework.github.io/sigil",

      # Docs
      name: "Sigil",
      docs: [
        main: "Sigil",
        source_ref: "v#{@version}",
        extras: ["README.md", "CHANGELOG.md", "LICENSE"],
        groups_for_modules: [
          Agent: [
            Sigil.Agent,
            Sigil.Agent.State,
            Sigil.Agent.EventStore,
            Sigil.Agent.EventStore.Writer,
            Sigil.Agent.Checkpoint,
            Sigil.Agent.Observer,
            Sigil.Agent.Guard,
            Sigil.Agent.Team,
            Sigil.Agent.Telemetry,
            Sigil.Agent.TelemetryEvents
          ],
          LLM: [
            Sigil.LLM,
            Sigil.LLM.Anthropic,
            Sigil.LLM.OpenAI
          ],
          Tools: [
            Sigil.Tool
          ],
          Memory: [
            Sigil.Memory.Budget,
            Sigil.Memory.Context,
            Sigil.Memory.Session,
            Sigil.Memory.Summarizer,
            Sigil.Memory.Tokenizer
          ],
          Web: [
            Sigil.Router,
            Sigil.Layout,
            Sigil.Live,
            Sigil.Live.Handler,
            Sigil.Live.Channel,
            Sigil.Live.Diff,
            Sigil.Live.SessionStore,
            Sigil.Web.Static,
            Sigil.Web.Conn,
            Sigil.CSRF
          ],
          Auth: [
            Sigil.Auth,
            Sigil.Auth.User,
            Sigil.Auth.Password,
            Sigil.Auth.SessionPlug
          ]
        ]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {Sigil.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp package do
    [
      name: "sigil",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Discord" => "https://discord.com/channels/1487814726950981674/1487814838066483221"
      },
      files: ~w(
        lib priv/static priv/templates
        .formatter.exs mix.exs README.md LICENSE CHANGELOG.md
      )
    ]
  end

  defp deps do
    [
      # --- Core (always required) ---

      # HTTP client for LLM API calls
      {:req, "~> 0.5"},
      # JSON encoding/decoding
      {:jason, "~> 1.4"},
      # Telemetry
      {:telemetry, "~> 1.3"},

      # --- Optional: Database (for event sourcing, checkpoints) ---

      {:ecto_sql, "~> 3.12", optional: true},
      {:postgrex, "~> 0.19", optional: true},
      {:pgvector, "~> 0.3", optional: true},

      # --- Optional: Web layer (for Sigil.Live, Sigil.Router) ---

      {:bandit, "~> 1.6", optional: true},
      {:websock_adapter, "~> 0.5", optional: true},
      {:plug, "~> 1.16", optional: true},

      # --- Optional: Auth (for Sigil.Auth) ---

      {:bcrypt_elixir, "~> 3.0", optional: true},

      # --- Optional: Dev tools ---

      {:file_system, "~> 1.0", optional: true},

      # --- Dev/Test ---

      {:ex_doc, "~> 0.35", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["test"]
    ]
  end
end
