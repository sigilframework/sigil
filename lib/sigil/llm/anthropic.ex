defmodule Sigil.LLM.Anthropic do
  @moduledoc """
  Anthropic Claude adapter for Sigil.LLM.

  Supports chat completions with tool use and streaming.

  ## Options

  - `:api_key` — Anthropic API key (required)
  - `:model` — Model name (default: `"claude-sonnet-4-20250514"`)
  - `:max_tokens` — Max tokens in response (default: `4096`)
  - `:temperature` — Sampling temperature (default: `0.7`)
  - `:tools` — List of tool definitions for function calling
  - `:system` — System prompt string
  """
  @behaviour Sigil.LLM

  @base_url "https://api.anthropic.com/v1"
  @default_model "claude-sonnet-4-20250514"
  @default_max_tokens 4096
  @api_version "2023-06-01"

  @impl true
  def chat(messages, opts) do
    api_key = Keyword.fetch!(opts, :api_key)

    body =
      build_body(messages, opts)
      |> Jason.encode!()

    case Req.post("#{@base_url}/messages",
           body: body,
           headers: headers(api_key),
           receive_timeout: 120_000
         ) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, parse_response(body)}

      {:ok, %{status: status, body: body}} ->
        {:error, %{status: status, body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def stream(messages, opts) do
    api_key = Keyword.fetch!(opts, :api_key)

    body =
      messages
      |> build_body(opts)
      |> Map.put("stream", true)
      |> Jason.encode!()

    stream =
      Stream.resource(
        fn ->
          {:ok, resp} =
            Req.post("#{@base_url}/messages",
              body: body,
              headers: headers(api_key),
              into: :self,
              receive_timeout: 120_000
            )

          resp
        end,
        fn resp ->
          receive do
            {ref, {:data, data}} when ref == resp.body.ref ->
              chunks = parse_sse_chunks(data)
              {chunks, resp}

            {ref, :done} when ref == resp.body.ref ->
              {:halt, resp}
          after
            30_000 -> {:halt, resp}
          end
        end,
        fn _resp -> :ok end
      )

    {:ok, stream}
  end

  @impl true
  def embed(_input, _opts) do
    # Anthropic doesn't have an embeddings API — delegate to OpenAI
    {:error, :not_supported}
  end

  # Private helpers

  defp headers(api_key) do
    [
      {"content-type", "application/json"},
      {"x-api-key", api_key},
      {"anthropic-version", @api_version}
    ]
  end

  defp build_body(messages, opts) do
    model = Keyword.get(opts, :model, @default_model)
    max_tokens = Keyword.get(opts, :max_tokens, @default_max_tokens)
    temperature = Keyword.get(opts, :temperature, 0.7)
    system = Keyword.get(opts, :system)
    tools = Keyword.get(opts, :tools, [])

    body = %{
      "model" => model,
      "max_tokens" => max_tokens,
      "temperature" => temperature,
      "messages" => format_messages(messages)
    }

    body = if system, do: Map.put(body, "system", system), else: body

    if tools != [] do
      Map.put(body, "tools", Enum.map(tools, &format_tool/1))
    else
      body
    end
  end

  defp format_messages(messages) do
    Enum.map(messages, fn msg ->
      %{
        "role" => to_string(msg.role),
        "content" => format_content(msg.content)
      }
    end)
  end

  defp format_content(content) when is_binary(content), do: content

  defp format_content(blocks) when is_list(blocks) do
    Enum.map(blocks, fn
      %{type: "tool_result"} = block ->
        %{
          "type" => "tool_result",
          "tool_use_id" => block.tool_use_id,
          "content" => to_string(block.content)
        }

      %{type: "text", text: text} ->
        %{"type" => "text", "text" => text}

      other ->
        other
    end)
  end

  defp format_tool(tool_module) when is_atom(tool_module) do
    params = tool_module.params()

    %{
      "name" => tool_module.name(),
      "description" => tool_module.description(),
      "input_schema" => params
    }
  end

  defp format_tool(tool_map) when is_map(tool_map), do: tool_map

  defp parse_response(%{"content" => content, "usage" => usage} = body) do
    text_parts =
      content
      |> Enum.filter(&(&1["type"] == "text"))
      |> Enum.map(& &1["text"])
      |> Enum.join("")

    tool_calls =
      content
      |> Enum.filter(&(&1["type"] == "tool_use"))
      |> Enum.map(fn tc ->
        %{
          id: tc["id"],
          name: tc["name"],
          input: tc["input"]
        }
      end)

    %{
      role: "assistant",
      content: text_parts,
      tool_calls: tool_calls,
      stop_reason: body["stop_reason"],
      token_count: (usage["input_tokens"] || 0) + (usage["output_tokens"] || 0),
      usage: %{
        input_tokens: usage["input_tokens"] || 0,
        output_tokens: usage["output_tokens"] || 0
      }
    }
  end

  defp parse_sse_chunks(data) do
    data
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, "data: "))
    |> Enum.map(&String.trim_leading(&1, "data: "))
    |> Enum.reject(&(&1 == "[DONE]"))
    |> Enum.flat_map(fn json_str ->
      case Jason.decode(json_str) do
        {:ok, %{"type" => "content_block_delta", "delta" => %{"text" => text}}} ->
          [{:chunk, text}]

        {:ok, %{"type" => "message_stop"}} ->
          [:done]

        {:ok,
         %{"type" => "content_block_start", "content_block" => %{"type" => "tool_use"} = block}} ->
          [{:tool_call_start, %{id: block["id"], name: block["name"]}}]

        {:ok, %{"type" => "content_block_delta", "delta" => %{"partial_json" => json}}} ->
          [{:tool_call_delta, json}]

        _ ->
          []
      end
    end)
  end
end
