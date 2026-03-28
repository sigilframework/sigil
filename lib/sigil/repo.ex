if Code.ensure_loaded?(Ecto) do
  defmodule Sigil.Repo do
    @moduledoc """
    Ecto Repo for PostgreSQL.

    This module is only available when `ecto_sql` and `postgrex` are
    included in your dependencies.

    Configure in your application:

        config :sigil, Sigil.Repo,
          url: "postgres://localhost/sigil_dev",
          pool_size: 10
    """
    use Ecto.Repo,
      otp_app: :sigil,
      adapter: Ecto.Adapters.Postgres
  end
end
