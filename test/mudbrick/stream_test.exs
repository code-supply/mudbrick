defmodule Mudbrick.StreamTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Mudbrick.TestHelper

  property "compresses data when there's a saving" do
    check all uncompressed <- string(:alphanumeric, min_length: 150), max_runs: 200 do
      result =
        Mudbrick.Stream.new(compress: true, data: uncompressed)
        |> Mudbrick.Object.to_iodata()
        |> IO.iodata_to_binary()

      assert result =~ "FlateDecode"
    end
  end

  test "doesn't compress data when there's no saving" do
    uncompressed = "1234567890abcdefghijklmnopqrstuvwxyz"

    result =
      Mudbrick.Stream.new(compress: true, data: uncompressed)
      |> Mudbrick.Object.to_iodata()
      |> IO.iodata_to_binary()

    refute result =~ "FlateDecode"
  end

  test "includes length and stream markers when serialised" do
    serialised =
      Mudbrick.Stream.new(data: bodoni_regular())
      |> Mudbrick.Object.to_iodata()
      |> IO.iodata_to_binary()

    assert String.starts_with?(serialised, """
           <</Length 42952
           >>
           stream\
           """)

    assert String.ends_with?(serialised, """
           endstream\
           """)
  end

  test "includes additional entries merged into the dictionary" do
    assert Mudbrick.Stream.new(data: "yo", additional_entries: %{Hi: :There})
           |> show() ==
             """
             <</Hi /There
               /Length 2
             >>
             stream
             yo
             endstream\
             """
  end
end
