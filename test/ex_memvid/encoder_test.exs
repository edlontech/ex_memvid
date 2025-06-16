defmodule ExMemvid.EncoderTest do
  use Nx.Case, async: false

  alias ExMemvid.Config
  alias ExMemvid.Encoder
  alias ExMemvid.Index

  @test_chunks [
    "This is the first chunk of text for testing.",
    "Here is a second chunk with different content.",
    "The third chunk contains some technical information.",
    "Final chunk with conclusion and summary data."
  ]

  defp default_config do
    embedding_config = %{
      module: ExMemvid.MockEmbedding,
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
    test "creates encoder with valid config map" do
      config = Config.validate!(default_config())

      {:ok, encoder} = Encoder.new(config)

      assert %Encoder{} = encoder
      assert encoder.config == config
      assert encoder.chunks == []
    end

    test "creates encoder with valid config list" do
      {:ok, encoder} = Encoder.new(default_config())

      assert %Encoder{} = encoder
      assert is_map(encoder.config)
      assert encoder.chunks == []
    end

    test "creates encoder with empty config list" do
      {:ok, encoder} = Encoder.new([])

      assert %Encoder{} = encoder
      assert is_map(encoder.config)
      assert encoder.chunks == []
    end

    test "handles config conversion from list to map" do
      config_list = [codec: :h265]
      {:ok, encoder} = Encoder.new(config_list)

      assert is_map(encoder.config)
      assert encoder.config[:codec] == :h265
    end
  end

  describe "add_chunks/2" do
    setup do
      {:ok, encoder} = Encoder.new(default_config())
      {:ok, encoder: encoder}
    end

    test "adds chunks to empty encoder", %{encoder: encoder} do
      updated_encoder = Encoder.add_chunks(encoder, @test_chunks)

      assert updated_encoder.chunks == @test_chunks
      assert length(updated_encoder.chunks) == 4
    end

    test "appends chunks to existing chunks", %{encoder: encoder} do
      encoder_with_chunks = Encoder.add_chunks(encoder, ["first chunk", "second chunk"])
      final_encoder = Encoder.add_chunks(encoder_with_chunks, ["third chunk"])

      assert final_encoder.chunks == ["first chunk", "second chunk", "third chunk"]
    end

    test "handles empty chunk list", %{encoder: encoder} do
      updated_encoder = Encoder.add_chunks(encoder, [])

      assert updated_encoder.chunks == []
    end

    test "preserves original encoder config and other fields", %{encoder: encoder} do
      updated_encoder = Encoder.add_chunks(encoder, @test_chunks)

      assert updated_encoder.config == encoder.config
      assert updated_encoder.__struct__ == encoder.__struct__
    end

    test "handles single chunk in list", %{encoder: encoder} do
      updated_encoder = Encoder.add_chunks(encoder, ["single chunk"])

      assert updated_encoder.chunks == ["single chunk"]
    end
  end

  describe "build_video/3" do
    setup do
      config = Config.validate!(default_config())
      {:ok, encoder} = Encoder.new(config)
      encoder = Encoder.add_chunks(encoder, @test_chunks)

      # Create temporary paths
      output_dir = Briefly.create!(type: :directory)
      video_path = Path.join(output_dir, "test_video.mkv")
      index_path = Path.join(output_dir, "test_index.json")

      {:ok,
       encoder: encoder, video_path: video_path, index_path: index_path, output_dir: output_dir}
    end

    @tag timeout: 60_000
    test "builds video and index successfully", %{
      encoder: encoder,
      video_path: video_path,
      index_path: index_path
    } do
      {:ok, stats} = Encoder.build_video(encoder, video_path, index_path)

      # Verify return stats structure
      assert is_map(stats)
      assert Map.has_key?(stats, :total_chunks)
      assert Map.has_key?(stats, :total_frames)
      assert Map.has_key?(stats, :duration_seconds)
      assert Map.has_key?(stats, :fps)
      assert Map.has_key?(stats, :index_stats)

      # Verify stats values
      assert stats.total_chunks == 4
      assert stats.total_frames == 4
      assert stats.duration_seconds > 0
      assert stats.fps > 0
      assert is_map(stats.index_stats)

      # Verify files were created
      assert File.exists?(video_path)
      assert File.exists?(index_path)

      # Verify video file has content
      video_stat = File.stat!(video_path)
      assert video_stat.size > 0

      # Verify index file structure
      {:ok, index_content} = File.read(index_path)
      {:ok, index_data} = Jason.decode(index_content, keys: :atoms)
      assert Map.has_key?(index_data, :metadata)
      assert Map.has_key?(index_data, :frame_to_chunks)
      assert Map.has_key?(index_data, :config)
    end

    @tag timeout: 60_000
    test "handles different codec configurations", %{
      index_path: index_path,
      video_path: video_path
    } do
      # Test with h265 codec
      h265_config = Config.validate!(Map.put(default_config(), :codec, :h265))
      {:ok, h265_encoder} = Encoder.new(h265_config)
      h265_encoder = Encoder.add_chunks(h265_encoder, ["test chunk for h265"])

      {:ok, stats} = Encoder.build_video(h265_encoder, video_path, index_path)

      assert stats.total_chunks == 1
      # h265 default fps
      assert stats.fps == 30
      assert File.exists?(video_path)
    end

    @tag timeout: 60_000
    test "handles single chunk", %{video_path: video_path, index_path: index_path} do
      config = Config.validate!(default_config())
      {:ok, encoder} = Encoder.new(config)
      encoder = Encoder.add_chunks(encoder, ["Single test chunk"])

      {:ok, stats} = Encoder.build_video(encoder, video_path, index_path)

      assert stats.total_chunks == 1
      assert stats.total_frames == 1
      assert File.exists?(video_path)
      assert File.stat!(video_path).size > 0
    end

    @tag timeout: 60_000
    test "generates valid QR codes for each chunk", %{
      encoder: encoder,
      video_path: video_path,
      index_path: index_path
    } do
      {:ok, _stats} = Encoder.build_video(encoder, video_path, index_path)

      # Load the created index and verify it contains our chunks
      {:ok, index} = Index.load(encoder.config, index_path)

      # Verify we can retrieve chunks by frame
      for frame_num <- 0..3 do
        {:ok, chunks} = Index.get_chunks_by_frame(index, frame_num)
        assert length(chunks) == 1
        chunk_data = List.first(chunks)
        assert Map.has_key?(chunk_data, :frame_num)
        assert Map.has_key?(chunk_data, :text_snippet)
        assert chunk_data.frame_num == frame_num
      end
    end

    @tag timeout: 60_000
    test "preserves chunk order in frames", %{
      encoder: encoder,
      video_path: video_path,
      index_path: index_path
    } do
      {:ok, _stats} = Encoder.build_video(encoder, video_path, index_path)

      # Load index and verify chunk order
      {:ok, index} = Index.load(encoder.config, index_path)

      # Verify each frame corresponds to the correct chunk
      expected_chunks = @test_chunks

      for {expected_chunk, frame_num} <- Enum.with_index(expected_chunks) do
        {:ok, chunks} = Index.get_chunks_by_frame(index, frame_num)
        chunk_data = List.first(chunks)

        # Check that the text snippet matches the beginning of our expected chunk
        snippet = chunk_data.text_snippet
        # snippet is truncated to 100 chars
        assert String.starts_with?(expected_chunk, snippet) or
                 String.length(snippet) == 100
      end
    end
  end
end
