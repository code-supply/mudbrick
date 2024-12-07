defmodule Mudbrick.ParserTest do
  use ExUnit.Case, async: true

  import Mudbrick.TestHelper

  alias Mudbrick.Parser

  test "can parse version" do
    parsed =
      auto_kerning_example()
      |> Parser.parse()

    assert parsed[:version] == [2, 0]
  end

  test "pair" do
    assert {:ok, [pair: ["Foo", "Bar"]], _, %{}, _, _} =
             Parser.pair("/Foo /Bar")

    assert {:ok, [pair: ["Foo", "Bar"]], _, %{}, _, _} =
             Parser.pair(" /Foo /Bar")

    assert {:ok, [pair: ["Foo", "Bar"]], _, %{}, _, _} =
             Parser.pair("/Foo    /Bar")

    assert {:ok, [pair: ["Foo", "Bar"]], _, %{}, _, _} =
             Parser.pair("  /Foo    /Bar  ")
  end

  describe "objects" do
    test "parse" do
      parsed = auto_kerning_example() |> Parser.parse()

      assert [
               version: [2, 0],
               object: [
                 1,
                 0,
                 "obj",
                 {:pair, ["Subtype", "OpenType"]},
                 {:pair, ["Length", "39860"]},
                 {:pair, ["Length1", "39860"]}
               ]
             ] = parsed
    end

    test "parse with multiple spaces separating version and revision etc." do
      parsed =
        """
        %PDF-2.0
        %ï¿½ï¿½ï¿½ï¿½
        1    099       obj
        endobj
        """
        |> Parser.parse()

      assert parsed[:object] == [1, 99, "obj"]
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
