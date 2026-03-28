defmodule Sigil.CSRFTest do
  use ExUnit.Case, async: true

  test "generate_token produces a string" do
    token = Sigil.CSRF.generate_token("session-123")
    assert is_binary(token)
    assert String.length(token) > 0
  end

  test "verify_token succeeds with matching session" do
    token = Sigil.CSRF.generate_token("session-456")
    assert Sigil.CSRF.verify_token(token, "session-456")
  end

  test "verify_token fails with different session" do
    token = Sigil.CSRF.generate_token("session-789")
    refute Sigil.CSRF.verify_token(token, "different-session")
  end

  test "verify_token fails with invalid token" do
    refute Sigil.CSRF.verify_token("invalid-token", "session-123")
  end

  test "verify_token fails with nil inputs" do
    refute Sigil.CSRF.verify_token(nil, "session-123")
    refute Sigil.CSRF.verify_token("token", nil)
  end

  test "same session always generates same token (deterministic)" do
    t1 = Sigil.CSRF.generate_token("deterministic-test")
    t2 = Sigil.CSRF.generate_token("deterministic-test")
    assert t1 == t2
  end

  test "meta_tag produces valid HTML" do
    html = Sigil.CSRF.meta_tag("session-meta")
    assert html =~ ~r/<meta name="sigil-csrf" content="[^"]+" \/>/
  end
end
