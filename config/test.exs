import Config

config :sigil,
  anthropic_api_key: "test_key",
  openai_api_key: "test_key"

# Do not configure Repo for tests — tests run without a database
# If you need database tests, add:
# config :sigil, Sigil.Repo,
#   database: "sigil_test",
#   username: "postgres",
#   password: "postgres",
#   hostname: "localhost",
#   pool: Ecto.Adapters.SQL.Sandbox

config :logger, level: :warning
