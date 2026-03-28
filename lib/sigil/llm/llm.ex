defmodule Sigil.LLM do
  @moduledoc """
  Behaviour for LLM adapters.

  Provides a unified interface for chatting with AI models,
  streaming responses, and generating embeddings.

  ## Implementing an Adapter

      defmodule MyAdapter do
        @behaviour Sigil.LLM

        @impl true
        def chat(messages, opts) do
          # Call your LLM API here
          {:ok, %{role: "assistant", content: "Hello!"}}
        end

        @impl true
        def stream(messages, opts) do
          # Return a stream of chunks
          {:ok, Stream.map(["Hello", " world"], &{:chunk, &1})}
        end

        @impl true
        def embed(input, opts) do
          # Return a vector
          {:ok, [0.1, 0.2, 0.3]}
        end
      end

  ## Using an Adapter

      {:ok, response} = Sigil.LLM.chat(MyAdapter, messages, opts)
      {:ok, stream} = Sigil.LLM.stream(MyAdapter, messages, opts)
      {:ok, vector} = Sigil.LLM.embed(MyAdapter, "some text", opts)
  """

  @type message :: %{role: String.t(), content: String.t()}
  @type response :: %{role: String.t(), content: String.t(), tool_calls: list()}
  @type chunk :: {:chunk, String.t()} | {:tool_call, map()} | :done

  @doc "Send messages to the LLM and receive a complete response."
  @callback chat(messages :: [message()], opts :: keyword()) ::
              {:ok, response()} | {:error, term()}

  @doc "Send messages and receive a stream of response chunks."
  @callback stream(messages :: [message()], opts :: keyword()) ::
              {:ok, Enumerable.t()} | {:error, term()}

  @doc "Generate an embedding vector from input text."
  @callback embed(input :: String.t(), opts :: keyword()) ::
              {:ok, [float()]} | {:error, term()}

  # Convenience functions that delegate to the adapter

  @doc "Chat using the given adapter module."
  def chat(adapter, messages, opts \\ []) do
    with {:ok, response} <- adapter.chat(messages, opts) do
      :telemetry.execute(
        [:sigil, :llm, :chat],
        %{tokens: Map.get(response, :token_count, 0)},
        %{adapter: adapter, model: Keyword.get(opts, :model)}
      )

      {:ok, response}
    end
  end

  @doc "Stream using the given adapter module."
  def stream(adapter, messages, opts \\ []) do
    adapter.stream(messages, opts)
  end

  @doc "Generate embeddings using the given adapter module."
  def embed(adapter, input, opts \\ []) do
    adapter.embed(input, opts)
  end
end
