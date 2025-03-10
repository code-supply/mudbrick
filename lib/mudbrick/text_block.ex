defmodule Mudbrick.TextBlock do
  @type alignment :: :left | :right

  @type underline_option ::
          {:width, number()}
          | {:colour, Mudbrick.colour()}
  @type underline_options :: [underline_option()]

  @type option ::
          {:align, alignment()}
          | {:auto_kern, boolean()}
          | {:colour, Mudbrick.colour()}
          | {:font, atom()}
          | {:font_size, number()}
          | {:leading, number()}
          | {:position, Mudbrick.coords()}

  @type options :: [option()]

  @type part_option ::
          {:colour, Mudbrick.colour()}
          | {:font, atom()}
          | {:font_size, number()}
          | {:leading, number()}
          | {:underline, underline_options()}

  @type part_options :: [part_option()]

  @type write_tuple :: {String.t(), part_options()}
  @type write_part :: String.t() | write_tuple()

  @type write ::
          write_part()
          | list(write_part())

  @type t :: %__MODULE__{
          align: alignment(),
          colour: Mudbrick.colour(),
          font: Mudbrick.Font.t(),
          font_size: number(),
          lines: list(),
          position: Mudbrick.coords(),
          leading: number()
        }

  defstruct align: :left,
            auto_kern: true,
            colour: {0, 0, 0},
            font: nil,
            font_size: 12,
            leading: nil,
            lines: [],
            position: {0, 0}

  alias Mudbrick.TextBlock.Line

  @doc false
  @spec new(options()) :: t()
  def new(opts \\ []) do
    block = struct!(__MODULE__, opts)

    Map.update!(block, :leading, fn
      nil ->
        block.font_size * 1.2

      leading ->
        leading
    end)
  end

  @doc false
  @spec write(t(), String.t(), options()) :: t()
  def write(tb, text, opts \\ []) do
    tb
    |> write_lines(text, opts)
    |> assign_offsets()
  end

  defp assign_offsets(tb) do
    {_, lines} =
      for line <- Enum.reverse(tb.lines), reduce: {0.0, []} do
        {y, lines} ->
          {y - line.leading,
           [
             %{
               line
               | parts:
                   (
                     {_, parts} =
                       for part <- Enum.reverse(line.parts), reduce: {0.0, []} do
                         {x, parts} ->
                           width = Line.Part.width(part)
                           {x + width, [%{part | left_offset: {x, y}} | parts]}
                       end

                     parts
                   )
             }
             | lines
           ]}
      end

    %{tb | lines: lines}
  end

  defp write_lines(tb, text, chosen_opts) do
    line_texts = String.split(text, "\n")

    text_block_opts = [
      auto_kern: tb.auto_kern,
      colour: tb.colour,
      font_size: tb.font_size,
      font: tb.font,
      leading: tb.leading
    ]

    merged_opts =
      Keyword.merge(
        text_block_opts,
        chosen_opts,
        &prefer_lhs_over_nil/3
      )

    Map.update!(tb, :lines, fn
      [] ->
        add_texts([], line_texts, merged_opts, text_block_opts)

      existing_lines ->
        case line_texts do
          # \n at beginning of new line
          ["" | new_line_texts] ->
            existing_lines
            |> add_texts(new_line_texts, merged_opts, text_block_opts)

          # didn't start with \n, so first part belongs to previous line
          [first_new_line_text | new_line_texts] ->
            existing_lines
            # Update previous line with chosen opts, to allow logic around
            # choices.
            |> update_previous_line(first_new_line_text, merged_opts, chosen_opts)
            |> add_texts(new_line_texts, merged_opts, text_block_opts)
        end
    end)
  end

  defp update_previous_line(
         [previous_line | existing_lines],
         first_new_line_text,
         merged_opts,
         opts
       ) do
    [
      Line.append(previous_line, first_new_line_text, merged_opts, opts)
      | existing_lines
    ]
  end

  defp add_texts(existing_lines, new_line_texts, opts, opts_for_empty_lines) do
    for text <- new_line_texts, reduce: existing_lines do
      acc ->
        if text == "" do
          [Line.wrap(text, opts_for_empty_lines) | acc]
        else
          [Line.wrap(text, opts) | acc]
        end
    end
  end

  defp prefer_lhs_over_nil(_key, lhs, nil) do
    lhs
  end

  defp prefer_lhs_over_nil(_key, _lhs, rhs) do
    rhs
  end
end
