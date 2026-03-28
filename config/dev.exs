import Config

config :logger, level: :debug

# Database (optional — only needed for event sourcing/checkpoints)
config :sigil, Sigil.Repo,
  database: "sigil_dev",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 5432,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# Web server (optional — starts Bandit on this port)
# config :sigil, port: 4000
