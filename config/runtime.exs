import Config

if config_env() in [:dev, :prod] do
  config :sigil,
    anthropic_api_key: System.get_env("ANTHROPIC_API_KEY"),
    openai_api_key: System.get_env("OPENAI_API_KEY")
end
