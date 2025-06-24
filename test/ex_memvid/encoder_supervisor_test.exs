defmodule ExMemvid.EncoderSupervisorTest do
  use ExUnit.Case

  alias ExMemvid.Config
  alias ExMemvid.Encoder
  alias ExMemvid.EncoderSupervisor

  setup do
    case Process.whereis(EncoderSupervisor) do
      nil ->
        {:ok, _sup} = EncoderSupervisor.start_link([])
        :ok

      _pid ->
        EncoderSupervisor.stop_all_encoders()
        :ok
    end

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
        }
      )

    on_exit(fn ->
      if Process.whereis(EncoderSupervisor) do
        try do
          EncoderSupervisor.stop_all_encoders()
        catch
          :exit, _ -> :ok
        end
      end
    end)

    {:ok, config: config}
  end

  describe "start_encoder/1" do
    test "starts an encoder with required options", %{config: config} do
      assert {:ok, pid} =
               EncoderSupervisor.start_encoder(
                 index_name: "test_index_001",
                 config: config
               )

      assert is_pid(pid)
      assert Process.alive?(pid)

      {state, data} = Encoder.get_state(pid)
      assert state == :ready
      assert data.index_name == "test_index_001"
    end

    test "starts multiple encoders independently", %{config: config} do
      assert {:ok, pid1} =
               EncoderSupervisor.start_encoder(
                 index_name: "index_001",
                 config: config
               )

      assert {:ok, pid2} =
               EncoderSupervisor.start_encoder(
                 index_name: "index_002",
                 config: config
               )

      assert {:ok, pid3} =
               EncoderSupervisor.start_encoder(
                 index_name: "index_003",
                 config: config
               )

      assert pid1 != pid2
      assert pid2 != pid3
      assert pid1 != pid3

      assert Process.alive?(pid1)
      assert Process.alive?(pid2)
      assert Process.alive?(pid3)
    end

    test "starts encoder with custom name", %{config: config} do
      name = :"test_encoder_#{System.unique_integer()}"

      assert {:ok, pid} =
               EncoderSupervisor.start_encoder(
                 index_name: "named_index",
                 config: config,
                 name: name
               )

      assert Process.whereis(name) == pid
    end

    test "starts encoder with custom restart strategy", %{config: config} do
      assert {:ok, pid} =
               EncoderSupervisor.start_encoder(
                 index_name: "restart_test",
                 config: config,
                 restart: :transient
               )

      assert is_pid(pid)
    end

    test "fails without required options" do
      assert_raise KeyError, fn ->
        EncoderSupervisor.start_encoder([])
      end
    end
  end

  describe "stop_encoder/1" do
    setup %{config: config} do
      {:ok, pid} =
        EncoderSupervisor.start_encoder(
          index_name: "to_stop",
          config: config
        )

      {:ok, pid: pid}
    end

    test "stops encoder by pid", %{pid: pid} do
      assert Process.alive?(pid)
      assert :ok = EncoderSupervisor.stop_encoder(pid)

      Process.sleep(50)
      refute Process.alive?(pid)
    end

    test "stops encoder by name", %{config: config} do
      name = :"stop_by_name_#{System.unique_integer()}"

      {:ok, pid} =
        EncoderSupervisor.start_encoder(
          index_name: "named_stop",
          config: config,
          name: name
        )

      assert Process.alive?(pid)
      assert :ok = EncoderSupervisor.stop_encoder(name)

      Process.sleep(50)
      refute Process.alive?(pid)
      assert Process.whereis(name) == nil
    end

    test "returns error for non-existent encoder" do
      assert {:error, :not_found} = EncoderSupervisor.stop_encoder(self())
    end
  end

  describe "list_encoders/0" do
    test "returns empty list when no encoders", %{config: _config} do
      EncoderSupervisor.stop_all_encoders()
      assert [] = EncoderSupervisor.list_encoders()
    end

    test "returns list of running encoders", %{config: config} do
      {:ok, pid1} =
        EncoderSupervisor.start_encoder(
          index_name: "list_test_1",
          config: config
        )

      {:ok, pid2} =
        EncoderSupervisor.start_encoder(
          index_name: "list_test_2",
          config: config
        )

      encoders = EncoderSupervisor.list_encoders()
      assert length(encoders) == 2

      pids = Enum.map(encoders, fn {_id, pid, _type, _modules} -> pid end)
      assert pid1 in pids
      assert pid2 in pids
    end
  end

  describe "count_encoders/0" do
    test "returns zero when no encoders" do
      EncoderSupervisor.stop_all_encoders()
      assert EncoderSupervisor.count_encoders() == 0
    end

    test "returns correct count", %{config: config} do
      assert EncoderSupervisor.count_encoders() == 0

      {:ok, _} =
        EncoderSupervisor.start_encoder(
          index_name: "count_1",
          config: config
        )

      assert EncoderSupervisor.count_encoders() == 1

      {:ok, _} =
        EncoderSupervisor.start_encoder(
          index_name: "count_2",
          config: config
        )

      assert EncoderSupervisor.count_encoders() == 2

      {:ok, pid3} =
        EncoderSupervisor.start_encoder(
          index_name: "count_3",
          config: config
        )

      assert EncoderSupervisor.count_encoders() == 3

      EncoderSupervisor.stop_encoder(pid3)
      Process.sleep(50)
      assert EncoderSupervisor.count_encoders() == 2
    end
  end

  describe "stop_all_encoders/0" do
    test "stops all running encoders", %{config: config} do
      {:ok, pid1} =
        EncoderSupervisor.start_encoder(
          index_name: "stop_all_1",
          config: config
        )

      {:ok, pid2} =
        EncoderSupervisor.start_encoder(
          index_name: "stop_all_2",
          config: config
        )

      {:ok, pid3} =
        EncoderSupervisor.start_encoder(
          index_name: "stop_all_3",
          config: config
        )

      assert Process.alive?(pid1)
      assert Process.alive?(pid2)
      assert Process.alive?(pid3)

      assert :ok = EncoderSupervisor.stop_all_encoders()

      Process.sleep(50)
      refute Process.alive?(pid1)
      refute Process.alive?(pid2)
      refute Process.alive?(pid3)

      assert EncoderSupervisor.count_encoders() == 0
    end
  end

  describe "get_encoders_info/0" do
    test "returns empty map when no encoders" do
      EncoderSupervisor.stop_all_encoders()
      assert %{} = EncoderSupervisor.get_encoders_info()
    end

    test "returns state info for all encoders", %{config: config} do
      {:ok, pid1} =
        EncoderSupervisor.start_encoder(
          index_name: "info_test_1",
          config: config
        )

      {:ok, pid2} =
        EncoderSupervisor.start_encoder(
          index_name: "info_test_2",
          config: config
        )

      :ok = Encoder.add_chunks(pid2, ["chunk1", "chunk2"])

      info = EncoderSupervisor.get_encoders_info()

      assert map_size(info) == 2
      assert Map.has_key?(info, pid1)
      assert Map.has_key?(info, pid2)

      {state1, data1} = info[pid1]
      assert state1 == :ready
      assert data1.index_name == "info_test_1"

      {state2, data2} = info[pid2]
      assert state2 == :collecting
      assert data2.index_name == "info_test_2"
      assert length(data2.chunks) == 2
    end

    test "handles crashed encoders gracefully", %{config: config} do
      {:ok, pid1} =
        EncoderSupervisor.start_encoder(
          index_name: "good_encoder",
          config: config
        )

      {:ok, pid2} =
        EncoderSupervisor.start_encoder(
          index_name: "bad_encoder",
          config: config
        )

      Process.exit(pid2, :kill)
      Process.sleep(50)

      info = EncoderSupervisor.get_encoders_info()

      assert map_size(info) >= 1
      assert Map.has_key?(info, pid1)

      {state, data} = info[pid1]
      assert state == :ready
      assert data.index_name == "good_encoder"
    end
  end

  describe "supervisor behavior" do
    test "isolates encoder failures", %{config: config} do
      {:ok, pid1} =
        EncoderSupervisor.start_encoder(
          index_name: "survivor",
          config: config
        )

      {:ok, pid2} =
        EncoderSupervisor.start_encoder(
          index_name: "crasher",
          config: config
        )

      Process.exit(pid2, :kill)
      Process.sleep(50)

      assert Process.alive?(pid1)
      refute Process.alive?(pid2)

      assert :ok = Encoder.add_chunks(pid1, ["still working"])
      {state, data} = Encoder.get_state(pid1)
      assert state == :collecting
      assert data.chunks == ["still working"]
    end

    test "respects restart strategy", %{config: config} do
      {:ok, temp_pid} =
        EncoderSupervisor.start_encoder(
          index_name: "temporary",
          config: config,
          restart: :temporary
        )

      ref = Process.monitor(temp_pid)
      Process.exit(temp_pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^temp_pid, :killed}

      Process.sleep(100)

      assert EncoderSupervisor.count_encoders() == 0
    end

    test "handles concurrent operations", %{config: config} do
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            EncoderSupervisor.start_encoder(
              index_name: "concurrent_#{i}",
              config: config
            )
          end)
        end

      results = Task.await_many(tasks)

      assert Enum.all?(results, fn result ->
               match?({:ok, _pid}, result)
             end)

      assert EncoderSupervisor.count_encoders() == 10
    end
  end
end
