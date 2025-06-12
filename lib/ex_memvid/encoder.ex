defmodule ExMemvid.Encoder do
  alias ExMemvid.{Config, Index, QR}
  alias Evision
  alias Xav.Encoder

  @type t :: %__MODULE__{
          chunks: list(String.t()),
          config: Config.t()
        }

  defstruct chunks: [],
            config: nil

  @doc """
  Creates a new ExMemvid.Encoder.
  """
  @spec new(Config.t() | list) :: {:ok, t()}
  def new(config) do
    config = if is_list(config), do: Enum.into(config, %{}), else: config
    {:ok, %__MODULE__{config: config, chunks: []}}
  end

  @doc """
  Adds a list of text chunks to the encoder.
  """
  @spec add_chunks(t(), list(String.t())) :: t()
  def add_chunks(encoder, new_chunks) when is_list(new_chunks) do
    %__MODULE__{encoder | chunks: encoder.chunks ++ new_chunks}
  end

  @doc """
  Builds the QR code video and search index.
  """
  @spec build_video(t(), Path.t(), Path.t()) :: {:ok, map()} | {:error, term()}
  def build_video(encoder, output_path, index_path) do
    codec_name = get_in(encoder.config, [:codec])
    codec_params = Config.get_codec_parameters(codec_name)

    encoder_opts = [
      height: codec_params.frame_height,
      width: codec_params.frame_width,
      format: String.to_atom(codec_params.pix_fmt),
      time_base: {1, codec_params.video_fps}
    ]

    File.mkdir_p!(Path.dirname(output_path))

    video_encoder = Encoder.new(codec_name, encoder_opts)
    frame_numbers = Enum.to_list(0..(length(encoder.chunks) - 1))

    all_packets =
      Enum.zip(encoder.chunks, frame_numbers)
      |> Enum.flat_map(fn chunk_frame ->
        frame = generate_and_prepare_frame(chunk_frame, encoder.config, codec_params)
        Encoder.encode(video_encoder, frame)
      end)

    final_packets = Encoder.flush(video_encoder)

    packets = all_packets ++ final_packets

    packets
    |> Stream.map(& &1.data)
    |> Stream.into(File.stream!(output_path))
    |> Stream.run()

    with {:ok, index} <- Index.new(encoder.config),
         {:ok, index} <- Index.add_items(index, encoder.chunks, frame_numbers),
         :ok <- Index.save(index, index_path) do
      stats = %{
        total_chunks: length(encoder.chunks),
        total_frames: length(frame_numbers),
        duration_seconds: length(frame_numbers) / codec_params.video_fps,
        fps: codec_params.video_fps,
        index_stats: Map.new(),
        packets_count: length(packets)
      }

      {:ok, stats}
    end
  end

  defp generate_and_prepare_frame({chunk, frame_num}, config, codec_params) do
    chunk_data_json = Jason.encode!(%{id: frame_num, text: chunk, frame: frame_num})

    {:ok, qr_png_binary} = QR.encode(chunk_data_json, config)

    bgr_mat = Evision.imdecode(qr_png_binary, Evision.Constant.cv_IMREAD_COLOR())
    target_size = {codec_params.frame_width, codec_params.frame_height}
    resized_mat = Evision.resize(bgr_mat, target_size)

    frame_binary = Evision.Mat.to_binary(resized_mat)

    Xav.Frame.new(
      frame_binary,
      :bgr24,
      codec_params.frame_width,
      codec_params.frame_height,
      frame_num
    )
  end
end
