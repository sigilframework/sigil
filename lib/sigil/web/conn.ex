if Code.ensure_loaded?(Plug) do
  defmodule Sigil.Web.Conn do
    @moduledoc """
    Response helpers for Sigil web handlers.

    Provides simple functions for common response patterns.
    """
    import Plug.Conn

    @doc "Send an HTML response."
    def html(conn, body, status \\ 200) do
      conn
      |> put_resp_content_type("text/html")
      |> send_resp(status, body)
    end

    @doc "Send a JSON response."
    def json(conn, data, status \\ 200) do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(status, Jason.encode!(data))
    end

    @doc "Redirect to a path."
    def redirect(conn, opts) do
      to = Keyword.fetch!(opts, :to)

      conn
      |> put_resp_header("location", to)
      |> send_resp(302, "")
    end
  end
end
