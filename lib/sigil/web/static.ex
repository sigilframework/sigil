if Code.ensure_loaded?(Plug) do
defmodule Sigil.Web.Static do
  @moduledoc """
  Serves static files from `priv/static/`.

  Works both as a Plug and as a direct function call from the router.
  """
  import Plug.Conn

  @doc """
  Serve a static file given a path list.

  Called from the router's catch-all `/assets/*path` route.
  """
  def serve(conn, path) when is_list(path) do
    file_path = Path.join(path)
    serve_file(conn, file_path)
  end

  defp serve_file(conn, file_path) do
    # Prevent path traversal
    if String.contains?(file_path, "..") do
      send_resp(conn, 403, "Forbidden")
    else
      full_path = resolve_path(file_path)

      if full_path && File.exists?(full_path) do
        content_type = MIME.from_path(full_path)

        conn
        |> put_resp_content_type(content_type)
        |> put_resp_header("cache-control", "public, max-age=3600")
        |> send_resp(200, File.read!(full_path))
      else
        send_resp(conn, 404, "Not Found")
      end
    end
  end

  defp resolve_path(file_path) do
    # Check app's priv/static first, then Sigil's own
    otp_app = Application.get_env(:sigil, :otp_app)

    if otp_app do
      app_path = Application.app_dir(otp_app, Path.join("priv/static", file_path))
      if File.exists?(app_path), do: app_path, else: sigil_path(file_path)
    else
      sigil_path(file_path)
    end
  end

  defp sigil_path(file_path) do
    path = Application.app_dir(:sigil, Path.join("priv/static", file_path))
    if File.exists?(path), do: path, else: nil
  end
end
end
