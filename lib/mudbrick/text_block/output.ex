defmodule Mudbrick.TextBlock.Output do
  @moduledoc false

  defstruct font: nil, operations: []

  alias Mudbrick.ContentStream.{BT, ET}
  alias Mudbrick.ContentStream.Rg
  alias Mudbrick.ContentStream.Td
  alias Mudbrick.ContentStream.Tf
  alias Mudbrick.ContentStream.{Apostrophe, Tj}
  alias Mudbrick.ContentStream.TL
  alias Mudbrick.Font
  alias Mudbrick.TextBlock.Line

  defmodule LeftAlign do
    @moduledoc false

    alias Mudbrick.TextBlock.Output

    def reduce_lines(output, [line]) do
      reduce_parts(output, line, Tj, :first_line)
    end

    def reduce_lines(output, [line | lines]) do
      output
      |> reduce_parts(line, Tj, nil)
      |> reduce_lines(lines)
    end

    # first line, first part
    defp reduce_parts(output, %Line{parts: [part]}, _operator, :first_line) do
      add_part(output, part, Tj)
    end

    # subsequent line, first part
    defp reduce_parts(output, %Line{parts: [part]}, _operator, nil) do
      add_part(output, part, Apostrophe)
    end

    defp reduce_parts(output, %Line{parts: [part | parts]} = line, operator, line_kind) do
      output
      |> add_part(part, operator)
      |> reduce_parts(%{line | parts: parts}, Tj, line_kind)
    end

    def add_part(output, part, operator) do
      output
      |> Output.add(struct!(operator, font: output.font, text: part.text))
      |> Output.colour(part.colour)
    end
  end

  defmodule RightAlign do
    @moduledoc false

    alias Mudbrick.TextBlock.Output

    defp text(line) do
      Enum.map_join(line.parts, "", & &1.text)
    end

    def reduce_lines(output, [line], measure) do
      output
      |> Output.end_block()
      |> reduce_parts(line)
      |> measure.(text(line), 1)
      |> Output.start_block()
    end

    def reduce_lines(output, [line | lines], measure) do
      output
      |> Output.end_block()
      |> reduce_parts(line)
      |> measure.(text(line), length(lines) + 1)
      |> Output.start_block()
      |> reduce_lines(lines, measure)
    end

    defp reduce_parts(output, %Line{parts: [part]}) do
      add_part(output, part)
    end

    defp reduce_parts(output, %Line{parts: [part | parts]} = line) do
      output
      |> add_part(part)
      |> reduce_parts(%{line | parts: parts})
    end

    def add_part(output, part) do
      output
      |> Output.add(%Tj{font: output.font, text: part.text})
      |> Output.colour(part.colour)
    end
  end

  def from(
        %Mudbrick.TextBlock{
          align: :left,
          font: font,
          font_size: font_size,
          position: {x, y}
        } = tb
      ) do
    output =
      %__MODULE__{font: font}
      |> end_block()
      |> LeftAlign.reduce_lines(tb.lines)
      |> add(%Td{tx: x, ty: y})
      |> add(%TL{leading: leading(tb)})
      |> add(%Tf{font: font, size: font_size})
      |> start_block()

    output.operations
  end

  def from(
        %Mudbrick.TextBlock{
          align: :right,
          font: font,
          font_size: font_size,
          position: {x, y}
        } = tb
      ) do
    output =
      %__MODULE__{font: font}
      |> RightAlign.reduce_lines(tb.lines, fn output, text, line ->
        right_offset(output, tb, text, line)
      end)
      |> add(%Td{tx: x, ty: y})
      |> add(%TL{leading: leading(tb)})
      |> add(%Tf{font: font, size: font_size})
      |> start_block()

    output.operations
  end

  def add(%__MODULE__{} = output, op) do
    Map.update!(output, :operations, &[op | &1])
  end

  def colour(output, {r, g, b}) do
    new_colour = Rg.new(r: r, g: g, b: b)
    latest_colour = Enum.find(output.operations, &match?(%Rg{}, &1)) || %Rg{r: 0, g: 0, b: 0}

    if latest_colour == new_colour do
      remove(output, new_colour)
    else
      output
    end
    |> add(new_colour)
  end

  def start_block(output) do
    add(output, %BT{})
  end

  def end_block(output) do
    add(output, %ET{})
  end

  def right_offset(output, tb, text, line) do
    n = line - 1
    {x, y} = tb.position

    add(output, %Td{
      tx: x - Font.width(tb.font, tb.font_size, text),
      ty: y - leading(tb) * n
    })
  end

  defp remove(output, operation) do
    Map.update!(output, :operations, &List.delete(&1, operation))
  end

  defp leading(tb) do
    tb.leading || tb.font_size * 1.2
  end
end
