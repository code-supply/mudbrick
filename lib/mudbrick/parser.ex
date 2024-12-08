defmodule Mudbrick.Parser.Helpers do
  import NimbleParsec

  defmodule Convert do
    def to_indirect_object([ref_number, _version, contents]) do
      ref_number
      |> Mudbrick.Indirect.Ref.new()
      |> Mudbrick.Indirect.Object.new(contents)
    end

    def to_indirect_object([ref_number, _version, %{} = dict, "stream", data]) do
      ref_number
      |> Mudbrick.Indirect.Ref.new()
      |> Mudbrick.Indirect.Object.new(
        Mudbrick.Stream.new(
          data: data,
          additional_entries: Map.drop(dict, [:Length])
        )
      )
    end
  end

  def eol, do: string("\n")
  def whitespace, do: ascii_string([?\n, ?\s], min: 1)

  # def pdf do
  #   ignore(version())
  #   |> ignore(ascii_string([not: ?\n], min: 1))
  #   |> ignore(eol())
  #   |> concat(indirect_object())
  # end

  def version do
    ignore(string("%PDF-"))
    |> integer(1)
    |> ignore(string("."))
    |> integer(1)
    |> ignore(eol())
    |> tag(:version)
  end

  def name do
    ignore(string("/"))
    |> utf8_string(
      [
        not: ?\s,
        not: ?\n,
        not: ?],
        not: ?[,
        not: ?/,
        not: ?<,
        not: ?>
      ],
      min: 1
    )
    |> unwrap_and_tag(:name)
  end

  def non_negative_integer do
    ascii_string([?0..?9], min: 1)
  end

  def negative_integer do
    string("-")
    |> concat(non_negative_integer())
  end

  def integer do
    choice([
      non_negative_integer(),
      negative_integer()
    ])
    |> tag(:integer)
  end

  # def stream do
  #   dictionary()
  #   |> ignore(whitespace())
  #   |> string("stream")
  #   |> ignore(eol())
  #   |> post_traverse({:stream_contents, []})
  #   |> ignore(eol())
  #   |> ignore(string("endstream"))
  # end

  def stream_contents(
        rest,
        ["stream", %{Length: bytes_to_read}] = results,
        context,
        _line,
        _offset
      ) do
    {
      binary_slice(rest, bytes_to_read..-1//1),
      [binary_slice(rest, 0, bytes_to_read) | results],
      context
    }
  end

  def boolean do
    choice([
      string("true") |> replace(true),
      string("false") |> replace(false)
    ])
    |> unwrap_and_tag(:boolean)
  end

  # def indirect_object do
  #   integer(min: 1)
  #   |> ignore(whitespace())
  #   |> integer(min: 1)
  #   |> ignore(whitespace())
  #   |> ignore(string("obj"))
  #   |> ignore(eol())
  #   |> concat(
  #     choice([
  #       boolean(),
  #       stream()
  #     ])
  #   )
  #   |> ignore(eol())
  #   |> ignore(string("endobj"))
  #   |> reduce({Convert, :to_indirect_object, []})
  # end
end

defmodule Mudbrick.Parser do
  import NimbleParsec
  import Mudbrick.Parser.Helpers

  defparsec(:boolean, boolean())

  defparsec(
    :array,
    ignore(ascii_char([?[]))
    |> repeat(
      optional(ignore(whitespace()))
      |> parsec(:object)
      |> optional(ignore(whitespace()))
    )
    |> ignore(ascii_char([?]]))
    |> tag(:array)
  )

  defparsec(
    :dictionary,
    ignore(string("<<"))
    |> repeat(
      optional(ignore(whitespace()))
      |> concat(name())
      |> ignore(whitespace())
      |> parsec(:object)
      |> tag(:pair)
    )
    |> optional(ignore(whitespace()))
    |> ignore(string(">>"))
    |> tag(:dictionary)
  )

  defparsec(
    :object,
    choice([
      name(),
      integer(),
      boolean(),
      parsec(:array),
      parsec(:dictionary)
    ])
  )

  def parse(iodata, f) do
    case iodata
         |> IO.iodata_to_binary()
         |> then(&apply(__MODULE__, f, [&1])) do
      {:ok, resp, _, %{}, _, _} -> resp
    end
  end

  def to_mudbrick(iodata, f), do: iodata |> parse(f) |> ast_to_mudbrick()

  defp ast_to_mudbrick(x) when is_tuple(x), do: ast_to_mudbrick([x])
  defp ast_to_mudbrick(array: a), do: Enum.map(a, &ast_to_mudbrick/1)
  defp ast_to_mudbrick(boolean: b), do: b
  defp ast_to_mudbrick(dictionary: []), do: %{}

  defp ast_to_mudbrick(dictionary: pairs) do
    for {:pair, [k, v]} <- pairs, into: %{} do
      {ast_to_mudbrick(k), ast_to_mudbrick(v)}
    end
  end

  defp ast_to_mudbrick(integer: [n]), do: String.to_integer(n)
  defp ast_to_mudbrick(integer: ["-", n]), do: -String.to_integer(n)
  defp ast_to_mudbrick(name: s), do: String.to_atom(s)
end
