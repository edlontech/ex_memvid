defmodule ExMemvid.Retriever do
  @moduledoc """
  A stateful GenServer for retrieving and decoding data from video memory.

  This module manages the retriever's state, including a cache for decoded
  frames, ensuring that the cache persists across multiple calls. You start
  the server with `start_link/3` and interact with it via the returned pid.
  """
  use GenServer

  alias ExMemvid.Config
  alias ExMemvid.Index
  alias ExMemvid.QR
  alias Xav.Reader

  defstruct video_path: nil,
            index: nil,
            config: nil,
            cache: %{}

  # ================================================================
  # Client API
  # ================================================================

  @doc """
  Starts the Retriever GenServer.
  """
  @spec start_link(video_path: Path.t(), index_path: Path.t(), config: Config.t()) ::
          GenServer.on_start()
  def start_link(video_path: video_path, index_path: index_path, config: config) do
    GenServer.start_link(__MODULE__, {video_path, index_path, config})
  end

  @doc """
  Performs a semantic search using the running Retriever server.
  """
  @spec search(pid :: pid(), query :: String.t(), top_k :: integer()) ::
          {:ok, list(String.t())} | {:error, term()}
  def search(pid, query, top_k \\ 5) do
    GenServer.call(pid, {:search, query, top_k})
  end

  # ================================================================
  # GenServer Callbacks
  # ================================================================

  @impl true
  def init({video_path, index_path, config}) do
    case Index.load(config, index_path) do
      {:ok, index} ->
        state = %__MODULE__{
          video_path: video_path,
          index: index,
          config: config,
          cache: %{}
        }

        {:ok, state}

      _ ->
        {:stop, "Failed to load index"}
    end
  end

  @impl true
  def handle_call({:search, query, top_k}, _from, state) do
    with {:ok, search_results} <- Index.search(state.index, query, top_k),
         frame_numbers <- Enum.map(search_results, & &1.frame_num) |> Enum.uniq(),
         {:ok, decoded_frames, new_cache} <- decode_frames(state, frame_numbers) do
      results =
        Enum.map(search_results, fn result ->
          case Map.get(decoded_frames, result.frame_num) do
            nil ->
              result.text_snippet

            decoded_json ->
              decode_seach_result(decoded_json, result)
          end
        end)

      new_state = %{state | cache: new_cache}
      {:reply, {:ok, results}, new_state}
    else
      error -> {:reply, error, state}
    end
  end

  # ================================================================
  # Private Helper Functions
  # ================================================================
  #
  defp decode_seach_result(decoded_json, result) do
    case Jason.decode(decoded_json) do
      {:ok, %{"text" => text}} -> text
      _ -> result.text_snippet
    end
  end

  defp decode_frames(state, frame_numbers) do
    cached_frames =
      Enum.reduce(frame_numbers, %{}, fn frame_num, acc ->
        if Map.has_key?(state.cache, frame_num) do
          Map.put(acc, frame_num, Map.get(state.cache, frame_num))
        else
          acc
        end
      end)

    uncached_frame_numbers = MapSet.new(frame_numbers -- Map.keys(cached_frames))

    if Enum.empty?(uncached_frame_numbers) do
      {:ok, cached_frames, state.cache}
    else
      newly_decoded_map =
        Reader.stream!(state.video_path)
        |> Stream.with_index()
        |> Stream.filter(fn {_frame, index} -> index in uncached_frame_numbers end)
        |> Task.async_stream(
          fn {frame, index} ->
            decode_qr(frame, index, state)
          end,
          max_concurrency: System.schedulers_online() * 2,
          ordered: false
        )
        |> Enum.reduce(%{}, fn
          {:ok, nil}, acc -> acc
          {:ok, {index, text}}, acc -> Map.put(acc, index, text)
        end)

      new_cache = Map.merge(state.cache, newly_decoded_map)
      all_decoded_frames = Map.merge(cached_frames, newly_decoded_map)

      {:ok, all_decoded_frames, new_cache}
    end
  end

  defp decode_qr(frame, index, state) do
    case QR.decode(frame.data, state.config) do
      {:ok, text} -> {index, text}
      {:error, _reason} -> nil
    end
  end
end
