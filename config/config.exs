import Config

config :sigil,
  ecto_repos: [Sigil.Repo]

# Import environment-specific config
import_config "#{config_env()}.exs"
