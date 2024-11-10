defmodule Mudbrick.Font do
  @type t :: %__MODULE__{
          descendant: Mudbrick.Indirect.Object.t(),
          encoding: atom(),
          name: atom(),
          resource_identifier: atom(),
          to_unicode: Mudbrick.Indirect.Object.t(),
          type: atom(),
          parsed: map()
        }

  @enforce_keys [
    :name,
    :resource_identifier,
    :type
  ]

  defstruct [
    :descendant,
    :encoding,
    :name,
    :resource_identifier,
    :to_unicode,
    :type,
    :parsed
  ]

  defmodule Unregistered do
    defexception [:message]
  end

  alias __MODULE__
  alias Mudbrick.Document
  alias Mudbrick.Font.CMap
  alias Mudbrick.Object
  alias Mudbrick.Stream

  @doc false
  def new(opts) do
    case Keyword.fetch(opts, :parsed) do
      {:ok, parsed} ->
        {:name, font_type} = Map.fetch!(parsed, "SubType")
        struct!(__MODULE__, Keyword.put(opts, :type, type!(font_type)))

      :error ->
        struct!(__MODULE__, opts)
    end
  end

  @doc false
  def type!(s), do: Map.fetch!(%{"Type0" => :Type0}, s)

  @doc false
  def add_objects(doc, fonts) do
    {doc, font_objects, _id} =
      for {human_name, file_contents} <- fonts, reduce: {doc, %{}, 0} do
        {doc, font_objects, id} ->
          font_opts =
            [resource_identifier: :"F#{id + 1}"]

          opentype =
            OpenType.new()
            |> OpenType.parse(file_contents)

          font_name = String.to_atom(opentype.name)

          {doc, font} =
            doc
            |> add_font_file(file_contents)
            |> add_descriptor(opentype, font_name)
            |> add_cid_font(opentype, font_name)
            |> add_font(opentype, font_name, font_opts)

          {doc, Map.put(font_objects, human_name, font), id + 1}
      end

    {doc, font_objects}
  end

  @doc false
  def width(_font, _size, "") do
    0
  end

  def width(font, size, text) do
    {glyph_ids, _positions} = OpenType.layout_text(font.parsed, text)

    for id <- glyph_ids, reduce: 0 do
      acc ->
        glyph_width = Enum.at(font.parsed.glyphWidths, id)
        width_in_points = glyph_width / 1000 * size

        acc + width_in_points
    end
  end

  defp add_font_file(doc, contents) do
    doc
    |> Document.add(
      Stream.new(
        compress: doc.compress,
        data: contents,
        additional_entries: %{
          Length1: byte_size(contents),
          Subtype: :OpenType
        }
      )
    )
  end

  defp add_descriptor(doc, opentype, font_name) do
    doc
    |> Document.add(
      &Font.Descriptor.new(
        ascent: opentype.ascent,
        cap_height: opentype.capHeight,
        descent: opentype.descent,
        file: &1,
        flags: opentype.flags,
        font_name: font_name,
        bounding_box: opentype.bbox,
        italic_angle: opentype.italicAngle,
        stem_vertical: opentype.stemV
      )
    )
  end

  defp add_cid_font(doc, opentype, font_name) do
    doc
    |> Document.add(
      &Font.CIDFont.new(
        default_width: opentype.defaultWidth,
        descriptor: &1,
        type: :CIDFontType0,
        font_name: font_name,
        widths: opentype.glyphWidths
      )
    )
  end

  defp add_font({doc, cid_font}, opentype, font_name, font_opts) do
    doc
    |> Document.add(CMap.new(compress: doc.compress, parsed: opentype))
    |> Document.add(fn cmap ->
      Font.new(
        Keyword.merge(font_opts,
          descendant: cid_font,
          encoding: :"Identity-H",
          name: font_name,
          parsed: opentype,
          to_unicode: cmap
        )
      )
    end)
  end

  defimpl Mudbrick.Object do
    def from(font) do
      Object.from(%{
        Type: :Font,
        BaseFont: font.name,
        Subtype: font.type,
        Encoding: font.encoding,
        DescendantFonts: [font.descendant.ref],
        ToUnicode: font.to_unicode.ref
      })
    end
  end
end
