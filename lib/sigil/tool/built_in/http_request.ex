defmodule Sigil.Tools.HTTPRequest do
  @moduledoc """
  Built-in tool for making HTTP requests.

  Allows agents to call external APIs with configurable
  methods, headers, and body.
  """
  use Sigil.Tool

  @impl true
  def name, do: "http_request"

  @impl true
  def description, do: "Make an HTTP request to an external URL"

  @impl true
  def params do
    %{
      "type" => "object",
      "properties" => %{
        "url" => %{"type" => "string", "description" => "The URL to request"},
        "method" => %{
          "type" => "string",
          "enum" => ["GET", "POST", "PUT", "PATCH", "DELETE"],
          "description" => "HTTP method (default: GET)"
        },
        "headers" => %{
          "type" => "object",
          "description" => "Request headers as key-value pairs",
          "additionalProperties" => %{"type" => "string"}
        },
        "body" => %{
          "type" => "string",
          "description" => "Request body (for POST/PUT/PATCH)"
        }
      },
      "required" => ["url"]
    }
  end

  @impl true
  def call(params, _context) do
    url = params["url"]
    method = String.downcase(params["method"] || "GET")
    headers = params["headers"] || %{}
    body = params["body"]

    header_list = Enum.map(headers, fn {k, v} -> {k, v} end)

    opts = [headers: header_list, receive_timeout: 15_000]
    opts = if body, do: Keyword.put(opts, :body, body), else: opts

    result =
      case method do
        "get" -> Req.get(url, opts)
        "post" -> Req.post(url, opts)
        "put" -> Req.put(url, opts)
        "patch" -> Req.patch(url, opts)
        "delete" -> Req.delete(url, opts)
        _ -> {:error, "Unsupported method: #{method}"}
      end

    case result do
      {:ok, %{status: status, body: resp_body}} ->
        body_str =
          case resp_body do
            b when is_binary(b) -> b
            b when is_map(b) -> Jason.encode!(b)
            b -> inspect(b)
          end

        {:ok, %{status: status, body: String.slice(body_str, 0, 10_000)}}

      {:error, reason} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end
end
