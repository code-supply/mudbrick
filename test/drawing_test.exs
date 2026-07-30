defmodule Mudbrick.DrawingTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Mudbrick.Path

  alias Mudbrick.Path.{
    Line,
    Move,
    Output,
    Rectangle
  }

  alias Mudbrick.TestHelper

  import Mudbrick.TestHelper,
    only: [
      invalid_colour: 0
    ]

  test "can add drawings to a page" do
    import Mudbrick

    assert [
             "q",
             "0 0 m",
             "1 0 0 RG",
             "1 w",
             "50 60 l",
             "S",
             "0 0 0 RG",
             "1 w",
             "0 0 50 60 re",
             "S",
             "Q"
           ] =
             new()
             |> page()
             |> path(fn path ->
               path
               |> Path.move(to: {0, 0})
               |> Path.line(to: {50, 60}, colour: {1, 0, 0})
               |> Path.rectangle(lower_left: {0, 0}, dimensions: {50, 60})
             end)
             |> Mudbrick.TestHelper.output()
             |> Mudbrick.TestHelper.operations()
  end

  test "a fill colour paints the rectangle's interior" do
    import Mudbrick

    assert [
             "q",
             "0 0.5 1 rg",
             "10 10 40 20 re",
             "f",
             "Q"
           ] =
             new()
             |> page()
             |> path(fn path ->
               Path.rectangle(path,
                 lower_left: {10, 10},
                 dimensions: {40, 20},
                 fill: {0, 0.5, 1}
               )
             end)
             |> Mudbrick.TestHelper.output()
             |> Mudbrick.TestHelper.operations()
  end

  test "a fill and an outline colour together fill and stroke in one operation" do
    import Mudbrick

    assert [
             "q",
             "1 1 0 rg",
             "0 0 0 RG",
             "2 w",
             "10 10 40 20 re",
             "B",
             "Q"
           ] =
             new()
             |> page()
             |> path(fn path ->
               Path.rectangle(path,
                 lower_left: {10, 10},
                 dimensions: {40, 20},
                 fill: {1, 1, 0},
                 colour: {0, 0, 0},
                 stroke: true,
                 line_width: 2
               )
             end)
             |> Mudbrick.TestHelper.output()
             |> Mudbrick.TestHelper.operations()
  end

  test "without a fill colour a rectangle is still stroked only" do
    import Mudbrick

    ops =
      new()
      |> page()
      |> path(fn path ->
        Path.rectangle(path, lower_left: {0, 0}, dimensions: {50, 60})
      end)
      |> Mudbrick.TestHelper.output()
      |> Mudbrick.TestHelper.operations()

    assert "S" in ops
    refute "f" in ops
  end

  test "many filled rectangles compose, as a QR code or a bar chart would" do
    import Mudbrick

    ops =
      new()
      |> page()
      |> path(fn path ->
        for i <- 0..9, reduce: path do
          acc ->
            Path.rectangle(acc,
              lower_left: {i * 4, 0},
              dimensions: {3, 3},
              fill: {0, 0, 0}
            )
        end
      end)
      |> Mudbrick.TestHelper.output()
      |> Mudbrick.TestHelper.operations()

    assert Enum.count(ops, &(&1 == "f")) == 10
  end

  test "can construct a rectangle" do
    import Path

    path =
      new()
      |> rectangle(lower_left: {0, 0}, dimensions: {50, 75})

    assert path.sub_paths == [
             Rectangle.new(
               lower_left: {0, 0},
               dimensions: {50, 75},
               line_width: 1
             )
           ]
  end

  test "can construct a path with one straight line" do
    import Path

    path =
      new()
      |> move(to: {50, 50})
      |> line(to: {50, 50})

    assert path.sub_paths == [
             Line.new(to: {50, 50}, width: 1),
             Move.new(to: {50, 50})
           ]
  end

  test "can make an empty path" do
    import Path

    assert [] =
             operations(fn ->
               new()
             end)
  end

  test "can render a rectangle" do
    import Path

    assert [
             "q",
             "0 0 0 RG",
             "1 w",
             "0 0 50 75 re",
             "S",
             "Q"
           ] =
             operations(fn ->
               new()
               |> rectangle(lower_left: {0, 0}, dimensions: {50, 75})
             end)
  end

  test "can draw one path" do
    import Path

    assert [
             "q",
             "0 650 m",
             "0 0 0 RG",
             "1 w",
             "460 750 l",
             "S",
             "Q"
           ] =
             operations(fn ->
               new()
               |> move(to: {0, 650})
               |> line(to: {460, 750})
             end)
  end

  test "can choose line width" do
    import Path

    assert [
             "q",
             "0 650 m",
             "0 0 0 RG",
             "4.0 w",
             "460 750 l",
             "S",
             "Q"
           ] =
             operations(fn ->
               new()
               |> move(to: {0, 650})
               |> line(to: {460, 750}, width: 4.0)
             end)
  end

  test "can choose colour" do
    import Path

    assert [
             "q",
             "0 650 m",
             "0 1 0 RG",
             "1 w",
             "460 750 l",
             "S",
             "Q"
           ] =
             operations(fn ->
               new()
               |> move(to: {0, 650})
               |> line(to: {460, 750}, colour: {0, 1, 0})
             end)
  end

  property "it's an error to set a colour above 1" do
    import Path

    check all colour <- invalid_colour() do
      e =
        assert_raise(Mudbrick.ContentStream.InvalidColour, fn ->
          new()
          |> move(to: {0, 0})
          |> line(to: {100, 0}, colour: colour)
          |> Output.to_iodata()
        end)

      assert e.message == "tuple must be made of floats or integers between 0 and 1"
    end
  end

  defp operations(f) do
    TestHelper.wrapped_output(fn _ -> f.() end, Mudbrick.Path.Output)
    |> Enum.map(&Mudbrick.TestHelper.show/1)
    |> Enum.reverse()
  end
end
