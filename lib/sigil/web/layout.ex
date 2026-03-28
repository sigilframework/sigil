defmodule Sigil.Layout do
  @moduledoc """
  HTML layout system for Sigil applications.

  Layouts wrap your Live view content in a consistent HTML shell
  (head, nav, footer, etc.).

  ## Usage

      defmodule MyApp.Layouts do
        use Sigil.Layout

        def app(assigns, inner_content) do
          \"""
          <!DOCTYPE html>
          <html lang="en">
            <head>
              <meta charset="utf-8" />
              <meta name="viewport" content="width=device-width, initial-scale=1" />
              <title>\#{assigns[:page_title] || "My App"}</title>
              <link rel="stylesheet" href="/assets/app.css" />
            </head>
            <body>
              \#{inner_content}
              <script src="/assets/sigil.js"></script>
            </body>
          </html>
          \"""
        end
      end
  """

  defmacro __using__(_opts) do
    quote do
      @doc false
      def __layout__?, do: true
    end
  end

  @doc """
  Render a Live view inside a layout.

  Calls `layout_mod.layout_fn(assigns, inner_html)` to wrap content.
  """
  def render(layout_mod, layout_fn, assigns, inner_html) do
    apply(layout_mod, layout_fn, [assigns, inner_html])
  end

  @doc """
  Default layout when none is specified.
  Provides a minimal HTML shell with the Sigil client JS.
  """
  def default_layout(assigns, inner_content) do
    title = assigns[:page_title] || "Sigil App"
    csrf_meta = if assigns[:__csrf_token__] do
      ~s(<meta name="sigil-csrf" content="#{assigns[:__csrf_token__]}" />)
    else
      ""
    end

    """
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        #{csrf_meta}
        <title>#{title}</title>
        <link rel="stylesheet" href="/assets/app.css" />
      </head>
      <body>
        <div id="sigil-root" data-sigil-view="#{assigns[:__view__] || ""}">
          #{inner_content}
        </div>
        <script src="/assets/sigil.js"></script>
      </body>
    </html>
    """
  end
end
