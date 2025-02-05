defmodule Mudbrick.Parser do
  @moduledoc """
  Parse documents generated with Mudbrick back into Elixir. Useful for testing.

  Eventually this module may support documents generated with other PDF processors.
  """

  import Mudbrick.Parser.AST
  import Mudbrick.Parser.Helpers
  import NimbleParsec

  alias Mudbrick.ContentStream.{
    Tf,
    TJ
  }

  defmodule Error do
    defexception [:message]
  end

  @doc """
  Parse Mudbrick-generated `iodata` into a `Mudbrick.Document`.

  ## Minimal round-trip

      iex> doc = Mudbrick.new()
      ...> doc
      ...> |> Mudbrick.render()
      ...> |> Mudbrick.Parser.parse()
      doc
  """
  @spec parse(iodata()) :: Mudbrick.Document.t()
  def parse(iodata) do
    input = IO.iodata_to_binary(iodata)

    case pdf(input) do
      {:error, msg, rest, %{}, _things, _bytes} ->
        raise Error, "#{msg}\n#{rest}"

      {:ok, parsed_items, _rest, %{}, _, _} ->
        items = Enum.flat_map(parsed_items, &to_mudbrick/1)

        page_refs = page_refs(items)
        font_files = Enum.filter(items, &font?/1)
        image_files = Enum.filter(items, &image?/1)
        fonts = decompressed_resources_option(font_files, "F")
        images = decompressed_resources_option(image_files, "I")
        compress? = Enum.any?(items, &match?(%{value: %{compress: true}}, &1))

        opts =
          [compress: compress?] ++
            case Enum.find(items, &metadata?/1) do
              nil ->
                []

              metadata ->
                xml =
                  if metadata.value.compress do
                    Mudbrick.decompress(metadata.value.data)
                  else
                    metadata.value.data
                  end

                metadata(xml)
            end

        opts = if map_size(fonts) > 0, do: Keyword.put(opts, :fonts, fonts), else: opts
        opts = if map_size(images) > 0, do: Keyword.put(opts, :images, images), else: opts

        for page <- all(items, page_refs), reduce: Mudbrick.new(opts) do
          acc ->
            [_, _, w, h] = page.value[:MediaBox]

            Mudbrick.page(acc, size: {w, h})
            |> Mudbrick.ContentStream.update_operations(fn ops ->
              operations(items, page) ++ ops
            end)
        end
        |> Mudbrick.Document.finish()
    end
  end

  @doc """
  Parse a section of a Mudbrick-generated PDF with a named parsing function.
  Mostly useful for debugging this parser.
  """
  @spec parse(iodata(), atom()) :: term()
  def parse(iodata, f) do
    case iodata
         |> IO.iodata_to_binary()
         |> then(&apply(__MODULE__, f, [&1])) do
      {:ok, resp, _, %{}, _, _} -> resp
    end
  end

  @doc """
  Extract text content from a Mudbrick-generated PDF. Will map glyphs back to
  their original characters.

  ## With compression

      iex> import Mudbrick.TestHelper
      ...> import Mudbrick
      ...> new(compress: true, fonts: %{bodoni: bodoni_regular(), franklin: franklin_regular()})
      ...> |> page()
      ...> |> text({"hello, world!", underline: [width: 1]}, font: :bodoni)
      ...> |> text("hello in another font", font: :franklin)
      ...> |> Mudbrick.render()
      ...> |> Mudbrick.Parser.extract_text()
      [ "hello, world!", "hello in another font" ]

  ## Without compression

      iex> import Mudbrick.TestHelper
      ...> import Mudbrick
      ...> new(fonts: %{bodoni: bodoni_regular(), franklin: franklin_regular()})
      ...> |> page()
      ...> |> text({"hello, world!", underline: [width: 1]}, font: :bodoni)
      ...> |> text("hello in another font", font: :franklin)
      ...> |> Mudbrick.render()
      ...> |> Mudbrick.Parser.extract_text()
      [ "hello, world!", "hello in another font" ]

  """
  @spec extract_text(iodata()) :: [String.t()]
  def extract_text(iodata) do
    alias Mudbrick.ContentStream.{Tf, TJ}

    doc = parse(iodata)

    content_stream =
      Mudbrick.Document.find_object(doc, &match?(%Mudbrick.ContentStream{}, &1))

    page_tree = Mudbrick.Document.root_page_tree(doc)
    fonts = page_tree.value.fonts

    {text_items, _last_found_font} =
      content_stream.value.operations
      |> List.foldr({[], nil}, fn
        %Tf{font_identifier: font_identifier}, {text_items, _current_font} ->
          {text_items, Map.fetch!(fonts, font_identifier).value.parsed}

        %TJ{kerned_text: kerned_text}, {text_items, current_font} ->
          text =
            kerned_text
            |> Enum.map(fn
              {hex_glyph, _kern} -> hex_glyph
              hex_glyph -> hex_glyph
            end)
            |> Enum.map(fn hex_glyph ->
              {decimal_glyph, _} = Integer.parse(hex_glyph, 16)
              Map.fetch!(current_font.gid2cid, decimal_glyph)
            end)
            |> to_string()

          {[text | text_items], current_font}

        _operation, {text_items, current_font} ->
          {text_items, current_font}
      end)

    Enum.reverse(text_items)
  end

  def metadata(xml_iodata) do
    {doc, _rest} =
      xml_iodata
      |> IO.iodata_to_binary()
      |> String.replace(~r/^<\?xpacket.*\?>\n/, "")
      |> String.to_charlist()
      |> :xmerl_scan.string()

    [
      create_date: extract_metadata_field(doc, "xmp:CreateDate"),
      creator_tool: extract_metadata_field(doc, "xmp:CreatorTool"),
      creators: creators(doc),
      modify_date: extract_metadata_field(doc, "xmp:ModifyDate"),
      producer: extract_metadata_field(doc, "pdf:Producer"),
      title: extract_metadata_field(doc, "dc:title/rdf:Alt/rdf:li")
    ]
  end

  defp creators(doc) do
    :xmerl_xpath.string(~c"//dc:creator//rdf:li", doc)
    |> Enum.map(fn
      {:xmlElement, :"rdf:li", :"rdf:li", {~c"rdf", ~c"li"}, _ns, _attributes, _n, [], [], [],
       _path, :undeclared} ->
        ""

      {:xmlElement, :"rdf:li", :"rdf:li", {~c"rdf", ~c"li"}, _ns, _attributes, _n, [],
       [
         {:xmlText, _more_attributes, _1, [], text, :text}
       ], [], _path, :undeclared} ->
        text |> to_string() |> String.trim()
    end)
  end

  defp extract_metadata_field(doc, field) when field in ~w(xmp:CreateDate xmp:ModifyDate) do
    case extract_meta(doc, field)
         |> DateTime.from_iso8601() do
      {:ok, datetime, _offset} -> datetime
      {:error, _} -> ""
    end
  end

  defp extract_metadata_field(doc, field) do
    extract_meta(doc, field)
  end

  defp extract_meta(doc, field) do
    :xmerl_xpath.string(~c"//#{field}/text()", doc) |> extract_meta_text()
  end

  defp extract_meta_text([]), do: ""

  defp extract_meta_text([{:xmlText, _attributes, 1, [], text, :text}]),
    do: text |> to_string() |> String.trim()

  defp extract_meta_text([{:xmlText, _attributes, 1, [], text, :text} | _]) do
    text |> to_string() |> String.trim()
  end

  @doc false
  defparsec(:boolean, boolean())
  @doc false
  defparsec(:content_blocks, content_blocks())
  @doc false
  defparsec(:number, number())
  @doc false
  defparsec(:real, real())
  @doc false
  defparsec(:string, string())

  @doc false
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

  @doc false
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

  @doc false
  defparsec(
    :object,
    choice([
      string(),
      name(),
      indirect_reference(),
      real(),
      integer(),
      boolean(),
      parsec(:array),
      parsec(:dictionary)
    ])
  )

  @doc false
  defparsec(
    :stream,
    parsec(:dictionary)
    |> ignore(whitespace())
    |> string("stream")
    |> ignore(eol())
    |> post_traverse({:stream_contents, []})
    |> ignore(optional(eol()))
    |> ignore(string("endstream"))
  )

  @doc false
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
    |> tag(:indirect_object)
  )

  @doc false
  defparsec(
    :pdf,
    ignore(version())
    |> ignore(ascii_string([not: ?\n], min: 1))
    |> ignore(eol())
    |> repeat(parsec(:indirect_object) |> ignore(whitespace()))
    |> ignore(string("xref"))
    |> ignore(eol())
    |> eventually(ignore(string("trailer") |> concat(eol())))
    |> parsec(:dictionary)
  )

  @doc false
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
    dictionary = to_mudbrick({:dictionary, pairs})
    bytes_to_read = dictionary[:Length]

    {
      binary_slice(rest, bytes_to_read..-1//1),
      [binary_slice(rest, 0, bytes_to_read) | results],
      context
    }
  end

  @doc false
  def to_mudbrick(iodata, f),
    do:
      iodata
      |> parse(f)
      |> to_mudbrick()

  defp decompressed_resources_option(files, prefix) do
    files
    |> Enum.with_index(fn file, n ->
      {
        :"#{prefix}#{n + 1}",
        file.value.data
        |> then(
          &if file.value.compress do
            &1 |> Mudbrick.decompress() |> IO.iodata_to_binary()
          else
            &1
          end
        )
      }
    end)
    |> Enum.into(%{})
  end

  defp page_refs(items) do
    {:Root, [catalog_ref]} = Enum.find(items, &match?({:Root, _}, &1))
    catalog = one(items, catalog_ref)
    [page_tree_ref] = catalog.value[:Pages]
    page_tree = one(items, page_tree_ref)
    List.flatten(page_tree.value[:Kids])
  end

  defp operations(items, page) do
    [contents_ref] = page.value[:Contents]
    contents = one(items, contents_ref)
    stream = contents.value

    data =
      if stream.compress do
        Mudbrick.decompress(stream.data)
      else
        stream.data
      end

    if data == "" do
      []
    else
      case to_mudbrick(data, :content_blocks) do
        %Mudbrick.ContentStream{operations: operations} ->
          operations

        _ ->
          raise Error, "Can't parse content blocks: #{data}"
      end
    end
  end

  defp metadata?(item) do
    match?(%{value: %{additional_entries: %{Type: :Metadata}}}, item)
  end

  defp font?(item) do
    match?(%{value: %{additional_entries: %{Subtype: :OpenType}}}, item)
  end

  defp image?(item) do
    match?(%{value: %{additional_entries: %{Subtype: :Image}}}, item)
  end

  defp one(items, ref) do
    Enum.find(items, &match?(%{ref: ^ref}, &1))
  end

  defp all(items, refs) do
    Enum.filter(items, fn
      %{ref: ref} ->
        ref in refs

      _ ->
        false
    end)
  end
end
