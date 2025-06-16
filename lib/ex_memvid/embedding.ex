defmodule ExMemvid.Embedding do
  @moduledoc """
  Behavior module for generating text embeddings used in semantic search and retrieval.

  This module defines the interface for converting text into high-dimensional vector
  representations (embeddings) that can be used for similarity search, clustering,
  and other machine learning tasks within the ExMemvid system.

  ## Implementation

  Modules implementing this behavior must provide:
  - `embed_text/2` - Generate embedding for a single text string
  - `embed_texts/2` - Generate embeddings for multiple text strings (batch processing)

  ## Embedding Format

  All embeddings are returned as `Nx.Tensor` structures with:
  - Data type: `f32` (32-bit floating point)
  - Single text: 1D tensor with shape `[embedding_dim]`
  - Multiple texts: 2D tensor with shape `[batch_size, embedding_dim]`
  - Typical dimensions: 384, 512, 768, or 1024 depending on the model

  ## Example Implementation

      defmodule MyEmbeddingProvider do
        @behaviour ExMemvid.Embedding

        @impl true
        def embed_text(text, opts) do
          # Your embedding logic here
          {:ok, embedding_tensor}
        end

        @impl true
        def embed_texts(texts, opts) do
          # Batch embedding logic here
          {:ok, batch_embeddings_tensor}
        end
      end

  ## Usage

      # Using the convenience functions
      {:ok, embedding} = ExMemvid.Embedding.embed_text(MyProvider, "Hello world", %{})
      {:ok, embeddings} = ExMemvid.Embedding.embed_texts(MyProvider, ["Hello", "world"], %{})

      # Direct implementation call
      {:ok, embedding} = MyProvider.embed_text("Hello world", %{})

  ## Error Handling

  Implementations should return `{:error, reason}` for various failure cases:
  - `:empty_text` - When provided text is empty or whitespace-only
  - `:model_not_loaded` - When the embedding model is unavailable
  - `:invalid_input` - When text contains unsupported characters or format
  - `:timeout` - When embedding generation exceeds time limits
  """
  @type embedding :: Nx.Tensor.t()

  @doc """
  Generates embeddings for a single text string.

  ## Examples

      iex> ExMemvid.Embedding.embed_text(pid, "Hello world")
      {:ok, #Nx.Tensor<f32[384]>}
      
      iex> ExMemvid.Embedding.embed_text(pid, "")
      {:error, :empty_text}
  """
  @callback embed_text(text :: String.t(), opts :: map()) ::
              {:ok, embedding()} | {:error, term()}

  @doc """
  Generates embeddings for a list of text strings.

  ## Examples

      iex> ExMemvid.Embedding.embed_texts(pid, ["Hello", "world"])
      {:ok, #Nx.Tensor<f32[2][384]>}
  """
  @callback embed_texts(texts :: [String.t()], opts :: map()) ::
              {:ok, embedding()} | {:error, term()}

  def embed_text(module, text, opts) when is_atom(module) do
    module.embed_text(text, opts)
  end

  def embed_texts(module, texts, opts) when is_atom(module) do
    module.embed_texts(texts, opts)
  end
end
