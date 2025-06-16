defmodule ExMemvid.Config do
  @moduledoc """
  Configuration defaults and constants for ExMemvid.

  This module provides a Nimble Options schema for validating and managing
  ExMemvid configuration options, converted from the Python version.
  """

  @schema NimbleOptions.new!(
            qr: [
              type: :map,
              default: %{
                error_correction: :medium,
                fill_color: "#000000",
                back_color: "#ffffff",
                gzip: false
              },
              keys: [
                error_correction: [
                  type: :atom,
                  default: {:in, [:low, :medium, :quartile, :high]},
                  doc: "Error correction level"
                ],
                fill_color: [type: :string, default: "#000000", doc: "QR fill color"],
                back_color: [type: :string, default: "#ffffff", doc: "QR background color"],
                gzip: [
                  type: :boolean,
                  default: false,
                  doc: "Whether to gzip the QR code text"
                ]
              ],
              doc: "QR Code generation settings"
            ],
            codec: [
              type: :atom,
              default: :h265,
              doc: "Video codec to use: :h265, :hevc, :h264"
            ],
            chunking: [
              type: :map,
              default: %{
                chunk_size: 1024,
                overlap: 32
              },
              keys: [
                chunk_size: [
                  type: :integer,
                  default: 1024,
                  doc: "Default chunk size for processing"
                ],
                overlap: [type: :integer, default: 32, doc: "Overlap between chunks"]
              ],
              doc: "Text chunking settings"
            ],
            retrieval: [
              type: :map,
              keys: [
                top_k: [type: :integer, default: 5, doc: "Number of top results to retrieve"],
                batch_size: [type: :integer, default: 100, doc: "Batch size for processing"],
                max_workers: [
                  type: :integer,
                  default: 4,
                  doc: "Maximum number of worker processes"
                ],
                cache_size: [type: :integer, default: 1000, doc: "Number of frames to cache"]
              ],
              doc: "Data retrieval settings"
            ],
            embedding: [
              type: :map,
              default: %{
                module: ExMemvid.Embedding.Local,
                model: "sentence-transformers/all-MiniLM-L6-v2",
                dimension: 384,
                batch_size: 32,
                max_sequence_length: 512,
                partitions: System.schedulers_online()
              },
              keys: [
                module: [
                  type: :atom,
                  doc: "Which Embedding Implementation to use",
                  default: ExMemvid.Embedding.Local
                ],
                model: [
                  type: :string,
                  default: "sentence-transformers/all-MiniLM-L6-v2 ",
                  doc: "Embedding model name"
                ],
                dimension: [type: :integer, default: 384, doc: "Embedding vector dimension"],
                batch_size: [type: :integer, default: 32, doc: "Batch size for embedding"],
                max_sequence_length: [
                  type: :integer,
                  default: 512,
                  doc: "Maximum sequence length for text input"
                ],
                partitions: [
                  type: :integer,
                  default: System.schedulers_online(),
                  doc: "Number of embedding worker partitions (defaults to CPU cores)"
                ]
              ],
              doc: "Text embedding settings"
            ],
            index: [
              type: :map,
              default: %{
                vector_search_space: :cosine,
                embedding_dimensions: 384,
                max_elements: 10_000
              },
              keys: [
                ef_construction: [
                  type: :integer,
                  default: 400,
                  doc: "Number of elements to consider during index construction"
                ],
                ef_search: [
                  type: :integer,
                  default: 50,
                  doc: "Number of elements to consider during search"
                ],
                vector_search_space: [
                  type: {:in, [:cosine, :l2, :ip]},
                  default: :cosine,
                  doc: "Vector search space type"
                ],
                embedding_dimensions: [
                  type: :integer,
                  default: 384,
                  doc: "Dimensions of the embedding vectors"
                ],
                max_elements: [
                  type: :integer,
                  default: 10_000,
                  doc: "Maximum number of elements in the index"
                ]
              ],
              doc: "Vector index settings"
            ]
          )

  @typedoc """
  #{NimbleOptions.docs(@schema)}  
  """
  @type t() :: [unquote(NimbleOptions.option_typespec(@schema))]

  @doc """
  Returns codec parameters for the specified codec.
  """
  def codec_parameters do
    %{
      h265: %{
        video_fps: 30,
        frame_height: 256,
        frame_width: 256,
        pix_fmt: "yuv420p"
      },
      hevc: %{
        video_fps: 30,
        frame_height: 256,
        frame_width: 256,
        pix_fmt: "yuv420p"
      },
      h264: %{
        video_fps: 30,
        frame_height: 256,
        frame_width: 256,
        pix_fmt: "yuv420p"
      }
    }
  end

  @doc """
  Get codec parameters for a specific codec.

  ## Examples

      iex> ExMemvid.Config.get_codec_parameters(:h265)
      %{video_fps: 30, ...}
      
      iex> ExMemvid.Config.get_codec_parameters(:invalid)
      {:error, "Unsupported codec: invalid. Available: [:h265, :hevc, :h264]"}
  """
  def get_codec_parameters(codec_name \\ nil) do
    params = codec_parameters()

    case codec_name do
      nil -> params
      codec when is_map_key(params, codec) -> Map.get(params, codec)
      codec -> {:error, "Unsupported codec: #{codec}. Available: #{inspect(Map.keys(params))}"}
    end
  end

  @doc """
  Validates configuration options, raising on error.
  """
  def validate!(config), do: NimbleOptions.validate!(config, @schema) |> Enum.into(%{})
end
