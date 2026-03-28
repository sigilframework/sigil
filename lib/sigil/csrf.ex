if Code.ensure_loaded?(Plug.Crypto) do
defmodule Sigil.CSRF do
  @moduledoc """
  Cross-Site Request Forgery (CSRF) protection for Sigil applications.

  Generates per-session tokens and verifies them on form submissions
  and WebSocket connections.

  ## How it works

  1. On HTTP page load, a CSRF token is generated and embedded in:
     - A `<meta>` tag in the HTML head
     - A hidden `<input>` injected into forms with `sigil-submit`

  2. The client JS reads the token from the meta tag and includes
     it in every WebSocket event.

  3. The server verifies the token before processing events.

  ## Token format

  Tokens are HMAC-SHA256 signatures of the session ID, using the
  application's `secret_key_base` as the key. This means:
  - No server-side token storage needed
  - Tokens are tied to a specific session
  - Tokens can't be forged without the secret key
  """

  @doc "Generate a CSRF token for the given session ID."
  def generate_token(session_id) do
    secret = secret_key_base()
    :crypto.mac(:hmac, :sha256, secret, session_id)
    |> Base.url_encode64(padding: false)
  end

  @doc "Verify a CSRF token against the expected session ID."
  def verify_token(token, session_id) when is_binary(token) and is_binary(session_id) do
    expected = generate_token(session_id)
    Plug.Crypto.secure_compare(token, expected)
  end

  def verify_token(_, _), do: false

  @doc "Generate the HTML meta tag for embedding the CSRF token."
  def meta_tag(session_id) do
    token = generate_token(session_id)
    ~s(<meta name="sigil-csrf" content="#{token}" />)
  end

  defp secret_key_base do
    Application.get_env(:sigil, :secret_key_base) ||
      Application.get_env(:sigil, :csrf_secret, "sigil-dev-secret-change-me-in-prod")
  end
end
end
