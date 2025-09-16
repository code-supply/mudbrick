defmodule Mudbrick.FontTest do
  use ExUnit.Case, async: true

  import Mudbrick.TestHelper

  alias Mudbrick.Document
  alias Mudbrick.Font
  alias Mudbrick.Font.CMap
  alias Mudbrick.Indirect
  alias Mudbrick.Stream

  test "embedded OTF fonts have a glyph-unicode mapping to enable copy+paste" do
    doc = Mudbrick.new(fonts: %{bodoni: bodoni_regular()})

    font = Document.find_object(doc, &match?(%Font{}, &1))

    assert %Font{to_unicode: mapping} = font.value
    assert Document.object_with_ref(doc, mapping.ref)

    assert show(font.value) =~ ~r"/ToUnicode [0-9] 0 R"

    assert %Mudbrick.Font.CMap{} = mapping.value
  end

  test "serialised CMaps conform to standard" do
    parsed = OpenType.new() |> OpenType.parse(bodoni_regular())

    lines =
      Font.CMap.new(parsed: parsed)
      |> show()
      |> String.split("\n")

    assert [
             <<"<</Length ", _::binary>>,
             ">>",
             "stream",
             "/CIDInit /ProcSet findresource begin"
             | _
           ] = lines

    assert "497 beginbfchar" in lines
  end

  test "embedded OTF fonts create descendant, descriptor and file objects" do
    data = bodoni_regular()
    doc = Mudbrick.new(fonts: %{bodoni: data})
    font = Document.find_object(doc, &match?(%Font{}, &1))

    assert %Font{
             name: :"LibreBodoni-Regular",
             type: :Type0,
             encoding: :"Identity-H",
             descendant: descendant,
             resource_identifier: :F1
           } = font.value

    assert %Font.CIDFont{
             font_name: :"LibreBodoni-Regular",
             descriptor: descriptor,
             type: :CIDFontType0
           } = descendant.value

    assert %Font.Descriptor{
             bounding_box: _bbox,
             file: file,
             font_name: :"LibreBodoni-Regular",
             flags: 4
           } = descriptor.value

    assert %Mudbrick.Stream{
             data: ^data,
             additional_entries: %{
               Length1: 42_952,
               Subtype: :OpenType
             }
           } = file.value

    assert Document.object_with_ref(doc, descendant.ref)
    assert Document.object_with_ref(doc, descriptor.ref)
    assert Document.object_with_ref(doc, file.ref)
  end

  describe "with compression enabled" do
    test "Length is compressed size, Length1 is uncompressed size" do
      data = bodoni_regular()
      compressed = Mudbrick.compress(data)
      doc = Mudbrick.new(compress: true, fonts: %{bodoni: data})
      stream = Document.find_object(doc, &match?(%Stream{data: ^compressed}, &1)).value

      assert IO.iodata_length(stream.data) < IO.iodata_length(data)
      assert stream.additional_entries[:Length1] == IO.iodata_length(data)
      assert stream.length < IO.iodata_length(data)
    end

    test "cmap is compressed" do
      uncompressed_doc = Mudbrick.new(compress: false, fonts: %{bodoni: bodoni_regular()})
      compressed_doc = Mudbrick.new(compress: true, fonts: %{bodoni: bodoni_regular()})
      uncompressed_stream = Document.find_object(uncompressed_doc, &match?(%CMap{}, &1)).value
      compressed_stream = Document.find_object(compressed_doc, &match?(%CMap{}, &1)).value

      assert IO.iodata_length(Mudbrick.Object.to_iodata(compressed_stream)) <
               IO.iodata_length(Mudbrick.Object.to_iodata(uncompressed_stream))
    end
  end

  test "kerned handles Japanese with :pos tuple" do
    doc = Mudbrick.new(fonts: %{bodoni: bodoni_regular()})
    font = Document.find_object(doc, &match?(%Font{}, &1)).value

    result = Font.kerned(font, "日本語")
    assert is_list(result)
    assert Enum.all?(result, &(is_binary(&1) or is_tuple(&1)))
  end

  describe "serialisation" do
    test "with descendant" do
      assert %Font{
               name: :"LibreBodoni-Regular",
               type: :Type0,
               encoding: :"Identity-H",
               descendant: Indirect.Ref.new(22) |> Indirect.Object.new(%{}),
               resource_identifier: :F1,
               to_unicode: Indirect.Ref.new(23) |> Indirect.Object.new(%{})
             }
             |> show() ==
               """
               <</Type /Font
                 /Subtype /Type0
                 /BaseFont /LibreBodoni-Regular
                 /DescendantFonts [22 0 R]
                 /Encoding /Identity-H
                 /ToUnicode 23 0 R
               >>\
               """
    end

    test "CID font" do
      assert %Font.CIDFont{
               font_name: :"LibreBodoni-Regular",
               descriptor: Indirect.Ref.new(666) |> Indirect.Object.new(%{}),
               type: :CIDFontType0,
               default_width: 1000,
               widths: [0, 1, 2]
             }
             |> show() ==
               """
               <</Type /Font
                 /Subtype /CIDFontType0
                 /BaseFont /LibreBodoni-Regular
                 /CIDSystemInfo <</Ordering (Identity)
                 /Registry (Adobe)
                 /Supplement 0
               >>
                 /DW 1000
                 /FontDescriptor 666 0 R
                 /W [0 [0 1 2]]
               >>\
               """
    end

    test "descriptor" do
      assert %Font.Descriptor{
               ascent: 928,
               bounding_box: [1, 1, 1, 1],
               cap_height: 1000,
               descent: 111,
               font_name: :"LibreBodoni-Regular",
               flags: 4,
               file: Indirect.Ref.new(99) |> Indirect.Object.new(%{}),
               italic_angle: 0.0,
               stem_vertical: 80
             }
             |> show() ==
               """
               <</Type /FontDescriptor
                 /Ascent 928
                 /CapHeight 1000
                 /Descent 111
                 /Flags 4
                 /FontBBox [1 1 1 1]
                 /FontFile3 99 0 R
                 /FontName /LibreBodoni-Regular
                 /ItalicAngle 0.0
                 /StemV 80
               >>\
               """
    end
  end
end
