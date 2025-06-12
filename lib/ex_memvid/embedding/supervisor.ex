defmodule ExMemvid.Embedding.Supervisor do
  @moduledoc """
  Supervisor for managing partitioned embedding workers.

  This supervisor manages multiple instances of embedding workers using PartitionSupervisor
  for better performance and load distribution. Workers are selected using round-robin
  to distribute the embedding workload across available CPU cores.
  """

  use Supervisor

  require Logger

  @registry ExMemvid.Embedding.Registry
  @counter_name :embedding_counter

  def start_link(config) do
    Supervisor.start_link(__MODULE__, config, name: __MODULE__)
  end

  @impl true
  def init(config) do
    embedding_config = config[:embedding] || %{}
    partitions = Map.get(embedding_config, :partitions, System.schedulers_online())

    Logger.info("Starting embedding supervisor with #{partitions} partitions")

    :persistent_term.put(@counter_name, :atomics.new(1, []))

    children = [
      {Registry, keys: :unique, name: @registry},
      {PartitionSupervisor,
       child_spec: ExMemvid.Embedding.Local.Worker,
       name: ExMemvid.Embedding.PartitionSupervisor,
       partitions: partitions,
       with_arguments: fn _child_spec, partition ->
         [{config, partition}]
       end}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Gets the next available worker using round-robin selection.
  """
  def get_worker do
    partitions = PartitionSupervisor.count_children(ExMemvid.Embedding.PartitionSupervisor).active
    counter_ref = :persistent_term.get(@counter_name)

    current = :atomics.add_get(counter_ref, 1, 1)
    partition = rem(current - 1, partitions)

    case Registry.lookup(@registry, {:worker, partition}) do
      [{pid, _}] when is_pid(pid) -> {:ok, pid}
      [] -> {:error, :no_worker_available}
    end
  rescue
    error ->
      Logger.error("Failed to get worker: #{inspect(error)}")
      {:error, :worker_selection_failed}
  catch
    :exit, reason ->
      Logger.error("Worker selection exited: #{inspect(reason)}")
      {:error, :worker_unavailable}
  end

  @doc """
  Gets worker for a specific partition (used by PartitionSupervisor).
  """
  def get_worker_for_partition(partition) do
    case Registry.lookup(@registry, {:worker, partition}) do
      [{pid, _}] when is_pid(pid) -> {:ok, pid}
      [] -> {:error, :no_worker_available}
    end
  end
end
