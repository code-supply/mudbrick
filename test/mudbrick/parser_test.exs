defmodule Mudbrick.ParserTest do
  use ExUnit.Case, async: true

  alias Mudbrick.Parser

  describe "parsing to AST" do
    test "strings bounded by parens" do
      assert Parser.parse("(hello, world!)", :string) == [string: ["hello, world!"]]
      assert Parser.parse("()", :string) == [string: []]
    end

    test "real numbers" do
      assert Parser.parse("0.1", :real) == [real: ["0", ".", "1"]]
    end

    test "booleans" do
      assert Parser.parse("true", :boolean) == [boolean: true]
    end

    test "empty dictionary" do
      assert Parser.parse("<<>>", :dictionary) == [{:dictionary, []}]
    end

    test "nonempty dictionary" do
      assert Parser.parse(
               """
               <</Name 123 /Type /Font
               /Pages 1 0 R
               /Page (hello)
               >>\
               """,
               :dictionary
             ) ==
               [
                 dictionary: [
                   {:pair, [name: "Name", integer: ["123"]]},
                   {:pair, [name: "Type", name: "Font"]},
                   {:pair, [name: "Pages", indirect_reference: ["1", "0", "R"]]},
                   {:pair, [name: "Page", string: ["hello"]]}
                 ]
               ]
    end

    test "dictionary in a dictionary" do
      assert Parser.parse("<</Font <</Type /CIDFont>>>>", :dictionary) ==
               [
                 dictionary: [
                   pair: [
                     name: "Font",
                     dictionary: [
                       {:pair,
                        [
                          name: "Type",
                          name: "CIDFont"
                        ]}
                     ]
                   ]
                 ]
               ]
    end

    test "empty array" do
      assert Parser.parse("[]", :array) == [{:array, []}]
    end

    test "empty array inside array" do
      assert Parser.parse("[[]]", :array) == [{:array, [array: []]}]
    end

    test "nonempty nested array" do
      assert Parser.parse("[[true false] true]", :array) == [
               {:array, [array: [boolean: true, boolean: false], boolean: true]}
             ]
    end

    test "array with negative integers" do
      assert Parser.parse("[-416 -326 1379 924]", :array) == [
               {:array,
                [
                  integer: ["-", "416"],
                  integer: ["-", "326"],
                  integer: ["1379"],
                  integer: ["924"]
                ]}
             ]
    end

    test "true on its own in an array" do
      assert Parser.parse("[true]", :array) == [
               {:array, [boolean: true]}
             ]
    end
  end
end

defmodule Mudbrick.ParseTextContentTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Mudbrick.Parser

  setup do
    import Mudbrick
    import Mudbrick.TestHelper

    doc =
      new(fonts: %{bodoni: bodoni_regular()})
      |> page()
      |> text("hello, world!")
      |> Mudbrick.Document.finish()

    obj =
      doc.objects
      |> Enum.find(&(%Mudbrick.ContentStream{} = &1.value))

    [
      {:dictionary, [pair: [name: "Length", integer: ["150"]]]},
      "stream",
      stream
    ] =
      obj.value
      |> Mudbrick.Object.to_iodata()
      |> IO.iodata_to_binary()
      |> Parser.parse(:stream)

    %{doc: doc, stream: stream}
  end

  test "can extract text from a stream with a single font", %{doc: doc} do
    assert doc |> Mudbrick.render() |> Parser.extract_text() == ["hello, world!"]
  end

  test "can turn text content to Mudbrick", %{stream: stream} do
    assert Parser.to_mudbrick(stream, :text_block) ==
             %Mudbrick.ContentStream{
               page: nil,
               operations: [
                 %Mudbrick.ContentStream.ET{},
                 %Mudbrick.ContentStream.TJ{
                   auto_kern: true,
                   kerned_text: [
                     {"00D5", 24},
                     "00C0",
                     "00ED",
                     "00ED",
                     "00FC",
                     "0195",
                     "01B7",
                     "0138",
                     "00FC",
                     {"010F", 12},
                     "00ED",
                     "00BB",
                     "0197"
                   ]
                 },
                 %Mudbrick.ContentStream.Rg{stroking: false, r: 0, g: 0, b: 0},
                 %Mudbrick.ContentStream.TL{leading: 14.399999999999999},
                 %Mudbrick.ContentStream.Tf{font_identifier: :F1, size: "12"},
                 %Mudbrick.ContentStream.BT{}
               ]
             }
  end

  test "can parse text content to AST", %{stream: stream} do
    assert [
             text_block: [
               Tf: ["1", "12"],
               TL: [real: ["14", ".", "399999999999999"]],
               rg: [integer: ["0"], integer: ["0"], integer: ["0"]],
               TJ: [
                 glyph_id: "00D5",
                 offset: "24",
                 glyph_id: "00C0",
                 glyph_id: "00ED",
                 glyph_id: "00ED",
                 glyph_id: "00FC",
                 glyph_id: "0195",
                 glyph_id: "01B7",
                 glyph_id: "0138",
                 glyph_id: "00FC",
                 glyph_id: "010F",
                 offset: "12",
                 glyph_id: "00ED",
                 glyph_id: "00BB",
                 glyph_id: "0197"
               ]
             ]
           ] =
             stream
             |> Parser.parse(:text_block)
  end
end

defmodule Mudbrick.ParseRoundtripTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Mudbrick.Parser

  describe "roundtripping from/to Mudbrick" do
    test "minimal PDF" do
      input = Mudbrick.new()

      assert input
             |> Mudbrick.render()
             |> IO.iodata_to_binary()
             |> Parser.parse() == input
    end

    test "PDF with text" do
      alias Mudbrick.TestHelper
      import Mudbrick

      input =
        new(fonts: %{bodoni: TestHelper.bodoni_regular()})
        |> page()
        |> text("hello, world!")
        |> Mudbrick.Document.finish()

      binary =
        input
        |> Mudbrick.render()
        |> IO.iodata_to_binary()

      assert binary ==
               binary
               |> Parser.parse()
               |> Mudbrick.render()
               |> IO.iodata_to_binary()
    end

    property "objects" do
      base_object =
        one_of([
          atom(:alphanumeric),
          boolean(),
          integer(),
          float(min: -999, max: 999),
          string(:alphanumeric)
        ])

      check all input <-
                  one_of([
                    base_object,
                    list_of(base_object),
                    list_of(list_of(base_object)),
                    map_of(atom(:alphanumeric), base_object),
                    map_of(atom(:alphanumeric), map_of(atom(:alphanumeric), base_object))
                  ]) do
        assert input
               |> Mudbrick.Object.to_iodata()
               |> Parser.to_mudbrick(:object) == input
      end
    end
  end
end
