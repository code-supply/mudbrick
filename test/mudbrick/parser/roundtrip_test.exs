defmodule Mudbrick.ParseRoundtripTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Mudbrick
  import Mudbrick.TestHelper

  alias Mudbrick.Parser

  property "documents" do
    check all document_options <- list_of(document_option()), max_runs: 20 do
      input =
        document_options
        |> new()
        |> render()

      parsed =
        input
        |> IO.iodata_to_binary()
        |> Parser.parse()
        |> render()

      assert parsed == input
    end
  end

  property "objects" do
    base_object =
      one_of([
        atom(:alphanumeric),
        boolean(),
        integer(),
        float(min: -999, max: 999),
        string(:alphanumeric)
      ])

    check all input <-
                one_of([
                  base_object,
                  list_of(base_object),
                  list_of(list_of(base_object)),
                  map_of(atom(:alphanumeric), base_object),
                  map_of(atom(:alphanumeric), map_of(atom(:alphanumeric), base_object))
                ]),
              max_runs: 50 do
      assert input
             |> Mudbrick.Object.to_iodata()
             |> Parser.to_mudbrick(:object) == input
    end
  end

  test "with an image" do
    input =
      new(images: %{flower: flower()})
      |> page()
      |> image(
        :flower,
        scale: {100, 100},
        position: {0, 0}
      )
      |> render()

    parsed =
      input
      |> IO.iodata_to_binary()
      |> Parser.parse()
      |> render()

    assert parsed == input
  end

  test "custom page size" do
    input =
      new()
      |> page(size: {400, 100})
      |> render()

    parsed =
      input
      |> IO.iodata_to_binary()
      |> Parser.parse()
      |> render()

    assert parsed == input
  end

  test "with rectangle" do
    input =
      new()
      |> page(size: {100, 100})
      |> path(fn path ->
        Mudbrick.Path.rectangle(path, lower_left: {0, 0}, dimensions: {50, 60})
      end)
      |> render()

    parsed =
      input
      |> IO.iodata_to_binary()
      |> Parser.parse()
      |> render()

    assert parsed == input
  end

  test "with underline" do
    input =
      new(fonts: %{poop: bodoni_bold()})
      |> page(size: {400, 100})
      |> text(
        [{"Warning\n", underline: [width: 0.5]}],
        font: :poop,
        font_size: 70,
        position: {7, 30}
      )
      |> render()

    parsed =
      input
      |> IO.iodata_to_binary()
      |> Parser.parse()
      |> render()

    assert parsed == input
  end

  test "PDF with text" do
    input =
      new(
        fonts: %{
          bodoni: bodoni_regular(),
          franklin: franklin_regular()
        }
      )
      |> page()
      |> text("hello, bodoni", font: :bodoni)
      |> text("hello, franklin", font: :franklin)
      |> render()

    parsed =
      input
      |> IO.iodata_to_binary()
      |> Parser.parse()
      |> render()

    assert parsed == input
  end

  test "PDF with text, compressed" do
    input =
      new(
        compress: true,
        fonts: %{
          bodoni: bodoni_regular(),
          franklin: franklin_regular()
        }
      )
      |> page()
      |> text("hello, bodoni", font: :bodoni)
      |> text("hello, franklin", font: :franklin)
      |> render()

    parsed =
      input
      |> IO.iodata_to_binary()
      |> Parser.parse()
      |> Mudbrick.render()

    assert parsed == input
  end

  defp fonts do
    optional_map(%{
      bodoni_bold: constant(bodoni_bold()),
      bodoni_regular: constant(bodoni_regular()),
      franklin_regular: constant(franklin_regular())
    })
  end

  defp images do
    optional_map(%{
      flower: constant(flower())
    })
  end

  # defp datetime do
  #   gen all i <- integer(0..143_256_036_886_856) do
  #     DateTime.from_unix!(i, 1024)
  #   end
  # end

  defp document_option do
    gen all fonts <- fonts(),
            images <- images(),
            compress <- boolean(),
            # producer <- string(:alphanumeric),
            # creator_tool <- string(:alphanumeric),
            # create_date <- datetime(),
            # modify_date <- datetime(),
            # title <- string(:alphanumeric),
            # creators <- list_of(string(:alphanumeric)),
            option <-
              member_of(
                compress: compress,
                fonts: fonts,
                images: images
                # producer: producer,
                # creator_tool: creator_tool,
                # create_date: create_date,
                # modify_date: modify_date,
                # title: title,
                # creators: creators
              ) do
      option
    end
  end
end
