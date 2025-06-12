defmodule ExMemvid.Embedding.Local.Worker do
  @moduledoc """
  Individual embedding worker process.

  This GenServer represents a single embedding worker that handles
  text embedding requests using Bumblebee. Multiple workers are
  managed by the PartitionSupervisor for load distribution.
  """

  use GenServer

  require Logger

  defstruct [:serving, :model_info, :tokenizer, :config, :partition]

  @registry ExMemvid.Embedding.Registry

  def start_link({config, partition}) do
    GenServer.start_link(__MODULE__, {config, partition})
  end

  def embed_text(worker_pid, text, opts \\ %{}) when is_binary(text) do
    timeout = Map.get(opts, :timeout, 15_000)

    if String.trim(text) == "" do
      {:error, :empty_text}
    else
      GenServer.call(worker_pid, {:embed_text, text}, timeout)
    end
  end

  def embed_texts(worker_pid, texts, opts \\ %{}) when is_list(texts) do
    timeout = Map.get(opts, :timeout, 15_000)

    non_empty_texts = Enum.reject(texts, fn text -> String.trim(text) == "" end)

    if Enum.empty?(non_empty_texts) do
      {:error, :empty_texts}
    else
      GenServer.call(worker_pid, {:embed_texts, non_empty_texts}, timeout)
    end
  end

  ## GenServer Callbacks

  @impl true
  def init({config, partition}) do
    embedding_config =
      %{
        model: config[:embedding][:model],
        dimension: config[:embedding][:dimension],
        batch_size: config[:embedding][:batch_size],
        max_sequence_length: config[:embedding][:max_sequence_length]
      }

    Logger.debug(
      "Initializing embedding worker #{partition} with model: #{embedding_config.model}"
    )

    case load_model_and_serving(embedding_config) do
      {:ok, state} ->
        Registry.register(@registry, {:worker, partition}, %{started_at: DateTime.utc_now()})

        final_state = %{state | partition: partition}
        Logger.debug("Embedding worker #{partition} initialized successfully")
        {:ok, final_state}

      {:error, reason} = error ->
        Logger.error("Failed to initialize embedding worker #{partition}: #{inspect(reason)}")
        {:stop, error}
    end
  end

  @impl true
  def handle_call({:embed_text, text}, _from, state) do
    case Nx.Serving.run(state.serving, text) do
      %{embedding: embedding} ->
        {:reply, {:ok, embedding}, state}

      error ->
        Logger.error("Worker #{state.partition} failed to embed text: #{inspect(error)}")
        {:reply, {:error, :embedding_failed}, state}
    end
  end

  @impl true
  def handle_call({:embed_texts, texts}, _from, state) do
    batch_size = state.config.batch_size

    try do
      embeddings =
        texts
        |> Enum.chunk_every(batch_size)
        |> Enum.map(fn batch ->
          case Nx.Serving.run(state.serving, batch) do
            results when is_list(results) ->
              Enum.map(results, & &1.embedding)

            %{embedding: embedding} ->
              [embedding]

            _ ->
              throw({:error, :batch_embedding_failed})
          end
        end)
        |> List.flatten()
        |> Nx.stack()

      {:reply, {:ok, embeddings}, state}
    rescue
      e ->
        Logger.error("Worker #{state.partition} exception while embedding texts: #{inspect(e)}")
        {:reply, {:error, :embedding_exception}, state}
    catch
      {:error, reason} ->
        Logger.error("Worker #{state.partition} failed to embed texts: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Worker #{state.partition} received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  ## Private Functions

  defp load_model_and_serving(config) do
    model_name = config.model
    max_sequence_length = config.max_sequence_length

    Logger.debug("Loading model: #{model_name}")

    {:ok, model_info} = Bumblebee.load_model({:hf, model_name})
    {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, model_name})

    serving =
      Bumblebee.Text.text_embedding(model_info, tokenizer,
        compile: [batch_size: 1, sequence_length: max_sequence_length]
      )

    state = %__MODULE__{
      serving: serving,
      model_info: model_info,
      tokenizer: tokenizer,
      config: config
    }

    {:ok, state}
  rescue
    e ->
      {:error, {:model_load_failed, e}}
  end
end
