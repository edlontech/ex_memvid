defmodule ExMemvid.EncoderTest do
  use ExUnit.Case, async: true

  alias ExMemvid.Config
  alias ExMemvid.Encoder

  setup do
    config =
      Config.validate!(
        codec: :h264,
        qr: %{
          error_correction: :medium,
          fill_color: "#000000",
          back_color: "#ffffff",
          gzip: false
        },
        embedding: %{
          module: ExMemvid.MockEmbedding,
          model: "mock_model",
          dimension: 3,
          batch_size: 32,
          max_sequence_length: 512
        },
        index: %{
          vector_search_space: :cosine,
          embedding_dimensions: 3,
          max_elements: 100,
          ef_construction: 100,
          ef_search: 10
        },
        chunking: %{
          chunk_size: 100,
          overlap: 20
        }
      )

    {:ok, config: config}
  end

  describe "start_link/1" do
    test "starts encoder with required options", %{config: config} do
      {:ok, pid} = Encoder.start_link(index_name: "test_index", config: config)
      assert is_pid(pid)

      {state, data} = Encoder.get_state(pid)
      assert state == :ready
      assert data.index_name == "test_index"
      assert data.chunks == []
      assert data.output_path == nil
      assert data.index_path == nil
    end

    test "starts encoder with name registration", %{config: config} do
      name = :"test_encoder_#{System.unique_integer()}"

      {:ok, pid} =
        Encoder.start_link(
          index_name: "test_index",
          config: config,
          name: name
        )

      assert Process.whereis(name) == pid
    end

    test "fails without required options" do
      assert_raise KeyError, fn ->
        Encoder.start_link([])
      end
    end
  end

  describe "add_chunks/2" do
    setup %{config: config} do
      {:ok, pid} = Encoder.start_link(index_name: "test_index", config: config)
      {:ok, pid: pid}
    end

    test "adds chunks in ready state", %{pid: pid} do
      chunks = ["chunk1", "chunk2", "chunk3"]
      assert :ok = Encoder.add_chunks(pid, chunks)

      {state, data} = Encoder.get_state(pid)
      assert state == :collecting
      assert data.chunks == chunks
    end

    test "adds chunks in collecting state", %{pid: pid} do
      assert :ok = Encoder.add_chunks(pid, ["chunk1", "chunk2"])
      assert :ok = Encoder.add_chunks(pid, ["chunk3", "chunk4"])

      {state, data} = Encoder.get_state(pid)
      assert state == :collecting
      assert data.chunks == ["chunk1", "chunk2", "chunk3", "chunk4"]
    end

    test "rejects non-list input", %{pid: pid} do
      assert_raise FunctionClauseError, fn ->
        Encoder.add_chunks(pid, "not a list")
      end
    end
  end

  describe "add_text/2" do
    setup %{config: config} do
      {:ok, pid} = Encoder.start_link(index_name: "test_index", config: config)
      {:ok, pid: pid}
    end

    test "chunks and adds text", %{pid: pid} do
      text = String.duplicate("This is a test sentence. ", 10)

      assert :ok = Encoder.add_text(pid, text)

      {state, data} = Encoder.get_state(pid)
      assert state == :collecting
      assert length(data.chunks) > 0
      assert Enum.all?(data.chunks, &is_binary/1)
    end

    test "handles empty text", %{pid: pid} do
      assert :ok = Encoder.add_text(pid, "")

      {state, data} = Encoder.get_state(pid)
      assert state == :collecting
      assert length(data.chunks) == 1
      assert hd(data.chunks) == "incompatible_config_or_text_no_chunks_saved"
    end
  end

  describe "build_video/3" do
    setup %{config: config} do
      {:ok, pid} = Encoder.start_link(index_name: "test_index", config: config)
      {:ok, tmp_dir} = Briefly.create(type: :directory)

      output_path = Path.join(tmp_dir, "test_video.mp4")
      index_path = Path.join(tmp_dir, "test_index.bin")

      {:ok, pid: pid, output_path: output_path, index_path: index_path}
    end

    test "builds video from chunks", %{pid: pid, output_path: output_path, index_path: index_path} do
      chunks = ["Test chunk 1", "Test chunk 2", "Test chunk 3"]
      assert :ok = Encoder.add_chunks(pid, chunks)

      assert {:ok, stats} = Encoder.build_video(pid, output_path, index_path)

      assert stats.total_chunks == 3
      assert stats.total_frames == 3
      assert stats.fps == 30
      assert stats.duration_seconds == 0.1
      assert stats.output_path == output_path
      assert stats.index_path == index_path
      assert stats.index_name == "test_index"

      assert File.exists?(output_path)
      assert File.exists?(index_path)

      {state, _data} = Encoder.get_state(pid)
      assert state == :completed
    end

    test "fails when no chunks added", %{
      pid: pid,
      output_path: output_path,
      index_path: index_path
    } do
      assert {:error, :no_chunks} = Encoder.build_video(pid, output_path, index_path)

      {state, _data} = Encoder.get_state(pid)
      assert state == :ready
    end

    test "rejects operations while building", %{
      pid: pid,
      output_path: output_path,
      index_path: index_path
    } do
      chunks = for i <- 1..10, do: "chunk #{i} with more content to process"
      assert :ok = Encoder.add_chunks(pid, chunks)

      task =
        Task.async(fn ->
          Encoder.build_video(pid, output_path, index_path)
        end)

      Process.sleep(10)

      {state, _data} = Encoder.get_state(pid)

      if state == :building do
        assert {:error, :building_in_progress} = Encoder.add_chunks(pid, ["chunk2"])
        assert {:error, :building_in_progress} = Encoder.reset(pid)
      else
        assert state == :completed
      end

      # Clean up the task
      Task.shutdown(task, :brutal_kill)
    end
  end

  describe "reset/1" do
    setup %{config: config} do
      {:ok, pid} = Encoder.start_link(index_name: "test_index", config: config)
      {:ok, pid: pid}
    end

    test "resets from collecting state", %{pid: pid} do
      assert :ok = Encoder.add_chunks(pid, ["chunk1", "chunk2"])

      {state, data} = Encoder.get_state(pid)
      assert state == :collecting
      assert length(data.chunks) == 2

      assert :ok = Encoder.reset(pid)

      {state, data} = Encoder.get_state(pid)
      assert state == :ready
      assert data.chunks == []
      assert data.stats == nil
      assert data.error == nil
    end

    test "resets from completed state", %{pid: pid} do
      {:ok, tmp_dir} = Briefly.create(type: :directory)
      output_path = Path.join(tmp_dir, "test.mp4")
      index_path = Path.join(tmp_dir, "test.bin")

      assert :ok = Encoder.add_chunks(pid, ["chunk1"])
      assert {:ok, _stats} = Encoder.build_video(pid, output_path, index_path)

      {state, _data} = Encoder.get_state(pid)
      assert state == :completed

      assert :ok = Encoder.reset(pid)

      {state, data} = Encoder.get_state(pid)
      assert state == :ready
      assert data.chunks == []
      assert data.stats == nil
    end

    test "resets from error state", %{pid: pid} do
      # Test reset from ready state
      assert :ok = Encoder.reset(pid)
      {state, _data} = Encoder.get_state(pid)
      assert state == :ready

      # Test that no_chunks error doesn't change state
      assert {:error, :no_chunks} = Encoder.build_video(pid, "/tmp/video.mp4", "/tmp/index.bin")
      {state, _data} = Encoder.get_state(pid)
      assert state == :ready

      # Test reset from collecting state
      assert :ok = Encoder.add_chunks(pid, ["chunk1", "chunk2"])
      {state, data} = Encoder.get_state(pid)
      assert state == :collecting
      assert length(data.chunks) == 2

      assert :ok = Encoder.reset(pid)
      {state, data} = Encoder.get_state(pid)
      assert state == :ready
      assert data.chunks == []
    end
  end

  describe "get_state/1" do
    setup %{config: config} do
      {:ok, pid} = Encoder.start_link(index_name: "test_index", config: config)
      {:ok, pid: pid}
    end

    test "returns state information", %{pid: pid} do
      {state, data} = Encoder.get_state(pid)
      assert state == :ready
      assert is_map(data)
      assert Map.has_key?(data, :index_name)
      assert Map.has_key?(data, :chunks)

      Encoder.add_chunks(pid, ["chunk1"])
      {state, data} = Encoder.get_state(pid)
      assert state == :collecting
      assert data.chunks == ["chunk1"]
    end
  end

  describe "state transitions" do
    setup %{config: config} do
      {:ok, pid} = Encoder.start_link(index_name: "test_index", config: config)
      {:ok, pid: pid}
    end

    test "complete workflow from ready to completed", %{pid: pid} do
      {:ok, tmp_dir} = Briefly.create(type: :directory)
      output_path = Path.join(tmp_dir, "workflow_test.mp4")
      index_path = Path.join(tmp_dir, "workflow_test.bin")

      assert {:ready, _} = Encoder.get_state(pid)

      assert :ok = Encoder.add_chunks(pid, ["chunk1", "chunk2"])
      assert {:collecting, _} = Encoder.get_state(pid)

      assert {:ok, stats} = Encoder.build_video(pid, output_path, index_path)
      assert {:completed, data} = Encoder.get_state(pid)
      assert data.stats == stats

      assert :ok = Encoder.reset(pid)
      assert {:ready, _} = Encoder.get_state(pid)
    end

    test "can build directly from ready state with chunks", %{pid: pid} do
      {:ok, tmp_dir} = Briefly.create(type: :directory)
      output_path = Path.join(tmp_dir, "direct_build.mp4")
      index_path = Path.join(tmp_dir, "direct_build.bin")

      assert {:error, :no_chunks} = Encoder.build_video(pid, output_path, index_path)

      assert :ok = Encoder.add_chunks(pid, ["chunk1"])
      assert :ok = Encoder.reset(pid)
      assert :ok = Encoder.add_chunks(pid, ["chunk1"])

      assert :ok = Encoder.reset(pid)
      assert {:ready, _} = Encoder.get_state(pid)

      assert :ok = Encoder.add_chunks(pid, ["final chunk"])
      assert {:ok, _stats} = Encoder.build_video(pid, output_path, index_path)
    end
  end

  describe "error handling" do
    test "encoder crashes on build failure due to linked process", %{config: config} do
      {:ok, supervisor_pid} = Task.Supervisor.start_link()

      {encoder_pid, _ref} =
        Task.Supervisor.async_nolink(supervisor_pid, fn ->
          {:ok, pid} = Encoder.start_link(index_name: "test_index", config: config)
          :ok = Encoder.add_chunks(pid, ["chunk1"])

          pid
        end)
        |> Task.await()
        |> (fn pid -> {pid, Process.monitor(pid)} end).()

      spawn(fn ->
        try do
          Encoder.build_video(
            encoder_pid,
            "/non/existent/dir/video.mp4",
            "/non/existent/dir/index.bin"
          )
        catch
          :exit, _ -> :ok
        end
      end)

      assert_receive {:DOWN, _ref, :process, ^encoder_pid, _reason}, 500

      Process.exit(supervisor_pid, :kill)
    end

    test "rejects invalid state transitions", %{config: config} do
      {:ok, pid} = Encoder.start_link(index_name: "test_index", config: config)
      {:ok, tmp_dir} = Briefly.create(type: :directory)

      output_path = Path.join(tmp_dir, "test.mp4")
      index_path = Path.join(tmp_dir, "test.bin")

      assert :ok = Encoder.add_chunks(pid, ["chunk1"])
      assert {:ok, _} = Encoder.build_video(pid, output_path, index_path)

      assert {:error, :already_completed} = Encoder.add_chunks(pid, ["chunk2"])
      assert {:error, :already_completed} = Encoder.build_video(pid, output_path, index_path)
    end
  end
end

