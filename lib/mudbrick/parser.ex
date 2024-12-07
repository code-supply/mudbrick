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
    |> utf8_string([not: ?\s, not: ?\n], min: 1)
  end

  def number do
    ascii_string([?0..?9], min: 1)
  end

  def pair do
    optional(ignore(whitespace()))
    |> concat(name())
    |> ignore(whitespace())
    |> concat(choice([name(), number()]))
    |> optional(ignore(whitespace()))
    |> tag(:pair)
  end

  def dictionary do
    ignore(string("<<"))
    |> repeat(pair())
    |> ignore(string(">>"))
  end

  def object do
    integer(min: 1)
    |> ignore(whitespace())
    |> integer(min: 1)
    |> ignore(whitespace())
    |> string("obj")
    |> ignore(eol())
    |> concat(optional(dictionary()))
    |> tag(:object)
  end
end

defmodule Mudbrick.Parser do
  import NimbleParsec
  import Mudbrick.Parser.Helpers

  defparsec(:pair, pair())

  defparsec(
    :pdf,
    version()
    |> ignore(ascii_string([not: ?\n], min: 1))
    |> ignore(eol())
    |> concat(object())
  )

  def parse(pdf) do
    {:ok, resp, _, %{}, _, _} =
      pdf
      |> IO.iodata_to_binary()
      |> pdf()

    resp
  end
end
