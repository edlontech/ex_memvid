defmodule ExMemvid.TextChunking do
  @moduledoc """
  Contains functions for chunking text into smaller segments
  """

  alias ExMemvid.Config

  @spec chunk(String.t(), Config.t()) :: [String.t()] | nil
  def chunk(text, opts) do
    opts = [
      chunk_size: get_in(opts, [:chunking, :chunk_size]),
      chunk_overlap: get_in(opts, [:chunking, :overlap])
    ]

    text
    |> TextChunker.split(opts)
    |> Enum.map(& &1.text)
  end
end
