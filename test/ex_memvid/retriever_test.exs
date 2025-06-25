defmodule ExMemvid.RetrieverTest do
  use Nx.Case, async: false

  alias ExMemvid.Config
  alias ExMemvid.Embedding.Supervisor
  alias ExMemvid.Index
  alias ExMemvid.QR
  alias ExMemvid.Retriever

  setup do
    config = Config.validate!([])

    _ = Supervisor.start_link(config)

    chunks = [
      "elixir is a functional language",
      "phoenix is a web framework",
      "erlang runs on the beam virtual machine",
      "genserver provides stateful server processes",
      "ets tables store data in memory",
      "supervision trees handle process failures",
      "otp provides building blocks for applications",
      "pattern matching is a powerful feature",
      "immutable data structures prevent bugs",
      "the actor model enables concurrency"
    ]

    {:ok, temp_dir} = Briefly.create(type: :directory)

    index_path = Path.join(temp_dir, "test_index.json")
    video_path = Path.join(temp_dir, "test_video.mp4")
    frames_dir = Path.join(temp_dir, "frames")

    File.mkdir_p!(frames_dir)

    {:ok, index} = Index.new(config)
    {:ok, index} = Index.add_items(index, chunks, Enum.to_list(0..(length(chunks) - 1)))
    :ok = Index.save(index, index_path)

    # 2. Create QR code frames for the video
    Enum.each(Enum.with_index(chunks), fn {chunk, i} ->
      qr_content = Jason.encode!(%{id: i, text: chunk, frame: i})
      {:ok, png_binary} = QR.encode(qr_content, config)

      File.write!(
        Path.join(frames_dir, "frame_#{:erlang.integer_to_binary(i, 10)}.png"),
        png_binary
      )
    end)

    # 3. Create a video from the frames
    ffmpeg_args = [
      "-framerate",
      "1",
      "-i",
      Path.join(frames_dir, "frame_%d.png"),
      "-t",
      "2",
      video_path
    ]

    System.cmd("ffmpeg", ffmpeg_args)

    {:ok, video_path: video_path, index_path: index_path, config: config, chunks: chunks}
  end

  test "search/3 retrieves and decodes content", %{
    video_path: video_path,
    index_path: index_path,
    config: config,
    chunks: chunks
  } do
    {:ok, pid} =
      Retriever.start_link(video_path, index_path, config)

    query = "elixir"
    {:ok, [result | _]} = Retriever.search(pid, query)

    assert result == hd(chunks)
  end
end
