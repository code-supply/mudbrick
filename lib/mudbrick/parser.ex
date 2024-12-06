defmodule Mudbrick.Parser.Helpers do
  import NimbleParsec

  def eol, do: string("\n")

  def version do
    ignore(string("%PDF-"))
    |> integer(1)
    |> ignore(string("."))
    |> integer(1)
    |> ignore(eol())
    |> tag(:version)
  end

  def object_start do
    integer(min: 1)
    |> ignore(string(" "))
    |> integer(min: 1)
    |> string(" obj")
    |> ignore(eol())
    |> tag(:object)
  end
end

defmodule Mudbrick.Parser do
  import NimbleParsec
  import Mudbrick.Parser.Helpers

  defparsec(
    :pdf,
    version()
    |> ignore(ascii_string([not: 10..10], min: 1))
    |> ignore(eol())
    |> concat(object_start())
  )

  def parse(pdf) do
    {:ok, resp, _, %{}, _, _} =
      pdf
      |> IO.iodata_to_binary()
      |> pdf()

    resp
  end
end
