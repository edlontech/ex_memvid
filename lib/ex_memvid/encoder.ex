defmodule ExMemvid.Encoder do
  @moduledoc """
  Encodes text chunks into QR code video files for memory storage and retrieval.

  The `ExMemvid.Encoder` is the core component responsible for converting textual data
  into video files where each frame contains a QR code representing a chunk of text.
  This enables storing large amounts of text data in video format that can be later
  decoded and searched.

  ## Workflow

  1. **Initialize** - Create a new encoder with configuration
  2. **Add Chunks** - Add text chunks to be encoded
  3. **Build Video** - Generate QR codes for each chunk and create video file
  4. **Index Creation** - Build a search index for efficient text retrieval

  ## Example

      # Create encoder with configuration
      config = %ExMemvid.Config{codec: "libx264", qr_size: 400}
      {:ok, encoder} = ExMemvid.Encoder.new(config)

      # Add text chunks
      encoder = ExMemvid.Encoder.add_chunks(encoder, [
        "First chunk of text data",
        "Second chunk of text data",
        "Third chunk of text data"
      ])

      # Build the video and index
      {:ok, stats} = ExMemvid.Encoder.build_video(
        encoder,
        "output/video.mp4",
        "output/index.bin"
      )

  ## Video Generation Process

  For each text chunk, the encoder:
  1. Creates a JSON payload with chunk ID, text content, and frame number
  2. Generates a QR code from the JSON payload
  3. Converts the QR code to a video frame with proper dimensions
  4. Encodes the frame using the specified video codec
  5. Builds a searchable index mapping text content to frame positions

  ## Output

  The encoder produces:
  - **Video file**: Contains QR code frames that can be decoded to retrieve original text
  - **Index file**: Binary search index for efficient text lookup and retrieval
  - **Statistics**: Metadata about the encoding process (frame count, duration, etc.)

  ## Configuration

  The encoder behavior is controlled by `ExMemvid.Config` which specifies:
  - Video codec and parameters (resolution, FPS, pixel format)
  - QR code generation settings
  - Output format preferences
  """
  alias Evision
  alias ExMemvid.Config
  alias ExMemvid.Index
  alias ExMemvid.QR
  alias ExMemvid.TextChunking
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
  Adds text and automatically chunks it using the configured chunking settings.
  """
  @spec add_text(t(), String.t()) :: t()
  def add_text(encoder, text) when is_binary(text) do
    chunks = TextChunking.chunk(text, encoder.config)
    add_chunks(encoder, chunks)
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
