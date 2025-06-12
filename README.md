# ExMemvid

An Elixir Port of [Memvid](https://github.com/Olow304/memvid).

ExMemvid is a proof-of-concept library for storing and retrieving large amounts of text data by encoding it into a video file composed of QR code frames. It leverages modern Elixir libraries for machine learning, video processing, and vector search to provide a unique solution for data storage and semantic retrieval.

## How it Works

The core idea is to treat video frames as a data storage medium. Each frame in the video contains a QR code that holds a chunk of text. A separate search index is created using text embeddings to allow for fast, semantic searching of the content stored in the video.

### Encoding Process

1.  **Text Chunking**: The input text is divided into smaller, manageable chunks.
2.  **Embedding**: A sentence transformer model from Hugging Face (via `Bumblebee`) generates a vector embedding for each text chunk.
3.  **QR Code Generation**: Each text chunk is serialized (optionally with Gzip compression) and encoded into a QR code image.
4.  **Video Encoding**: The QR code images are compiled into a video file, where each image becomes a single frame. The library uses `Xav` and `Evision` (OpenCV bindings) for this.
5.  **Index Creation**: The vector embeddings are stored in an HNSWLib (Hierarchical Navigable Small World) index for efficient similarity search. This index maps the embeddings to their corresponding frame numbers in the video.
6.  **Saving**: The final video file and the search index are saved to disk.

### Retrieval Process

1.  **Search Query**: The user provides a text query.
2.  **Query Embedding**: The query is converted into a vector embedding using the same model as the encoding process.
3.  **Semantic Search**: The HNSWLib index is queried to find the text chunks with embeddings most similar to the query's embedding.
4.  **Frame Identification**: The search results from the index provide the frame numbers where the relevant text chunks are stored.
5.  **Frame Decoding**: The `Retriever` seeks to the specific frames in the video file, reads the QR codes, and decodes them to retrieve the original text chunks.
6.  **Result Aggregation**: The retrieved text chunks are returned to the user.

## Features

*   **Data Archiving**: Store large text corpora in a compressed video format.
*   **Semantic Search**: Go beyond keyword matching with state-of-the-art text embeddings.
*   **Configurable**: Easily configure everything from the video codec and QR code version to the embedding model.
*   **Concurrent**: Utilizes Elixir's concurrency to parallelize embedding and frame decoding tasks.
*   **Extensible**: The `Embedding` behaviour allows for swapping out the embedding implementation.

## Installation

Add `ex_memvid` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_memvid, github: "edlontech/ex_memvid", branch: "main"}
  ]
end
```

You will also need `ffmpeg` installed on your system for some of the underlying video operations.

## Usage Example

Here’s a complete example of how to encode a list of text chunks and then retrieve them via search.

```elixir
# 1. Configuration
config = ExMemvid.Config.validate!(
  embedding: %{
    # Using a mock embedding module for this example
    module: ExMemvid.MockEmbedding,
    dimension: 3
  }
)

# Some text data to store
chunks = [
  "elixir is a functional, concurrent language",
  "phoenix is a popular web framework for elixir",
  "the actor model enables robust, concurrent systems",
  "bumblebee brings hugging face transformers to elixir"
]

# 2. Setup Encoder
{:ok, encoder} = ExMemvid.Encoder.new(config)
encoder = ExMemvid.Encoder.add_chunks(encoder, chunks)

# 3. Define output paths
output_dir = "output"
video_path = Path.join(output_dir, "my_video.mkv")
index_path = Path.join(output_dir, "my_index.json")

# 4. Build the video and search index
{:ok, stats} = ExMemvid.Encoder.build_video(encoder, video_path, index_path)
IO.inspect(stats)

# 5. Start the Retriever GenServer
{:ok, retriever_pid} = ExMemvid.Retriever.start_link(
  video_path: video_path,
  index_path: index_path,
  config: config
)

# 6. Perform a search
query = "What is elixir?"
{:ok, results} = ExMemvid.Retriever.search(retriever_pid, query, 2)

IO.puts("Search results for '#{query}':")
IO.inspect(results)
#=> ["elixir is a functional, concurrent language", "bumblebee brings hugging face transformers to elixir"]
```


