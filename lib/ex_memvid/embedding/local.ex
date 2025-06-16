defmodule ExMemvid.Embedding.Local do
  @moduledoc """
  Text embedding module using Bumblebee for semantic search.

  This module acts as a facade for the partitioned embedding workers.
  It uses round-robin selection to distribute embedding requests across
  multiple worker processes for better performance and load distribution.
  """

  require Logger

  alias ExMemvid.Embedding.Local.Worker, as: LocalWorker
  alias ExMemvid.Embedding.Supervisor, as: EmbeddingSupervisor

  @behaviour ExMemvid.Embedding

  @doc """
  Starts the embedding supervisor with the given configuration.
  """
  def start_link(opts \\ []) do
    EmbeddingSupervisor.start_link(opts)
  end

  @impl true
  def embed_text(text, opts \\ %{}) when is_binary(text) do
    if String.trim(text) == "" do
      {:error, :empty_text}
    else
      case EmbeddingSupervisor.get_worker() do
        {:ok, worker_pid} ->
          LocalWorker.embed_text(worker_pid, text, opts)

        {:error, reason} ->
          Logger.error("Failed to get embedding worker: #{inspect(reason)}")
          {:error, :no_worker_available}
      end
    end
  end

  @impl true
  def embed_texts(texts, opts \\ %{}) when is_list(texts) do
    non_empty_texts = Enum.reject(texts, fn text -> String.trim(text) == "" end)

    if Enum.empty?(non_empty_texts) do
      {:error, :empty_texts}
    else
      case EmbeddingSupervisor.get_worker() do
        {:ok, worker_pid} ->
          LocalWorker.embed_texts(worker_pid, non_empty_texts, opts)

        {:error, reason} ->
          Logger.error("Failed to get embedding worker: #{inspect(reason)}")
          {:error, :no_worker_available}
      end
    end
  end

  @doc """
  Gets a specific worker for direct access (mainly for testing).
  """
  def get_worker do
    EmbeddingSupervisor.get_worker()
  end
end
