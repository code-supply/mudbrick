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

  test "can parse objects" do
    parsed = auto_kerning_example() |> Parser.parse()
    assert parsed[:object] == [1, 0, " obj"]
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
