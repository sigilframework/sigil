defmodule Journal.UploadController do
  @moduledoc "Handles image uploads for the rich text editor."
  import Plug.Conn

  @allowed_types ~w(image/jpeg image/png image/gif image/webp image/svg+xml)
  @upload_dir "priv/static/uploads"

  def upload(conn, _opts) do
    if conn.assigns[:current_user] do
      handle_upload(conn)
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(401, Jason.encode!(%{error: "unauthorized"}))
      |> halt()
    end
  end

  defp handle_upload(conn) do
    case conn.body_params do
      %{"file" => %Plug.Upload{content_type: content_type, path: tmp_path, filename: original}} ->
        if content_type in @allowed_types do
          ext = Path.extname(original) |> String.downcase()
          name = "#{Ecto.UUID.generate()}#{ext}"

          upload_path = Path.join([File.cwd!(), @upload_dir])
          File.mkdir_p!(upload_path)

          dest = Path.join(upload_path, name)
          File.cp!(tmp_path, dest)

          conn
          |> put_resp_content_type("application/json")
          |> send_resp(200, Jason.encode!(%{url: "/uploads/#{name}"}))
          |> halt()
        else
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(400, Jason.encode!(%{error: "unsupported file type: #{content_type}"}))
          |> halt()
        end

      other ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{error: "no file provided", keys: Map.keys(other)}))
        |> halt()
    end
  end
end
