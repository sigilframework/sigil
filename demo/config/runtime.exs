import Config

# Runtime config — reads from environment variables at startup
config :sigil_demo, SigilDemo.Repo,
  url: System.get_env("DATABASE_URL") || "ecto://postgres:postgres@db/sigil_demo",
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

config :sigil,
  port: String.to_integer(System.get_env("PORT") || "4000"),
  secret_key_base:
    System.get_env("SECRET_KEY_BASE") ||
      "sigil-demo-dev-key-change-in-production-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  anthropic_api_key: System.get_env("ANTHROPIC_API_KEY")

config :sigil, :sigil_demo,
  host: System.get_env("PHX_HOST") || "localhost"
