defmodule Mudbrick.ParserTest do
  use ExUnit.Case, async: true

  import Mudbrick.TestHelper

  alias Mudbrick.Indirect
  alias Mudbrick.Parser

  describe "indirect objects" do
    test "roundtrip" do
      input =
        123
        |> Indirect.Ref.new()
        |> Indirect.Object.new(true)

      assert input
             |> Mudbrick.Object.to_iodata()
             |> IO.iodata_to_binary()
             |> Parser.parse(:indirect_object) == input
    end
  end

  describe "full PDF" do
    test "version is parsed" do
      parsed = Parser.parse(auto_kerning_example())
      assert parsed[:version] == [2, 0]
    end

    test "streams are parsed" do
      parsed = auto_kerning_example() |> Parser.parse()

      assert [
               %Indirect.Object{
                 ref: %Indirect.Ref{number: 1},
                 value: %Mudbrick.Stream{
                   compress: false,
                   data: _data,
                   additional_entries: %{Length1: 39860, Subtype: :OpenType},
                   length: 39860,
                   filters: []
                 }
               }
             ] = Enum.filter(parsed, &match?(%Indirect.Object{}, &1))
    end
  end

  defp auto_kerning_example() do
    Mudbrick.new(fonts: %{bodoni: bodoni_bold()})
    |> Mudbrick.page(size: {600, 200})
    |> Mudbrick.text(
      [
        {"Warning\\n", underline: [width: 0.5]},
        "MORE ",
        {"efficiency", underline: [width: 0.5]}
      ],
      font: :bodoni,
      font_size: 70,
      position: {7, 130}
    )
    |> Mudbrick.render()
  end
end
