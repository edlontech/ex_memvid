defmodule ExMemvid.IndexTest do
  use ExUnit.Case, async: true

  alias ExMemvid.Index
  alias ExMemvid.MockEmbedding

  defp default_config do
    embedding_config = %{
      module: MockEmbedding,
      model: "mock_model",
      dimension: 3,
      batch_size: 32,
      max_sequence_length: 512
    }

    %{
      embedding: embedding_config,
      index: %{
        vector_search_space: :cosine,
        embedding_dimensions: 3,
        max_elements: 100,
        ef_construction: 100,
        ef_search: 10
      }
    }
  end

  describe "new/1" do
    test "creates a new Index with a valid config" do
      config = default_config()

      assert {:ok, %Index{index: index, metadata: %{}, frame_to_chunks: %{}, config: ^config}} =
               Index.new(config)

      assert index.__struct__ == HNSWLib.Index
      {:ok, count} = HNSWLib.Index.get_current_count(index)
      assert count == 0
    end
  end

  describe "add_items/3" do
    test "adds valid items to the index and updates metadata" do
      {:ok, state} = Index.new(default_config())
      chunks = ["hello world", "another chunk"]
      frame_numbers = [10, 20]

      {:ok, new_state} = Index.add_items(state, chunks, frame_numbers)

      # Check metadata map
      assert map_size(new_state.metadata) == 2
      assert Map.keys(new_state.metadata) == [0, 1]

      metadata_values = Map.values(new_state.metadata) |> Enum.sort_by(& &1.id)
      assert Enum.map(metadata_values, & &1.text_snippet) == ["hello world", "another chunk"]
      assert Enum.map(metadata_values, & &1.frame_num) == [10, 20]

      # Check frame_to_chunks map
      assert new_state.frame_to_chunks == %{10 => [0], 20 => [1]}

      {:ok, count} = HNSWLib.Index.get_current_count(new_state.index)
      assert count == 2
    end

    test "skips invalid chunks and adds only valid ones" do
      {:ok, state} = Index.new(default_config())
      chunks = ["valid chunk", "", "  ", "another valid"]
      frame_numbers = [1, 2, 3, 5]

      {:ok, new_state} = Index.add_items(state, chunks, frame_numbers)

      # Assert that only the two valid chunks were added
      assert map_size(new_state.metadata) == 2
      assert Map.get(new_state.metadata, 0).text_snippet == "valid chunk"
      assert Map.get(new_state.metadata, 1).text_snippet == "another valid"

      assert new_state.frame_to_chunks == %{1 => [0], 5 => [1]}

      {:ok, count} = HNSWLib.Index.get_current_count(new_state.index)
      assert count == 2
    end
  end

  describe "search/3" do
    test "searches for items and returns the closest matches" do
      {:ok, state} = Index.new(default_config())
      chunks = ["apple", "apricot", "banana"]
      frame_numbers = [1, 2, 3]

      {:ok, state} = Index.add_items(state, chunks, frame_numbers)

      # "apply" vector should be closer to "apple" and "apricot" than "banana"
      {:ok, results} = Index.search(state, "apply", 2)
      assert length(results) == 2
      result_snippets = Enum.map(results, & &1.text_snippet)
      assert "apple" in result_snippets
      assert "apricot" in result_snippets
      refute "banana" in result_snippets
    end
  end

  describe "new utility functions" do
    setup do
      {:ok, state} = Index.new(default_config())
      chunks = ["chunk one", "chunk two", "chunk three"]
      # Note: frame 10 has two chunks
      frame_numbers = [10, 20, 10]
      {:ok, state} = Index.add_items(state, chunks, frame_numbers)
      {:ok, state: state}
    end

    test "get_stats/1 returns correct statistics", %{state: state} do
      {:ok, stats} = Index.get_stats(state)
      assert stats.total_items == 3
      assert stats.embedding_dimensions == 3
      assert stats.known_frames == 2
    end

    test "get_chunk_by_id/2 retrieves a chunk or returns not_found", %{state: state} do
      # Test found
      assert {:ok, %{id: 1, text_snippet: "chunk two", frame_num: 20}} =
               Index.get_chunk_by_id(state, 1)

      # Test not found
      assert :not_found == Index.get_chunk_by_id(state, 99)
    end

    test "get_chunks_by_frame/2 returns all chunks for a given frame", %{state: state} do
      # Test frame with multiple chunks
      {:ok, results_frame_10} = Index.get_chunks_by_frame(state, 10)
      assert length(results_frame_10) == 2
      snippets = Enum.map(results_frame_10, & &1.text_snippet) |> Enum.sort()
      assert snippets == ["chunk one", "chunk three"]

      # Test frame with one chunk
      {:ok, results_frame_20} = Index.get_chunks_by_frame(state, 20)
      assert length(results_frame_20) == 1
      assert hd(results_frame_20).text_snippet == "chunk two"

      # Test frame with no chunks
      {:ok, results_frame_99} = Index.get_chunks_by_frame(state, 99)
      assert results_frame_99 == []
    end
  end

  describe "save/2 and load/1" do
    test "saves and loads an index to/from a file" do
      {:ok, tmp_dir} = Briefly.create(type: :directory)
      path = Path.join(tmp_dir, "my_index.json")

      {:ok, original_state} = Index.new(default_config())
      chunks = ["first item", "second item"]
      frame_numbers = [100, 200]
      {:ok, original_state} = Index.add_items(original_state, chunks, frame_numbers)

      :ok = Index.save(original_state, path)

      assert File.exists?(path)
      hnsw_path = Path.join(tmp_dir, "my_index.hnsw")
      assert File.exists?(hnsw_path)

      case Index.load(default_config(), path) do
        {:ok, loaded_state} ->
          assert loaded_state.metadata == original_state.metadata
          assert loaded_state.frame_to_chunks == original_state.frame_to_chunks

          {:ok, results} = Index.search(loaded_state, "first", 1)
          assert length(results) == 1
          assert hd(results).text_snippet == "first item"

        {:error, reason} ->
          flunk("Failed to load index. Reason: #{inspect(reason)}")
      end
    end
  end
end
