defmodule ExMemvid.RetrieverSupervisor do
  @moduledoc """
  A DynamicSupervisor for managing ExMemvid.Retriever processes.

  This supervisor allows starting multiple retriever instances dynamically,
  each with their own video and index paths. It provides a management API
  similar to the EncoderSupervisor for consistent usage patterns.
  """

  use DynamicSupervisor

  @doc """
  Starts the RetrieverSupervisor.
  """
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts a new retriever process under this supervisor.

  ## Parameters
    - `video_path` - Path to the video file
    - `index_path` - Path to the index file
    - `config` - Configuration map for the retriever
    - `opts` - Optional keyword list with:
      - `:name` - Name to register the retriever process (optional)

  ## Examples

      iex> ExMemvid.RetrieverSupervisor.start_retriever("video.mp4", "index.hnsw", %{})
      {:ok, #PID<0.123.0>}

      iex> ExMemvid.RetrieverSupervisor.start_retriever("video.mp4", "index.hnsw", %{}, name: MyRetriever)
      {:ok, #PID<0.124.0>}
  """
  def start_retriever(video_path, index_path, config, opts \\ []) do
    child_spec = %{
      id: make_ref(),
      start: {ExMemvid.Retriever, :start_link, [video_path, index_path, config]},
      restart: :temporary
    }

    # Add name option if provided
    child_spec =
      if name = opts[:name] do
        put_in(
          child_spec,
          [:start],
          {ExMemvid.Retriever, :start_link, [video_path, index_path, config, [name: name]]}
        )
      else
        child_spec
      end

    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  @doc """
  Stops a retriever process.

  ## Parameters
    - `retriever_pid` - PID or registered name of the retriever to stop

  ## Examples

      iex> ExMemvid.RetrieverSupervisor.stop_retriever(retriever_pid)
      :ok

      iex> ExMemvid.RetrieverSupervisor.stop_retriever(MyRetriever)
      :ok
  """
  def stop_retriever(retriever_pid) when is_pid(retriever_pid) do
    DynamicSupervisor.terminate_child(__MODULE__, retriever_pid)
  end

  def stop_retriever(retriever_name) when is_atom(retriever_name) do
    case Process.whereis(retriever_name) do
      nil -> {:error, :not_found}
      pid -> stop_retriever(pid)
    end
  end

  @doc """
  Lists all active retriever processes managed by this supervisor.

  Returns a list of tuples containing the PID and child specification.

  ## Examples

      iex> ExMemvid.RetrieverSupervisor.list_retrievers()
      [{#PID<0.123.0>, %{id: #Reference<...>, ...}}]
  """
  def list_retrievers do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.map(fn {_, pid, _, _} -> pid end)
    |> Enum.filter(&is_pid/1)
  end

  @doc """
  Returns the count of active retriever processes.

  ## Examples

      iex> ExMemvid.RetrieverSupervisor.count_retrievers()
      2
  """
  def count_retrievers do
    DynamicSupervisor.count_children(__MODULE__).active
  end

  @doc """
  Retrieves information about a specific retriever process.

  ## Parameters
    - `retriever_pid` - PID or registered name of the retriever

  ## Returns
    - `{:ok, info}` where info contains the retriever's state information
    - `{:error, :not_found}` if the retriever doesn't exist

  ## Examples

      iex> ExMemvid.RetrieverSupervisor.get_retriever_info(pid)
      {:ok, %{video_path: "video.mp4", index_path: "index.hnsw", ...}}
  """
  def get_retriever_info(retriever_pid) when is_pid(retriever_pid) do
    case Process.alive?(retriever_pid) do
      true ->
        try do
          {:ok, GenServer.call(retriever_pid, :get_state)}
        catch
          :exit, _ -> {:error, :not_found}
        end

      false ->
        {:error, :not_found}
    end
  end

  def get_retriever_info(retriever_name) when is_atom(retriever_name) do
    case Process.whereis(retriever_name) do
      nil -> {:error, :not_found}
      pid -> get_retriever_info(pid)
    end
  end

  @doc """
  Stops all retriever processes managed by this supervisor.

  ## Examples

      iex> ExMemvid.RetrieverSupervisor.stop_all_retrievers()
      :ok
  """
  def stop_all_retrievers do
    list_retrievers()
    |> Enum.each(&stop_retriever/1)
  end
end
