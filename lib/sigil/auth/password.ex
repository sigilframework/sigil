if Code.ensure_loaded?(Bcrypt) do
defmodule Sigil.Auth.Password do
  @moduledoc """
  Password hashing and verification using bcrypt.

  ## Usage

      hash = Sigil.Auth.Password.hash("my_password")
      true = Sigil.Auth.Password.verify("my_password", hash)
      false = Sigil.Auth.Password.verify("wrong", hash)
  """

  @doc "Hash a plaintext password."
  def hash(password) when is_binary(password) do
    Bcrypt.hash_pwd_salt(password)
  end

  @doc "Verify a password against a hash. Returns `true` or `false`."
  def verify(password, hash) when is_binary(password) and is_binary(hash) do
    Bcrypt.verify_pass(password, hash)
  end

  @doc """
  Dummy check to prevent timing attacks.
  Call this when the user doesn't exist to keep response time consistent.
  """
  def no_user_verify do
    Bcrypt.no_user_verify()
  end
end
end
