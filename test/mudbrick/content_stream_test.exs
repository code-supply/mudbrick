defmodule Mudbrick.ContentStreamTest do
  use ExUnit.Case, async: true

  import Mudbrick

  alias Mudbrick.ContentStream.Tj
  alias Mudbrick.Font
  alias Mudbrick.Indirect
  alias Mudbrick.Object

  @font_data System.fetch_env!("FONT_LIBRE_BODONI_REGULAR") |> File.read!()

  test "built-in font linebreaks are converted to the ' operator" do
    {_doc, content_stream} =
      new()
      |> page(
        size: :letter,
        fonts: %{
          helvetica: [
            name: :Helvetica,
            type: :TrueType,
            encoding: :PDFDocEncoding
          ]
        }
      )
      |> contents()
      |> font(:helvetica, size: 10)
      |> text_position(0, 700)
      |> text("""
      a
      b\
      """)

    assert content_stream.value.operations
           |> render(2) ==
             """
             (a) Tj
             (b) '\
             """
  end

  test "CID font linebreaks are converted to the ' operator" do
    {_doc, content_stream} =
      new()
      |> page(
        size: :letter,
        fonts: %{bodoni: [file: @font_data]}
      )
      |> contents()
      |> font(:bodoni, size: 10)
      |> text_position(0, 700)
      |> text("""
      a
      b\
      """)

    assert content_stream.value.operations
           |> render(2) ==
             """
             <00A5> Tj
             <00B4> '\
             """
  end

  test "font is assigned to the operator struct when font descendant present" do
    {_doc, content_stream} =
      new()
      |> page(
        size: :letter,
        fonts: %{bodoni: [file: @font_data]}
      )
      |> contents()
      |> font(:bodoni, size: 24)
      |> text_position(0, 700)
      |> text("CO₂")

    [show_text_operation | _] = content_stream.value.operations

    assert %Tj{
             text: "CO₂",
             font: %Font{
               name: :"LibreBodoni-Regular",
               descendant: %Indirect.Object{value: %Font.CIDFont{}}
             }
           } = show_text_operation
  end

  describe "serialisation" do
    test "converts Tj text to the assigned font's glyph IDs in hex" do
      {_doc, content_stream} =
        new()
        |> page(
          size: :letter,
          fonts: %{bodoni: [file: @font_data]}
        )
        |> contents()
        |> font(:bodoni, size: 24)
        |> text_position(0, 700)
        |> text("CO₂")

      assert content_stream.value.operations
             |> render(1) ==
               """
               <001100550174> Tj\
               """
    end
  end

  defp render(ops, n) do
    ops
    |> Enum.take(n)
    |> Enum.reverse()
    |> Enum.map_join("\n", fn op ->
      Object.from(op) |> to_string()
    end)
  end
end
