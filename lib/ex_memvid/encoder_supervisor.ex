defmodule ExMemvid.EncoderSupervisor do
  @moduledoc """
  This supervisor provides a robust way to spawn, monitor, and manage
  individual encoder state machines. Each encoder process is isolated
  and can fail independently without affecting other encoding operations.

  ## Features

  - **Process Isolation**: Each encoder runs in its own supervised process
  - **Fault Tolerance**: Failed encoders don't affect other running encoders
  - **Dynamic Management**: Start and stop encoders on demand
  - **Resource Cleanup**: Automatic cleanup of failed or completed processes
  - **Process Registry**: Optional registration of encoders by name

  ## Usage

      # Start an encoder with automatic naming
      {:ok, pid} = ExMemvid.EncoderSupervisor.start_encoder(
        index_name: "document_001",
        config: %ExMemvid.Config{codec: :h264}
      )

      # Start an encoder with custom name
      {:ok, pid} = ExMemvid.EncoderSupervisor.start_encoder(
        index_name: "document_002", 
        config: config,
        name: {:via, Registry, {ExMemvid.Registry, "my_encoder"}}
      )

      # Stop a specific encoder
      :ok = ExMemvid.EncoderSupervisor.stop_encoder(pid)

      # List all running encoders
      encoders = ExMemvid.EncoderSupervisor.list_encoders()

  """
  use DynamicSupervisor

  alias ExMemvid.Encoder

  require Logger

  @supervisor_name __MODULE__

  @doc """
  Starts the encoder supervisor.
  """
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: @supervisor_name)
  end

  @doc """
  Starts a new encoder state machine under supervision.

  ## Options

  - `:index_name` - Unique identifier for the encoder (required)
  - `:config` - ExMemvid configuration (required) 
  - `:name` - Optional process name for registration
  - `:restart` - Restart strategy (default: `:temporary`)
  - `:shutdown` - Shutdown timeout (default: `5000`)

  ## Examples

      # Basic encoder
      {:ok, pid} = ExMemvid.EncoderSupervisor.start_encoder(
        index_name: "doc_001",
        config: %ExMemvid.Config{}
      )

      # Named encoder with custom restart strategy
      {:ok, pid} = ExMemvid.EncoderSupervisor.start_encoder(
        index_name: "doc_002",
        config: config,
        name: MyEncoder,
        restart: :transient
      )

  """
  @spec start_encoder(keyword()) :: DynamicSupervisor.on_start_child()
  def start_encoder(opts) when is_list(opts) do
    {restart, opts} = Keyword.pop(opts, :restart, :temporary)
    {shutdown, opts} = Keyword.pop(opts, :shutdown, 5000)

    index_name = Keyword.fetch!(opts, :index_name)

    child_spec = %{
      id: Encoder,
      start: {Encoder, :start_link, [opts]},
      restart: restart,
      shutdown: shutdown,
      type: :worker
    }

    case DynamicSupervisor.start_child(@supervisor_name, child_spec) do
      {:ok, pid} = result ->
        Logger.info("Successfully started encoder #{inspect(pid)} for index: #{index_name}")
        result

      {:error, reason} = error ->
        Logger.error("Failed to start encoder for index #{index_name}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Stops an encoder process.

  ## Examples

      :ok = ExMemvid.EncoderSupervisor.stop_encoder(pid)
      :ok = ExMemvid.EncoderSupervisor.stop_encoder(MyEncoder)

  """
  @spec stop_encoder(GenServer.server()) :: :ok | {:error, :not_found}
  def stop_encoder(pid_or_name) do
    # Resolve name to PID if necessary
    pid = if is_pid(pid_or_name) do
      pid_or_name
    else
      case GenServer.whereis(pid_or_name) do
        nil -> nil
        pid -> pid
      end
    end

    if pid do
      case DynamicSupervisor.terminate_child(@supervisor_name, pid) do
        :ok ->
          Logger.info("Successfully stopped encoder #{inspect(pid_or_name)}")
          :ok

        {:error, :not_found} = error ->
          Logger.warning("Encoder #{inspect(pid_or_name)} not found")
          error
      end
    else
      Logger.warning("Encoder #{inspect(pid_or_name)} not found")
      {:error, :not_found}
    end
  end

  @doc """
  Lists all currently running encoder processes.

  Returns a list of `{id, pid, type, modules}` tuples for each running encoder.
  """
  @spec list_encoders() :: [DynamicSupervisor.child()]
  def list_encoders do
    DynamicSupervisor.which_children(@supervisor_name)
  end

  @doc """
  Counts the number of running encoder processes.
  """
  @spec count_encoders() :: non_neg_integer()
  def count_encoders do
    DynamicSupervisor.count_children(@supervisor_name).active
  end

  @doc """
  Stops all running encoder processes.

  This is useful for cleanup during application shutdown or testing.
  """
  @spec stop_all_encoders() :: :ok
  def stop_all_encoders do
    @supervisor_name
    |> DynamicSupervisor.which_children()
    |> Enum.each(fn {_id, pid, _type, _modules} ->
      DynamicSupervisor.terminate_child(@supervisor_name, pid)
    end)

    Logger.info("Stopped all encoder processes")
    :ok
  end

  @doc """
  Gets detailed information about all running encoders including their current state.

  Returns a map with encoder PIDs as keys and their state information as values.
  """
  @spec get_encoders_info() :: %{pid() => {atom(), map()}}
  def get_encoders_info do
    @supervisor_name
    |> DynamicSupervisor.which_children()
    |> Enum.reduce(%{}, fn {_id, pid, _type, _modules}, acc ->
      try do
        state_info = Encoder.get_state(pid)
        Map.put(acc, pid, state_info)
      rescue
        _ -> acc
      end
    end)
  end

  # DynamicSupervisor Callbacks

  @impl DynamicSupervisor
  def init(_init_arg) do
    Logger.info("Starting ExMemvid encoder supervisor")
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
