defmodule Mudbrick.Parser.Helpers do
  import NimbleParsec

  def eol, do: string("\n")
  def whitespace, do: ascii_string([?\n, ?\s], min: 1)

  def pdf do
    version()
    |> ignore(ascii_string([not: ?\n], min: 1))
    |> ignore(eol())
    |> concat(object())
  end

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
    |> utf8_string([not: ?\s, not: ?\n], min: 1)
    |> map({String, :to_existing_atom, []})
  end

  def integer do
    ascii_string([?0..?9], min: 1)
    |> map({String, :to_integer, []})
  end

  def pair do
    optional(ignore(whitespace()))
    |> concat(name())
    |> ignore(whitespace())
    |> concat(choice([name(), integer()]))
    |> optional(ignore(whitespace()))
  end

  def dictionary do
    ignore(string("<<"))
    |> repeat(pair())
    |> ignore(string(">>"))
    |> reduce({:dictionary_to_map, []})
  end

  def dictionary_to_map(dict) do
    dict
    |> Enum.chunk_every(2)
    |> Enum.map(&List.to_tuple/1)
    |> Map.new()
  end

  def stream do
    dictionary()
    |> ignore(whitespace())
    |> string("stream")
    |> ignore(eol())
    |> post_traverse({:stream_contents, []})
    |> ignore(eol())
    |> ignore(string("endstream"))
  end

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

  def object do
    integer(min: 1)
    |> ignore(whitespace())
    |> integer(min: 1)
    |> ignore(whitespace())
    |> string("obj")
    |> ignore(eol())
    |> concat(optional(stream()))
    |> tag(:object)
  end
end

defmodule Mudbrick.Parser do
  import NimbleParsec
  import Mudbrick.Parser.Helpers

  defparsec(:pdf, pdf())

  def parse(pdf) do
    {:ok, resp, _, %{}, _, _} =
      pdf
      |> IO.iodata_to_binary()
      |> pdf()

    resp
  end
end
