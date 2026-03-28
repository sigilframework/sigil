defmodule Sigil.LLM.OpenAI do
  @moduledoc """
  OpenAI adapter for Sigil.LLM.

  Supports chat completions and embeddings.

  ## Options

  - `:api_key` — OpenAI API key (required)
  - `:model` — Model name (default: `"gpt-4o"`)
  - `:embedding_model` — Embedding model (default: `"text-embedding-3-small"`)
  - `:max_tokens` — Max tokens (default: `4096`)
  - `:temperature` — Sampling temperature (default: `0.7`)
  - `:tools` — List of tool definitions
  - `:system` — System prompt
  """
  @behaviour Sigil.LLM

  @base_url "https://api.openai.com/v1"
  @default_model "gpt-4o"
  @default_embedding_model "text-embedding-3-small"
  @default_max_tokens 4096

  @impl true
  def chat(messages, opts) do
    api_key = Keyword.fetch!(opts, :api_key)
    model = Keyword.get(opts, :model, @default_model)
    max_tokens = Keyword.get(opts, :max_tokens, @default_max_tokens)
    temperature = Keyword.get(opts, :temperature, 0.7)
    system = Keyword.get(opts, :system)
    tools = Keyword.get(opts, :tools, [])

    all_messages =
      if system do
        [%{"role" => "system", "content" => system} | format_messages(messages)]
      else
        format_messages(messages)
      end

    body =
      %{
        "model" => model,
        "messages" => all_messages,
        "max_tokens" => max_tokens,
        "temperature" => temperature
      }
      |> maybe_add_tools(tools)
      |> Jason.encode!()

    case Req.post("#{@base_url}/chat/completions",
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
    model = Keyword.get(opts, :model, @default_model)
    max_tokens = Keyword.get(opts, :max_tokens, @default_max_tokens)
    temperature = Keyword.get(opts, :temperature, 0.7)
    system = Keyword.get(opts, :system)
    tools = Keyword.get(opts, :tools, [])

    all_messages =
      if system do
        [%{"role" => "system", "content" => system} | format_messages(messages)]
      else
        format_messages(messages)
      end

    body =
      %{
        "model" => model,
        "messages" => all_messages,
        "max_tokens" => max_tokens,
        "temperature" => temperature,
        "stream" => true
      }
      |> maybe_add_tools(tools)
      |> Jason.encode!()

    stream =
      Stream.resource(
        fn ->
          {:ok, resp} =
            Req.post("#{@base_url}/chat/completions",
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
  def embed(input, opts) do
    api_key = Keyword.fetch!(opts, :api_key)
    model = Keyword.get(opts, :embedding_model, @default_embedding_model)

    body = Jason.encode!(%{"model" => model, "input" => input})

    case Req.post("#{@base_url}/embeddings",
           body: body,
           headers: headers(api_key),
           receive_timeout: 30_000
         ) do
      {:ok, %{status: 200, body: %{"data" => [%{"embedding" => embedding} | _]}}} ->
        {:ok, embedding}

      {:ok, %{status: status, body: body}} ->
        {:error, %{status: status, body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private

  defp headers(api_key) do
    [
      {"content-type", "application/json"},
      {"authorization", "Bearer #{api_key}"}
    ]
  end

  defp format_messages(messages) do
    Enum.map(messages, fn msg ->
      %{"role" => to_string(msg.role), "content" => to_string(msg.content)}
    end)
  end

  defp maybe_add_tools(body, []), do: body

  defp maybe_add_tools(body, tools) do
    formatted =
      Enum.map(tools, fn tool_module ->
        %{
          "type" => "function",
          "function" => %{
            "name" => tool_module.name(),
            "description" => tool_module.description(),
            "parameters" => tool_module.params()
          }
        }
      end)

    Map.put(body, "tools", formatted)
  end

  defp parse_response(%{"choices" => [choice | _], "usage" => usage}) do
    message = choice["message"]

    tool_calls =
      (message["tool_calls"] || [])
      |> Enum.map(fn tc ->
        %{
          id: tc["id"],
          name: tc["function"]["name"],
          input: Jason.decode!(tc["function"]["arguments"])
        }
      end)

    %{
      role: "assistant",
      content: message["content"] || "",
      tool_calls: tool_calls,
      stop_reason: choice["finish_reason"],
      token_count: (usage["prompt_tokens"] || 0) + (usage["completion_tokens"] || 0),
      usage: %{
        input_tokens: usage["prompt_tokens"] || 0,
        output_tokens: usage["completion_tokens"] || 0
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
        {:ok, %{"choices" => [%{"delta" => %{"content" => content}} | _]}}
        when is_binary(content) ->
          [{:chunk, content}]

        {:ok, %{"choices" => [%{"delta" => %{"tool_calls" => [tc | _]}} | _]}} ->
          if tc["function"]["name"] do
            [{:tool_call_start, %{id: tc["id"], name: tc["function"]["name"]}}]
          else
            [{:tool_call_delta, tc["function"]["arguments"] || ""}]
          end

        {:ok, %{"choices" => [%{"finish_reason" => "stop"} | _]}} ->
          [:done]

        _ ->
          []
      end
    end)
  end
end
