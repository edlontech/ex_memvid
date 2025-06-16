defmodule ExMemvid.MockEmbedding do
  @moduledoc false

  @behaviour ExMemvid.Embedding

  defp text_to_vec(text) do
    bytes = String.to_charlist(text)
    v1 = Enum.at(bytes, 0, 0) * 1.0
    v2 = Enum.at(bytes, 1, 0) * 1.0
    v3 = Enum.at(bytes, -1, 0) * 1.0
    Nx.tensor([v1, v2, v3])
  end

  @impl true
  def embed_texts(texts, _opts) do
    embeddings = Enum.map(texts, &text_to_vec/1)
    batch_tensor = Nx.stack(embeddings)
    {:ok, batch_tensor}
  end

  @impl true
  def embed_text(text, _opts) do
    {:ok, text_to_vec(text)}
  end
end
