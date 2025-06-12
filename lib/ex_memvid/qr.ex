defmodule ExMemvid.QR do
  @moduledoc """
  Handles QR code generation and decoding for video frame content encoding.

  The `ExMemvid.QR` module provides the core QR code functionality that enables
  text data to be visually encoded into video frames and later decoded back to
  the original content. Each QR code represents a chunk of text data that becomes
  a single frame in the encoded video.

  ## Configuration

  QR code behavior is controlled via configuration:

      config = [
        qr: [
          back_color: {255, 255, 255},     # White background
          fill_color: {0, 0, 0},           # Black foreground  
          error_correction: :medium,        # Error correction level
          gzip: true                       # Enable compression
        ]
      ]

  ## Usage Examples

      # Configure QR settings
      config = [
        qr: [
          back_color: {255, 255, 255},
          fill_color: {0, 0, 0}, 
          error_correction: :medium,
          gzip: true
        ]
      ]

      # Encode text data into QR code PNG
      chunk_data = Jason.encode!(%{id: 1, text: "Hello world", frame: 1})
      {:ok, qr_png_binary} = ExMemvid.QR.encode(chunk_data, config)

      # Decode QR code back to original text
      {:ok, decoded_text} = ExMemvid.QR.decode(qr_png_binary, config)
      {:ok, data} = Jason.decode(decoded_text)
      # data = %{"id" => 1, "text" => "Hello world", "frame" => 1}

  ## Data Flow

  1. **Encoding Path**:
     - Text data → (Optional) Gzip compression → Base64 encoding → QR code → PNG binary

  2. **Decoding Path**:
     - PNG binary → QR detection → Text extraction → (Optional) Base64 decode → Gzip decompress → Original text

  ## Compression Benefits

  When `gzip: true` is enabled:
  - Significantly reduces QR code complexity for repetitive text
  - Allows more data per QR code
  - Essential for maximizing storage density in video frames
  - Automatic compression/decompression is transparent to callers
  """
  alias ExMemvid.Config

  @spec encode(binary(), Config.t()) :: {:ok, binary()} | {:error, term()}
  def encode(data_to_encode, config) do
    png_settings = %QRCode.Render.PngSettings{
      background_color: config[:qr][:back_color],
      qrcode_color: config[:qr][:fill_color]
    }

    processed_data =
      if config[:qr][:gzip] do
        data_to_encode
        |> :zlib.compress()
        |> Base.encode64()
      else
        data_to_encode
      end

    processed_data
    |> QRCode.create(config[:qr][:error_correction])
    |> QRCode.render(:png, png_settings)
  end

  @spec decode(binary(), Config.t()) :: {:ok, String.t()} | {:error, term()}
  def decode(binary_to_decode, config) do
    binary = QRex.detect_qr_codes(binary_to_decode)

    with {:ok, qr_code} <- fetch_qr_code(binary) do
      if config[:qr][:gzip] do
        decode = Base.decode64!(qr_code.text)
        {:ok, :zlib.uncompress(decode)}
      else
        {:ok, qr_code.text}
      end
    end
  end

  defp fetch_qr_code({:ok, [qr_code | _]}), do: qr_code

  defp fetch_qr_code({:ok, []}), do: {:error, :invalid_code}

  defp fetch_qr_code({:error, _} = error), do: error
end
