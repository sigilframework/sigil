defmodule Sigil.HTML do
  @moduledoc """
  HTML escaping utilities for Sigil views.

  Provides safe escaping of user content for rendering in HTML templates.
  Used by Live views to prevent XSS when interpolating dynamic content.
  """

  @doc """
  Escape a string for safe HTML rendering.

  Replaces `&`, `<`, `>`, and `"` with their HTML entity equivalents.
  Returns an empty string for nil input.

  ## Examples

      iex> Sigil.HTML.escape("<script>alert('xss')</script>")
      "&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt;"

      iex> Sigil.HTML.escape(nil)
      ""
  """
  @spec escape(String.t() | nil) :: String.t()
  def escape(nil), do: ""

  def escape(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end

  @doc """
  Escape a string for use in an HTML attribute value.

  In addition to standard HTML escaping, also encodes newlines
  as `&#10;` to preserve them in attribute values.

  ## Examples

      iex> Sigil.HTML.escape_attr("line 1\\nline 2")
      "line 1&#10;line 2"
  """
  @spec escape_attr(String.t() | nil) :: String.t()
  def escape_attr(nil), do: ""
  def escape_attr(text), do: text |> escape() |> String.replace("\n", "&#10;")
end
