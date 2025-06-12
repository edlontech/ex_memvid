defmodule ExMemvid.Embedding do
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
