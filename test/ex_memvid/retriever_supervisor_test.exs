defmodule ExMemvid.RetrieverSupervisorTest do
  use ExUnit.Case, async: true

  alias ExMemvid.RetrieverSupervisor

  describe "start_link/1" do
    test "starts the supervisor" do
      assert {:ok, pid} = RetrieverSupervisor.start_link([])
      assert Process.alive?(pid)
    end
  end

  describe "start_retriever/4" do
    setup do
      start_supervised!(RetrieverSupervisor)
      :ok
    end

    test "starts a retriever without name" do
      video_path = "test/fixtures/video.mp4"
      index_path = "test/fixtures/index.hnsw"
      config = %{}

      assert {:error, _} = RetrieverSupervisor.start_retriever(video_path, index_path, config)
    end

    test "starts a retriever with name" do
      video_path = "test/fixtures/video.mp4"
      index_path = "test/fixtures/index.hnsw"
      config = %{}

      assert {:error, _} =
               RetrieverSupervisor.start_retriever(video_path, index_path, config,
                 name: TestRetriever
               )
    end
  end

  describe "list_retrievers/0" do
    setup do
      start_supervised!(RetrieverSupervisor)
      :ok
    end

    test "returns empty list when no retrievers are running" do
      assert [] == RetrieverSupervisor.list_retrievers()
    end
  end

  describe "count_retrievers/0" do
    setup do
      start_supervised!(RetrieverSupervisor)
      :ok
    end

    test "returns 0 when no retrievers are running" do
      assert 0 == RetrieverSupervisor.count_retrievers()
    end
  end

  describe "stop_retriever/1" do
    setup do
      start_supervised!(RetrieverSupervisor)
      :ok
    end

    test "returns error when stopping non-existent retriever by name" do
      assert {:error, :not_found} == RetrieverSupervisor.stop_retriever(NonExistentRetriever)
    end
  end

  describe "get_retriever_info/1" do
    setup do
      start_supervised!(RetrieverSupervisor)
      :ok
    end

    test "returns error for non-existent retriever by name" do
      assert {:error, :not_found} == RetrieverSupervisor.get_retriever_info(NonExistentRetriever)
    end

    test "returns error for non-existent retriever by pid" do
      fake_pid = spawn(fn -> :ok end)
      Process.exit(fake_pid, :kill)
      assert {:error, :not_found} == RetrieverSupervisor.get_retriever_info(fake_pid)
    end
  end

  describe "stop_all_retrievers/0" do
    setup do
      start_supervised!(RetrieverSupervisor)
      :ok
    end

    test "works even when no retrievers are running" do
      assert :ok == RetrieverSupervisor.stop_all_retrievers()
    end
  end
end
