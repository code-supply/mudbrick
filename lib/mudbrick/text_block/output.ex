defmodule Mudbrick.TextBlock.Output do
  @moduledoc false

  defstruct position: nil,
            font: nil,
            font_size: nil,
            operations: [],
            drawings: []

  alias Mudbrick.ContentStream.{BT, ET}
  alias Mudbrick.ContentStream.Rg
  alias Mudbrick.ContentStream.Td
  alias Mudbrick.ContentStream.Tf
  alias Mudbrick.ContentStream.{TJ, TStar}
  alias Mudbrick.ContentStream.TL
  alias Mudbrick.Path
  alias Mudbrick.TextBlock.Line

  def to_iodata(
        %Mudbrick.TextBlock{
          font: font,
          font_size: font_size,
          position: position
        } = tb
      ) do
    tl = %TL{leading: tb.leading}
    tf = %Tf{font_identifier: font.resource_identifier, size: font_size}

    %__MODULE__{position: position, font: font, font_size: font_size}
    |> end_block()
    |> reduce_lines(
      tb.lines,
      case tb.align do
        :left -> fn _ -> 0 end
        :right -> &Line.width/1
        :centre -> fn line -> Line.width(line) / 2 end
      end
    )
    |> td(position)
    |> add(tl)
    |> add(tf)
    |> start_block()
    |> drawings()
    |> deduplicate(tl)
    |> deduplicate(tf)
    |> Map.update!(:operations, &Enum.reverse/1)
  end

  defp add_part(output, part) do
    output
    |> with_font(
      struct!(TJ,
        auto_kern: part.auto_kern,
        kerned_text: Mudbrick.Font.kerned(output.font, part.text)
      ),
      part
    )
    |> colour(part.colour)
  end

  defp add(%__MODULE__{} = output, op) do
    Map.update!(output, :operations, &[op | &1])
  end

  defp remove(output, operation) do
    Map.update!(output, :operations, &List.delete(&1, operation))
  end

  defp deduplicate(output, initial_operator) do
    Map.update!(output, :operations, fn ops ->
      ops
      |> deduplicate_update(initial_operator)
      |> Enum.reverse()
    end)
  end

  defp deduplicate_update(ops, initial_operator) do
    {_, ops} =
      List.foldl(ops, {initial_operator, []}, fn
        current_operator, {current_operator, acc} ->
          if current_operator in acc do
            {current_operator, acc}
          else
            {current_operator, [current_operator | acc]}
          end

        op, {current_operator, acc} ->
          if op.__struct__ == initial_operator.__struct__ do
            {op, [op | acc]}
          else
            {current_operator, [op | acc]}
          end
      end)

    ops
  end

  defp reduce_lines(output, [line], x_offsetter) do
    output
    |> leading(line)
    |> reset_offset(x_offsetter.(line))
    |> reduce_parts(line, :first_line, x_offsetter.(line))
    |> offset(x_offsetter.(line))
  end

  defp reduce_lines(output, [line | lines], x_offsetter) do
    output
    |> leading(line)
    |> reset_offset(x_offsetter.(line))
    |> reduce_parts(line, nil, x_offsetter.(line))
    |> offset(x_offsetter.(line))
    |> reduce_lines(lines, x_offsetter)
  end

  defp reduce_parts(output, %Line{parts: []}, :first_line, _x_offset) do
    output
  end

  defp reduce_parts(output, %Line{parts: [part]}, :first_line, x_offset) do
    output
    |> add_part(part)
    |> underline(part, x_offset)
  end

  defp reduce_parts(output, %Line{parts: []}, nil, _x_offset) do
    output
    |> add(%TStar{})
  end

  defp reduce_parts(output, %Line{parts: [part]}, nil, x_offset) do
    output
    |> add_part(part)
    |> add(%TStar{})
    |> underline(part, x_offset)
  end

  defp reduce_parts(
         output,
         %Line{parts: [part | parts]} = line,
         line_kind,
         x_offset
       ) do
    output
    |> add_part(part)
    |> underline(part, x_offset)
    |> reduce_parts(%{line | parts: parts}, line_kind, x_offset)
  end

  defp leading(output, line) do
    output
    |> add(%TL{leading: line.leading})
  end

  defp offset(output, offset) do
    td(output, {-offset, 0})
  end

  defp reset_offset(output, offset) do
    td(output, {offset, 0})
  end

  defp underline(output, %Line.Part{underline: nil}, _line_x_offset), do: output

  defp underline(output, part, line_x_offset) do
    Map.update!(output, :drawings, fn drawings ->
      [underline_path(output, part, line_x_offset) | drawings]
    end)
  end

  defp underline_path(output, part, line_x_offset) do
    {initial_x, initial_y} = output.position
    {offset_x, offset_y} = part.left_offset

    x = initial_x + offset_x - line_x_offset
    y = initial_y + offset_y - part.font_size / 10

    Path.new()
    |> Path.move(to: {x, y})
    |> Path.line(Keyword.put(part.underline, :to, {x + Line.Part.width(part), y}))
    |> Path.Output.to_iodata()
  end

  defp drawings(output) do
    Map.update!(output, :operations, fn ops ->
      for drawing <- output.drawings, reduce: ops do
        ops ->
          Enum.reverse(drawing.operations) ++ ops
      end
    end)
  end

  defp td(output, {0, 0}), do: output
  defp td(output, {x, y}), do: add(output, %Td{tx: x, ty: y})

  defp with_font(output, op, part) do
    output
    |> add(%Tf{font_identifier: output.font.resource_identifier, size: output.font_size})
    |> add(op)
    |> add(%Tf{font_identifier: part.font.resource_identifier, size: part.font_size})
  end

  defp colour(output, {r, g, b}) do
    new_colour = Rg.new(r: r, g: g, b: b)
    latest_colour = Enum.find(output.operations, &match?(%Rg{}, &1)) || %Rg{r: 0, g: 0, b: 0}

    if latest_colour == new_colour do
      remove(output, new_colour)
    else
      output
    end
    |> add(new_colour)
  end

  defp start_block(output) do
    add(output, %BT{})
  end

  defp end_block(output) do
    add(output, %ET{})
  end
end
