defmodule ExMemvid.TextChunking do
  alias ExMemvid.Config

  @spec chunk(String.t(), Config.t()) :: String.t() | nil
  def chunk(text, opts) do
    opts = [
      chunk_size: get_in(opts, [:chunking, :chunk_size]),
      chunk_overlap: get_in(opts, [:chunking, :overlap])
    ]

    %{text: text} = TextChunker.split(text, opts)

    text
  end
end
