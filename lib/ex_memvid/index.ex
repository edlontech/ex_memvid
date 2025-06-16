defmodule ExMemvid.Index do
  @moduledoc """
  Manages a high-performance vector similarity search index for encoded video content.

  The `ExMemvid.Index` module provides semantic search capabilities over text chunks
  that have been encoded into QR code videos. It uses HNSW (Hierarchical Navigable
  Small World) algorithms for efficient approximate nearest neighbor search, enabling
  fast retrieval of relevant content from large video archives.

  ## Key Features

  - **Vector Similarity Search**: Uses embeddings to find semantically similar content
  - **Frame Mapping**: Maintains relationships between text chunks and video frames  
  - **Batch Processing**: Efficiently handles multiple text chunks simultaneously
  - **Persistence**: Save and load index state to/from disk
  - **Metadata Management**: Stores searchable metadata alongside vector embeddings
  - **Configurable Performance**: Tunable parameters for speed vs accuracy trade-offs

  ## Architecture

  The index maintains three key data structures:
  1. **HNSW Vector Index**: High-dimensional similarity search using HNSWLib
  2. **Metadata Store**: Maps chunk IDs to text snippets and frame numbers
  3. **Frame Mapping**: Associates video frames with their constituent text chunks

  ## Workflow

  1. **Initialize** - Create index with specified dimensions and parameters
  2. **Add Content** - Insert text chunks with their embeddings and frame associations
  3. **Search** - Query for similar content using natural language
  4. **Retrieve** - Get specific chunks by ID or all chunks from a video frame
  5. **Persist** - Save index state for future sessions

  ## Example Usage

      # Create a new index
      config = [
        index: %{
          vector_search_space: :cosine,
          embedding_dimensions: 384,
          max_elements: 10_000,
          ef_construction: 200,
          ef_search: 50
        },
        embedding: %{
          module: MyEmbeddingProvider,
          model: "all-MiniLM-L6-v2"
        }
      ]
      {:ok, index} = ExMemvid.Index.new(config)

      # Add text chunks from encoded video
      chunks = ["First chunk of text", "Second chunk of text"]
      frame_numbers = [0, 1]
      {:ok, index} = ExMemvid.Index.add_items(index, chunks, frame_numbers)

      # Search for similar content
      {:ok, results} = ExMemvid.Index.search(index, "find relevant text", 5)

      # Get all chunks from a specific video frame
      {:ok, frame_chunks} = ExMemvid.Index.get_chunks_by_frame(index, 0)

      # Save index for later use
      :ok = ExMemvid.Index.save(index, "my_index.json")

  ## Search Results

  Search operations return metadata maps containing:
  - `:id` - Unique identifier for the chunk
  - `:text_snippet` - First 100 characters of the original text
  - `:frame_num` - Video frame number containing this chunk

  ## Performance Tuning

  Key configuration parameters affect performance:
  - `ef_construction` - Higher values improve accuracy during index building (slower)
  - `ef_search` - Higher values improve search accuracy (slower queries)
  - `max_elements` - Maximum number of vectors the index can hold
  - `vector_search_space` - Distance metric (`:cosine`, `:l2`, `:ip`)

  ## Persistence Format

  The index is saved as two files:
  - `.json` file - Contains metadata and frame mappings
  - `.hnsw` file - Binary HNSW index data
  """
  alias ExMemvid.Config
  alias ExMemvid.Embedding
  alias HNSWLib, as: Hnsw

  @type t :: %__MODULE__{
          index: %Hnsw.Index{} | nil,
          metadata: %{integer => map()},
          frame_to_chunks: %{integer => list(integer())},
          config: ExMemvid.Config.t()
        }

  defstruct index: nil,
            metadata: %{},
            frame_to_chunks: %{},
            config: nil

  @spec new(ExMemvid.Config.t()) :: {:ok, t()} | {:error, term()}
  def new(config) do
    with {:ok, index} <-
           Hnsw.Index.new(
             get_in(config, [:index, :vector_search_space]),
             get_in(config, [:index, :embedding_dimensions]),
             get_in(config, [:index, :max_elements])
           ) do
      {:ok,
       %__MODULE__{
         index: index,
         config: config
       }}
    end
  end

  @spec add_items(t(), list(String.t()), list(integer())) :: {:ok, t()} | {:error, atom()}
  def add_items(search_state, chunks, frame_numbers) do
    {valid_chunks, valid_frame_numbers} =
      Enum.zip(chunks, frame_numbers)
      |> Enum.filter(fn {chunk, _frame} -> valid_chunk?(chunk) end)
      |> Enum.unzip()

    opts = %{
      model: get_in(search_state.config, [:embedding, :model]),
      dimension: get_in(search_state.config, [:embedding, :dimension]),
      batch_size: get_in(search_state.config, [:embedding, :batch_size]),
      max_sequence_length: get_in(search_state.config, [:embedding, :max_sequence_length])
    }

    with {:ok, embeddings} <-
           Embedding.embed_texts(
             get_in(search_state.config, [:embedding, :module]),
             valid_chunks,
             opts
           ),
         {:ok, start_id} <- Hnsw.Index.get_current_count(search_state.index),
         new_ids = Enum.to_list(start_id..(start_id + length(valid_chunks) - 1)),
         embeddings_tensor = Nx.concatenate(embeddings, axis: 0),
         ef_construction = get_in(search_state.config, [:index, :ef_construction]),
         :ok <-
           Hnsw.Index.add_items(search_state.index, embeddings_tensor,
             ids: new_ids,
             ef_construction: ef_construction
           ) do
      new_metadata =
        Enum.zip(new_ids, Enum.zip(valid_chunks, valid_frame_numbers))
        |> Enum.into(%{}, fn {id, {chunk, frame}} ->
          {id, %{id: id, text_snippet: String.slice(chunk, 0, 100), frame_num: frame}}
        end)

      new_frame_to_chunks =
        Enum.zip(new_ids, valid_frame_numbers)
        |> Enum.group_by(
          fn {_id, frame_num} -> frame_num end,
          fn {id, _frame_num} -> id end
        )

      {:ok,
       %{
         search_state
         | metadata: Map.merge(search_state.metadata, new_metadata),
           frame_to_chunks:
             Map.merge(search_state.frame_to_chunks, new_frame_to_chunks, fn _key, list1, list2 ->
               list1 ++ list2
             end)
       }}
    end
  end

  @spec search(t(), String.t(), integer()) :: {:ok, list(map())} | {:error, term()}
  def search(search_state, query, top_k \\ 5) do
    opts = %{
      model: get_in(search_state.config, [:embedding, :model]),
      dimension: get_in(search_state.config, [:embedding, :dimension]),
      batch_size: get_in(search_state.config, [:embedding, :batch_size]),
      max_sequence_length: get_in(search_state.config, [:embedding, :max_sequence_length])
    }

    with {:ok, query_embedding} <-
           Embedding.embed_text(
             get_in(search_state.config, [:embedding, :module]),
             query,
             opts
           ),
         ef_search = get_in(search_state.config, [:index, :ef_search]),
         {:ok, indices, _distances} <-
           Hnsw.Index.knn_query(search_state.index, query_embedding,
             k: top_k,
             ef_search: ef_search
           ) do
      indices_list = Nx.to_flat_list(indices)

      metadata_results =
        indices_list
        |> Enum.map(&round/1)
        |> Enum.map(&Map.get(search_state.metadata, &1))
        |> Enum.reject(&is_nil/1)

      {:ok, metadata_results}
    end
  end

  @spec get_stats(t()) :: {:ok, map()} | {:error, term()}
  def get_stats(search_state) do
    with {:ok, count} <- Hnsw.Index.get_current_count(search_state.index) do
      stats = %{
        total_items: count,
        embedding_dimensions: get_in(search_state.config, [:index, :embedding_dimensions]),
        vector_search_space: get_in(search_state.config, [:index, :vector_search_space]),
        known_frames: Map.keys(search_state.frame_to_chunks) |> length()
      }

      {:ok, stats}
    end
  end

  @spec get_chunk_by_id(t(), integer()) :: {:ok, map()} | :not_found
  def get_chunk_by_id(search_state, id) do
    case Map.get(search_state.metadata, id) do
      nil -> :not_found
      metadata -> {:ok, metadata}
    end
  end

  @spec get_chunks_by_frame(t(), integer()) :: {:ok, list(map())}
  def get_chunks_by_frame(search_state, frame_number) do
    chunk_ids = Map.get(search_state.frame_to_chunks, frame_number, [])

    results =
      chunk_ids
      |> Enum.map(fn id -> get_chunk_by_id(search_state, id) end)
      |> Enum.filter(fn tuple -> elem(tuple, 0) == :ok end)
      |> Enum.map(fn {:ok, metadata} -> metadata end)

    {:ok, results}
  end

  @spec save(t(), Path.t()) :: :ok | {:error, term()}
  def save(search_state, path) do
    path = Path.expand(path)
    hnsw_path = Path.join(Path.dirname(path), "#{Path.basename(path, ".json")}.hnsw")

    File.mkdir_p!(Path.dirname(path))

    :ok = Hnsw.Index.save_index(search_state.index, hnsw_path)

    metadata_to_save = %{
      metadata: search_state.metadata,
      frame_to_chunks: search_state.frame_to_chunks,
      config: search_state.config
    }

    File.write(path, Jason.encode!(metadata_to_save))
  end

  @spec load(Config.t(), Path.t()) :: {:ok, t()} | {:error, term()}
  def load(config, path) do
    path = Path.expand(path)
    hnsw_path = Path.join(Path.dirname(path), "#{Path.basename(path, ".json")}.hnsw")

    with {:ok, metadata_json} <- File.read(path),
         {:ok, loaded_data} <- Jason.decode(metadata_json, keys: :atoms),
         {:ok, index} <-
           Hnsw.Index.load_index(
             get_in(config, [:index, :vector_search_space]),
             get_in(config, [:index, :embedding_dimensions]),
             hnsw_path,
             max_elements: get_in(config, [:index, :max_elements])
           ) do
      metadata_map =
        for {k, v} <- loaded_data.metadata,
            into: %{},
            do: {
              k
              |> Atom.to_string()
              |> String.to_integer(),
              v
            }

      frame_to_chunks_map =
        for {k, v} <- loaded_data.frame_to_chunks,
            into: %{},
            do: {
              k
              |> Atom.to_string()
              |> String.to_integer(),
              v
            }

      search_state = %__MODULE__{
        index: index,
        metadata: metadata_map,
        frame_to_chunks: frame_to_chunks_map,
        config: config
      }

      {:ok, search_state}
    end
  end

  defp valid_chunk?(chunk) do
    is_binary(chunk) and String.length(String.trim(chunk)) > 0
  end
end
