# ExMemvid

[![Hex](https://img.shields.io/hexpm/v/ex_memvid?style=flat-square)](https://hex.pm/packages/ex_memvid)

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
*   **Supervised**: Built-in supervisors for managing encoder and retriever processes.

## Installation

Add `ex_memvid` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_memvid, "~> 0.1.1"}
  ]
end
```

You will also need `ffmpeg` installed on your system for some of the underlying video operations.

## Quick Start

### Basic Usage

```elixir
# 1. Configure with Hugging Face embeddings
config = ExMemvid.Config.validate!([])

# 2. Start the embedding supervisor
{:ok, _} = ExMemvid.Embedding.Supervisor.start_link(config)

# 3. Create and populate an encoder
{:ok, encoder} = ExMemvid.Encoder.new(config)

# Add your text data
texts = [
  "The Elixir programming language is designed for building maintainable and scalable applications.",
  "Phoenix LiveView enables rich, real-time user experiences with server-rendered HTML.",
  "OTP provides battle-tested abstractions for building fault-tolerant systems.",
  "Ecto is a database wrapper and query generator for Elixir.",
  "GenServers are the building blocks of stateful processes in Elixir applications."
]

encoder = ExMemvid.Encoder.add_chunks(encoder, texts)

# 4. Build the video and index
video_path = "knowledge_base.mp4"
index_path = "knowledge_base.hnsw"

{:ok, stats} = ExMemvid.Encoder.build_video(encoder, video_path, index_path)
IO.puts("Encoded #{stats.frame_count} frames into video")

# 5. Search the content
{:ok, retriever} = ExMemvid.Retriever.start_link(video_path, index_path, config)

{:ok, results} = ExMemvid.Retriever.search(retriever, "What is LiveView?", top_k: 2)
Enum.each(results, &IO.puts/1)
```

### Using Supervisors

```elixir
# Start the retriever supervisor
{:ok, _} = ExMemvid.RetrieverSupervisor.start_link([])

# Start multiple retrievers for different video archives
{:ok, docs_retriever} = ExMemvid.RetrieverSupervisor.start_retriever(
  "documentation.mp4",
  "documentation.hnsw",
  config,
  name: :docs_retriever
)

{:ok, blog_retriever} = ExMemvid.RetrieverSupervisor.start_retriever(
  "blog_posts.mp4",
  "blog_posts.hnsw", 
  config,
  name: :blog_retriever
)

# Query different knowledge bases
{:ok, docs} = ExMemvid.Retriever.search(:docs_retriever, "How to use GenServers?")
{:ok, blogs} = ExMemvid.Retriever.search(:blog_retriever, "Real-world Elixir stories")

# Check active retrievers
ExMemvid.RetrieverSupervisor.count_retrievers()
#=> 2

# Get info about a specific retriever
{:ok, info} = ExMemvid.RetrieverSupervisor.get_retriever_info(:docs_retriever)
#=> %{video_path: "documentation.mp4", cache_size: 5, ...}
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Original Python implementation: [Memvid](https://github.com/Olow304/memvid)
- Powered by [Bumblebee](https://github.com/elixir-nx/bumblebee) for ML models
- Video processing with [Xav](https://github.com/kim-company/xav)
- QR code handling via [Evision](https://github.com/cocoa-xu/evision)
