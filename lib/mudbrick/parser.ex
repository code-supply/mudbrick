defmodule Mudbrick.Parser do
  import NimbleParsec
  import Mudbrick.Parser.Helpers

  alias Mudbrick.ContentStream.{
    Cm,
    Do,
    L,
    M,
    QPop,
    QPush,
    Re,
    Rg,
    Td,
    Tf,
    TJ,
    TL,
    W
  }

  alias Mudbrick.Indirect

  def parse(iodata) do
    {:ok, parsed_items, _rest, %{}, _, _} =
      iodata
      |> IO.iodata_to_binary()
      |> pdf()

    items = Enum.flat_map(parsed_items, &ast_to_mudbrick/1)
    page_refs = page_refs(items)
    font_files = Enum.filter(items, &font?/1)
    image_files = Enum.filter(items, &image?/1)
    fonts = decompressed_resources_option(font_files, "F")
    images = decompressed_resources_option(image_files, "I")

    compress? = Enum.any?(font_files, fn f -> f.value.compress end)

    opts = []
    opts = if map_size(fonts) > 0, do: Keyword.put(opts, :fonts, fonts), else: opts
    opts = if map_size(images) > 0, do: Keyword.put(opts, :images, images), else: opts
    opts = if compress?, do: Keyword.put(opts, :compress, true), else: opts

    for page <- all(items, page_refs), reduce: Mudbrick.new(opts) do
      acc ->
        operations = operations(items, page)

        [_, _, w, h] = page.value[:MediaBox]

        Mudbrick.page(acc, size: {w, h})
        |> Mudbrick.ContentStream.update_operations(fn ops ->
          operations ++ ops
        end)
    end
    |> Mudbrick.Document.finish()
  end

  def parse(iodata, f) do
    case iodata
         |> IO.iodata_to_binary()
         |> then(&apply(__MODULE__, f, [&1])) do
      {:ok, resp, _, %{}, _, _} -> resp
    end
  end

  defparsec(:boolean, boolean())
  defparsec(:number, number())
  defparsec(:real, real())
  defparsec(:string, string())

  defparsec(
    :content_blocks,
    repeat(
      choice([
        text_block(),
        graphics_block()
      ])
      |> ignore(optional(whitespace()))
    )
  )

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

  def to_mudbrick(iodata, f),
    do:
      iodata
      |> parse(f)
      |> ast_to_mudbrick()

  defp decompressed_resources_option(files, prefix) do
    {_, resources} =
      for file <- files, reduce: {1, %{}} do
        {n, resources} ->
          if file.value.compress do
            {n + 1,
             Map.put(
               resources,
               :"#{prefix}#{n}",
               Mudbrick.decompress(file.value.data) |> IO.iodata_to_binary()
             )}
          else
            {n + 1, Map.put(resources, :"#{prefix}#{n}", file.value.data)}
          end
      end

    resources
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
      %Mudbrick.ContentStream{operations: operations} =
        to_mudbrick(data, :content_blocks)

      operations
    end
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

  defp ast_to_operator({:cm, [x_scale, x_skew, y_skew, y_scale, x_translate, y_translate]}),
    do: %Cm{
      scale: {ast_to_mudbrick(x_scale), ast_to_mudbrick(y_scale)},
      skew: {ast_to_mudbrick(x_skew), ast_to_mudbrick(y_skew)},
      position: {ast_to_mudbrick(x_translate), ast_to_mudbrick(y_translate)}
    }

  defp ast_to_operator({:re, [x, y, w, h]}),
    do: %Re{
      lower_left: {ast_to_mudbrick(x), ast_to_mudbrick(y)},
      dimensions: {ast_to_mudbrick(w), ast_to_mudbrick(h)}
    }

  defp ast_to_operator({:m, [x, y]}),
    do: %M{
      coords: {ast_to_mudbrick(x), ast_to_mudbrick(y)}
    }

  defp ast_to_operator({:l, [x, y]}),
    do: %L{
      coords: {ast_to_mudbrick(x), ast_to_mudbrick(y)}
    }

  defp ast_to_operator({:RG, [r, g, b]}),
    do: %Rg{
      stroking: true,
      r: ast_to_mudbrick(r),
      g: ast_to_mudbrick(g),
      b: ast_to_mudbrick(b)
    }

  defp ast_to_operator({:Do, [index]}), do: %Do{image_identifier: :"I#{index}"}
  defp ast_to_operator({:Td, [x, y]}), do: %Td{tx: ast_to_mudbrick(x), ty: ast_to_mudbrick(y)}
  defp ast_to_operator({:w, number}), do: %W{width: ast_to_mudbrick(number)}
  defp ast_to_operator({:Tf, [index, size]}), do: %Tf{font_identifier: :"F#{index}", size: size}
  defp ast_to_operator({:TL, leading}), do: %TL{leading: ast_to_mudbrick(leading)}

  defp ast_to_operator({:rg, components}),
    do: struct!(Rg, Enum.zip([:r, :g, :b], Enum.map(components, &ast_to_mudbrick/1)))

  defp ast_to_operator({:TJ, glyphs_and_offsets}) do
    contains_kerns? = Enum.any?(glyphs_and_offsets, &match?({:offset, _}, &1))

    kerned_text =
      Enum.reduce(glyphs_and_offsets, [], fn
        {:glyph_id, id}, acc ->
          [id | acc]

        {:offset, offset}, [last_glyph | acc] ->
          [{last_glyph, String.to_integer(offset)} | acc]
      end)

    %TJ{
      auto_kern: contains_kerns?,
      kerned_text: Enum.reverse(kerned_text)
    }
  end

  defp ast_to_operator({:Q, []}), do: %QPop{}
  defp ast_to_operator({:q, []}), do: %QPush{}

  defp ast_to_operator({op, []}),
    do: struct!(Module.safe_concat([Mudbrick.ContentStream, op]), [])

  defp ast_to_mudbrick([{block_type, _operations} | _rest] = input)
       when block_type in [:text_block, :graphics_block] do
    mudbrick_operations =
      Enum.flat_map(input, fn {_block_type, operations} ->
        Enum.map(operations, &ast_to_operator/1)
      end)

    %Mudbrick.ContentStream{
      page: nil,
      operations: Enum.reverse(mudbrick_operations)
    }
  end

  defp ast_to_mudbrick(x) when is_tuple(x), do: ast_to_mudbrick([x])
  defp ast_to_mudbrick(array: a), do: Enum.map(a, &ast_to_mudbrick/1)
  defp ast_to_mudbrick(boolean: b), do: b
  defp ast_to_mudbrick(integer: [n]), do: String.to_integer(n)
  defp ast_to_mudbrick(integer: ["-", n]), do: -String.to_integer(n)
  defp ast_to_mudbrick(real: [n, ".", d]), do: String.to_float("#{n}.#{d}")
  defp ast_to_mudbrick(real: ["-" | rest]), do: -ast_to_mudbrick(real: rest)
  defp ast_to_mudbrick(string: [s]), do: s
  defp ast_to_mudbrick(string: []), do: ""
  defp ast_to_mudbrick(name: s), do: String.to_atom(s)

  defp ast_to_mudbrick(pair: [k, v]) do
    {ast_to_mudbrick(k), ast_to_mudbrick(v)}
  end

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
      Indirect.Ref.new(ref_number)
      |> Indirect.Object.new(
        pairs
        |> Enum.map(&ast_to_mudbrick/1)
        |> Enum.into(%{})
      )
      | ast_to_mudbrick(rest)
    ]
  end

  defp ast_to_mudbrick([
         {:indirect_object,
          [
            ref_number,
            _version,
            {:dictionary, pairs},
            "stream",
            stream
          ]}
         | rest
       ]) do
    additional_entries =
      pairs
      |> Enum.map(&ast_to_mudbrick/1)
      |> Map.new()
      |> Map.drop([:Length])

    [
      Indirect.Ref.new(ref_number)
      |> Indirect.Object.new(
        Mudbrick.Stream.new(
          compress: additional_entries[:Filter] == [:FlateDecode],
          data: stream,
          additional_entries: additional_entries
        )
      )
      | ast_to_mudbrick(rest)
    ]
  end

  defp ast_to_mudbrick([
         {:indirect_reference,
          [
            ref_number,
            _version,
            "R"
          ]}
         | _rest
       ]) do
    [
      ref_number
      |> String.to_integer()
      |> Indirect.Ref.new()
    ]
  end
end
