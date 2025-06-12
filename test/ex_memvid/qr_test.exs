defmodule ExMemvid.QrTest do
  use ExUnit.Case, async: true

  alias ExMemvid.Config

  test "encode and decode plain QR code" do
    config = [
      qr: %{
        error_correction: :medium,
        fill_color: "#000000",
        back_color: "#ffffff",
        gzip: false
      }
    ]

    config = Config.validate!(config)

    data = "Hello, ExMemvid!"
    {:ok, encoded} = ExMemvid.QR.encode(data, config)
    assert is_binary(encoded)

    {:ok, decoded} = ExMemvid.QR.decode(encoded, config)
    assert decoded == data
  end

  test "encode and decode gzipped QR code" do
    config = [
      qr: %{
        error_correction: :medium,
        fill_color: "#000000",
        back_color: "#ffffff",
        gzip: true
      }
    ]

    config = Config.validate!(config)

    data = "Hello, ExMemvid!"
    {:ok, encoded} = ExMemvid.QR.encode(data, config)
    assert is_binary(encoded)

    {:ok, decoded} = ExMemvid.QR.decode(encoded, config)
    assert decoded == data
  end
end
