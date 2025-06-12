defmodule ExMemvid.Encoder do
  @moduledoc """
  A Encoder implementation for encoding text chunks into QR code videos.

  Each encoder instance is responsible for managing one video encoding process
  with proper state transitions and error handling.

  ## States

  - `:ready` - Ready to accept chunks and configuration
  - `:collecting` - Collecting text chunks for encoding
  - `:building` - Building the video and index files
  - `:completed` - Successfully completed encoding
  - `:error` - Error state with failure information

  ## State Data

  The state machine maintains:
  - `config`: ExMemvid configuration
  - `chunks`: List of text chunks to encode
  - `index_name`: Unique identifier for this encoding process
  - `output_path`: Video output file path
  - `index_path`: Index output file path
  - `stats`: Encoding statistics (when completed)
  - `error`: Error information (when in error state)

  ## Example Usage

      # Start a new encoder process
      {:ok, pid} = ExMemvid.EncoderStateMachine.start_link(
        index_name: "my_video_001",
        config: %ExMemvid.Config{codec: :h264}
      )

      # Add text chunks
      :ok = ExMemvid.EncoderStateMachine.add_chunks(pid, ["chunk1", "chunk2"])

      # Build the video
      {:ok, stats} = ExMemvid.EncoderStateMachine.build_video(
        pid, 
        "output/video.mp4", 
        "output/index.bin"
      )

  """
  use GenStateMachine, callback_mode: :state_functions

  alias Evision
  alias ExMemvid.Config
  alias ExMemvid.Index
  alias ExMemvid.QR
  alias ExMemvid.TextChunking
  alias Xav.Encoder

  require Logger

  @type state_name :: :ready | :collecting | :building | :completed | :error

  @type state_data :: %{
          config: Config.t(),
          chunks: list(String.t()),
          index_name: String.t(),
          output_path: String.t() | nil,
          index_path: String.t() | nil,
          stats: map() | nil,
          error: term() | nil,
          client_from: GenStateMachine.from() | nil
        }

  @doc """
  Starts a new encoder

  ## Options

  - `:index_name` - Unique identifier for this encoder instance (required)
  - `:config` - ExMemvid configuration (required)
  - `:name` - Optional process name for registration
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {index_name, opts} = Keyword.pop!(opts, :index_name)
    {config, opts} = Keyword.pop!(opts, :config)
    {name, _opts} = Keyword.pop(opts, :name)

    initial_data = %{
      config: config,
      chunks: [],
      index_name: index_name,
      output_path: nil,
      index_path: nil,
      stats: nil,
      error: nil,
      client_from: nil
    }

    start_opts = if name, do: [name: name], else: []
    GenStateMachine.start_link(__MODULE__, initial_data, start_opts)
  end

  @doc """
  Adds text chunks to the encoder.
  """
  @spec add_chunks(GenServer.server(), list(String.t())) :: :ok | {:error, term()}
  def add_chunks(server, chunks) when is_list(chunks) do
    GenStateMachine.call(server, {:add_chunks, chunks})
  end

  @doc """
  Adds text and automatically chunks it using the configured chunking settings.
  """
  @spec add_text(GenServer.server(), String.t()) :: :ok | {:error, term()}
  def add_text(server, text) when is_binary(text) do
    GenStateMachine.call(server, {:add_text, text})
  end

  @doc """
  Builds the QR code video and search index.
  This is an asynchronous operation that transitions the state machine to building state.
  """
  @spec build_video(GenServer.server(), Path.t(), Path.t()) :: {:ok, map()} | {:error, term()}
  def build_video(server, output_path, index_path) do
    GenStateMachine.call(server, {:build_video, output_path, index_path}, :infinity)
  end

  @doc """
  Gets the current state and data of the encoder.
  """
  @spec get_state(GenServer.server()) :: {state_name(), map()}
  def get_state(server) do
    GenStateMachine.call(server, :get_state)
  end

  @doc """
  Resets the encoder to ready state, clearing all chunks and previous results.
  """
  @spec reset(GenServer.server()) :: :ok
  def reset(server) do
    GenStateMachine.call(server, :reset)
  end

  # Callbacks

  @impl GenStateMachine
  def init(initial_data) do
    Logger.info("Starting encoder state machine for index: #{initial_data.index_name}")
    {:ok, :ready, initial_data}
  end

  # State: :ready
  def ready({:call, from}, {:add_chunks, chunks}, data) do
    new_chunks = data.chunks ++ chunks
    new_data = %{data | chunks: new_chunks}
    Logger.debug("Added #{length(chunks)} chunks, total: #{length(new_chunks)}")
    {:next_state, :collecting, new_data, [{:reply, from, :ok}]}
  end

  def ready({:call, from}, {:add_text, text}, data) do
    chunks = TextChunking.chunk(text, data.config)
    new_chunks = data.chunks ++ chunks
    new_data = %{data | chunks: new_chunks}

    Logger.debug("Chunked text into #{length(chunks)} chunks, total: #{length(new_chunks)}")

    {:next_state, :collecting, new_data, [{:reply, from, :ok}]}
  end

  def ready({:call, from}, {:build_video, output_path, index_path}, data) do
    if Enum.empty?(data.chunks) do
      {:keep_state_and_data, [{:reply, from, {:error, :no_chunks}}]}
    else
      new_data = %{data | output_path: output_path, index_path: index_path, client_from: from}
      {:next_state, :building, new_data, [{:next_event, :internal, :start_build}]}
    end
  end

  def ready({:call, from}, :get_state, data) do
    state_info = Map.drop(data, [:client_from])
    {:keep_state_and_data, [{:reply, from, {:ready, state_info}}]}
  end

  def ready({:call, from}, :reset, data) do
    reset_data = %{data | chunks: [], output_path: nil, index_path: nil, stats: nil, error: nil}
    {:keep_state, reset_data, [{:reply, from, :ok}]}
  end

  # State: :collecting
  def collecting({:call, from}, {:add_chunks, chunks}, data) do
    new_chunks = data.chunks ++ chunks
    new_data = %{data | chunks: new_chunks}
    Logger.debug("Added #{length(chunks)} chunks, total: #{length(new_chunks)}")
    {:keep_state, new_data, [{:reply, from, :ok}]}
  end

  def collecting({:call, from}, {:add_text, text}, data) do
    chunks = TextChunking.chunk(text, data.config)
    new_chunks = data.chunks ++ chunks
    new_data = %{data | chunks: new_chunks}
    Logger.debug("Chunked text into #{length(chunks)} chunks, total: #{length(new_chunks)}")
    {:keep_state, new_data, [{:reply, from, :ok}]}
  end

  def collecting({:call, from}, {:build_video, output_path, index_path}, data) do
    new_data = %{data | output_path: output_path, index_path: index_path, client_from: from}
    {:next_state, :building, new_data, [{:next_event, :internal, :start_build}]}
  end

  def collecting({:call, from}, :get_state, data) do
    state_info = Map.drop(data, [:client_from])
    {:keep_state_and_data, [{:reply, from, {:collecting, state_info}}]}
  end

  def collecting({:call, from}, :reset, data) do
    reset_data = %{data | chunks: [], output_path: nil, index_path: nil, stats: nil, error: nil}
    {:next_state, :ready, reset_data, [{:reply, from, :ok}]}
  end

  # State: :building
  def building(:internal, :start_build, data) do
    Logger.info("Starting video build for #{length(data.chunks)} chunks")

    pid = self()

    spawn_link(fn ->
      result = perform_video_build(data)
      GenStateMachine.cast(pid, {:build_complete, result})
    end)

    :keep_state_and_data
  end

  def building(:cast, {:build_complete, {:ok, stats}}, data) do
    new_data = %{data | stats: stats}

    reply_action =
      if data.client_from do
        [{:reply, data.client_from, {:ok, stats}}]
      else
        []
      end

    {:next_state, :completed, %{new_data | client_from: nil}, reply_action}
  end

  def building(:cast, {:build_complete, {:error, reason}}, data) do
    new_data = %{data | error: reason}

    reply_action =
      if data.client_from do
        [{:reply, data.client_from, {:error, reason}}]
      else
        []
      end

    {:next_state, :error, %{new_data | client_from: nil}, reply_action}
  end

  def building({:call, from}, :get_state, data) do
    state_info = Map.drop(data, [:client_from])
    {:keep_state_and_data, [{:reply, from, {:building, state_info}}]}
  end

  def building({:call, from}, :reset, _data) do
    {:keep_state_and_data, [{:reply, from, {:error, :building_in_progress}}]}
  end

  def building({:call, from}, _event, _data) do
    {:keep_state_and_data, [{:reply, from, {:error, :building_in_progress}}]}
  end

  # State: :completed
  def completed({:call, from}, :get_state, data) do
    state_info = Map.drop(data, [:client_from])
    {:keep_state_and_data, [{:reply, from, {:completed, state_info}}]}
  end

  def completed({:call, from}, :reset, data) do
    reset_data = %{data | chunks: [], output_path: nil, index_path: nil, stats: nil, error: nil}
    {:next_state, :ready, reset_data, [{:reply, from, :ok}]}
  end

  def completed({:call, from}, _event, _data) do
    {:keep_state_and_data, [{:reply, from, {:error, :already_completed}}]}
  end

  # State: :error
  def error({:call, from}, :get_state, data) do
    state_info = Map.drop(data, [:client_from])
    {:keep_state_and_data, [{:reply, from, {:error, state_info}}]}
  end

  def error({:call, from}, :reset, data) do
    reset_data = %{data | chunks: [], output_path: nil, index_path: nil, stats: nil, error: nil}
    {:next_state, :ready, reset_data, [{:reply, from, :ok}]}
  end

  def error({:call, from}, _event, data) do
    {:keep_state_and_data, [{:reply, from, {:error, data.error}}]}
  end

  @impl GenStateMachine
  def handle_event({:call, from}, _event, state, _data) do
    {:keep_state_and_data, [{:reply, from, {:error, {:unexpected_call_in_state, state}}}]}
  end

  defp perform_video_build(data) do
    codec_name = get_in(data.config, [:codec]) || :h264
    codec_params = Config.get_codec_parameters(codec_name)

    encoder_opts = [
      height: codec_params.frame_height,
      width: codec_params.frame_width,
      format: String.to_atom(codec_params.pix_fmt),
      time_base: {1, codec_params.video_fps}
    ]

    File.mkdir_p!(Path.dirname(data.output_path))

    video_encoder = Encoder.new(codec_name, encoder_opts)
    frame_numbers = Enum.to_list(0..(length(data.chunks) - 1))

    all_packets =
      Enum.zip(data.chunks, frame_numbers)
      |> Enum.flat_map(fn chunk_frame ->
        frame = generate_and_prepare_frame(chunk_frame, data.config, codec_params)
        Encoder.encode(video_encoder, frame)
      end)

    final_packets = Encoder.flush(video_encoder)
    packets = all_packets ++ final_packets

    packets
    |> Stream.map(& &1.data)
    |> Stream.into(File.stream!(data.output_path))
    |> Stream.run()

    with {:ok, index} <- Index.new(data.config),
         {:ok, index} <- Index.add_items(index, data.chunks, frame_numbers),
         :ok <- Index.save(index, data.index_path) do
      stats = %{
        total_chunks: length(data.chunks),
        total_frames: length(frame_numbers),
        duration_seconds: length(frame_numbers) / codec_params.video_fps,
        fps: codec_params.video_fps,
        index_stats: %{},
        packets_count: length(packets),
        index_name: data.index_name,
        output_path: data.output_path,
        index_path: data.index_path
      }

      {:ok, stats}
    else
      error -> {:error, {:index_creation_failed, error}}
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
