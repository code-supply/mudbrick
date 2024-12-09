defmodule Mudbrick.Parser.Helpers do
  import NimbleParsec

  def eol, do: string("\n")
  def whitespace, do: ascii_string([?\n, ?\s], min: 1)

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

  def positive_integer do
    ascii_string([?1..?9], min: 1)
    |> repeat(non_negative_integer())
  end

  def indirect_reference do
    positive_integer()
    |> ignore(whitespace())
    |> concat(non_negative_integer())
    |> ignore(whitespace())
    |> string("R")
    |> tag(:indirect_reference)
  end

  def integer do
    choice([
      non_negative_integer(),
      negative_integer()
    ])
    |> tag(:integer)
  end

  def boolean do
    choice([
      string("true") |> replace(true),
      string("false") |> replace(false)
    ])
    |> unwrap_and_tag(:boolean)
  end
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
      indirect_reference(),
      integer(),
      boolean(),
      parsec(:array),
      parsec(:dictionary)
    ])
  )

  defparsec(
    :stream,
    parsec(:dictionary)
    |> ignore(whitespace())
    |> string("stream")
    |> ignore(eol())
    |> post_traverse({:stream_contents, []})
    |> ignore(eol())
    |> ignore(string("endstream"))
  )

  defparsec(
    :indirect_object,
    integer(min: 1)
    |> ignore(whitespace())
    |> integer(min: 1)
    |> ignore(whitespace())
    |> ignore(string("obj"))
    |> ignore(eol())
    |> concat(
      choice([
        boolean(),
        parsec(:stream),
        parsec(:dictionary)
      ])
    )
    |> ignore(eol())
    |> ignore(string("endobj"))
    |> ignore(eol())
    |> tag(:indirect_object)
  )

  def stream_contents(
        rest,
        [
          "stream",
          {:dictionary, pairs}
        ] = results,
        context,
        _line,
        _offset
      ) do
    dictionary = ast_to_mudbrick({:dictionary, pairs})
    bytes_to_read = dictionary[:Length]

    {
      binary_slice(rest, bytes_to_read..-1//1),
      [binary_slice(rest, 0, bytes_to_read) | results],
      context
    }
  end

  defparsec(
    :pdf,
    ignore(version())
    |> ignore(ascii_string([not: ?\n], min: 1))
    |> ignore(eol())
    |> repeat(parsec(:indirect_object))
    |> reduce(:to_pdf)
  )

  defp to_pdf(_root_objects) do
    Mudbrick.new()
  end

  def parse(iodata) do
    {:ok, [parsed], _rest, %{}, _, _} = iodata |> IO.iodata_to_binary() |> pdf()
    parsed
  end

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

  defp ast_to_mudbrick([]), do: []

  defp ast_to_mudbrick([[{:indirect_object, _} | _rest] = unwrapped]) do
    ast_to_mudbrick(unwrapped)
  end

  defp ast_to_mudbrick([
         {:indirect_object,
          [
            ref_number,
            _version,
            {:dictionary, pairs}
          ]}
         | rest
       ]) do
    [
      Mudbrick.Indirect.Ref.new(ref_number)
      |> Mudbrick.Indirect.Object.new(pairs)
      | ast_to_mudbrick(rest)
    ]
  end

  defp ast_to_mudbrick([
         {:indirect_object,
          [
            ref_number,
            _version,
            {:dictionary, _pairs},
            "stream",
            stream
          ]}
         | rest
       ]) do
    [
      Mudbrick.Indirect.Ref.new(ref_number)
      |> Mudbrick.Indirect.Object.new(Mudbrick.Stream.new(data: stream))
      | ast_to_mudbrick(rest)
    ]
  end

  defp ast_to_mudbrick(integer: [n]), do: String.to_integer(n)
  defp ast_to_mudbrick(integer: ["-", n]), do: -String.to_integer(n)
  defp ast_to_mudbrick(name: s), do: String.to_atom(s)
end
