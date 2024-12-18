defmodule Mudbrick.ParserTest do
  use ExUnit.Case, async: true

  alias Mudbrick.Indirect
  alias Mudbrick.Parser

  describe "streams" do
    test "compressed" do
      stream =
        Mudbrick.Stream.new(
          compress: true,
          data: "oooooooooooo"
        )

      obj =
        Indirect.Ref.new(1)
        |> Indirect.Object.new(stream)

      assert Parser.parse(Mudbrick.Object.to_iodata(obj), :indirect_object) == [
               indirect_object: [
                 1,
                 0,
                 {:dictionary,
                  [
                    pair: [name: "Filter", array: [name: "FlateDecode"]],
                    pair: [name: "Length", integer: ["11"]]
                  ]},
                 "stream",
                 "x\x9C\xCB\xCFG\0\0!\xDE\x055"
               ]
             ]
    end

    test "uncompressed" do
      stream =
        Mudbrick.Stream.new(
          compress: false,
          data: "oooooooooooo"
        )

      obj =
        Indirect.Ref.new(1)
        |> Indirect.Object.new(stream)

      assert Parser.parse(Mudbrick.Object.to_iodata(obj), :indirect_object) == [
               indirect_object: [
                 1,
                 0,
                 {:dictionary, [pair: [name: "Length", integer: ["12"]]]},
                 "stream",
                 "oooooooooooo"
               ]
             ]
    end
  end

  test "strings bounded by parens" do
    assert Parser.parse("(hello, world!)", :string) == [string: ["hello, world!"]]
    assert Parser.parse("()", :string) == [string: []]
  end

  test "real numbers" do
    assert Parser.parse("0.1", :real) == [real: ["0", ".", "1"]]
    assert Parser.parse("0.1", :number) == [{:real, ["0", ".", "1"]}]
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

  test "mixed graphics and text blocks" do
    assert [
             graphics_block: [
               q: [],
               cm: [
                 integer: ["100"],
                 integer: ["0"],
                 integer: ["0"],
                 integer: ["100"],
                 integer: ["0"],
                 integer: ["0"]
               ],
               Do: ["1"],
               Q: []
             ],
             graphics_block: [
               q: [],
               m: [real: ["0", ".", "0"], real: ["-", "1", ".", "2"]],
               RG: [integer: ["0"], integer: ["0"], integer: ["0"]],
               w: [integer: ["1"]],
               l: [real: ["65", ".", "46"], real: ["-", "1", ".", "2"]],
               re: [integer: ["0"], integer: ["0"], integer: ["50"], integer: ["60"]],
               S: [],
               Q: []
             ],
             text_block: [
               BT: [],
               Tf: ["1", "12"],
               TL: [real: ["14", ".", "399999999999999"]],
               Td: [integer: ["7"], integer: ["30"]],
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
               ],
               ET: []
             ],
             text_block: [
               BT: [],
               Tf: ["2", "12"],
               TL: [real: ["14", ".", "399999999999999"]],
               rg: [integer: ["0"], integer: ["0"], integer: ["0"]],
               TJ: [
                 glyph_id: "0105",
                 offset: "44",
                 glyph_id: "00EA",
                 glyph_id: "011E",
                 glyph_id: "011E",
                 glyph_id: "012C",
                 glyph_id: "01F0",
                 glyph_id: "0109",
                 glyph_id: "0125",
                 glyph_id: "01F0",
                 glyph_id: "00C3",
                 glyph_id: "0125",
                 glyph_id: "012C",
                 offset: "35",
                 glyph_id: "015A",
                 offset: "13",
                 glyph_id: "0105",
                 offset: "13",
                 glyph_id: "00EA",
                 offset: "63",
                 glyph_id: "014B",
                 glyph_id: "01F0",
                 offset: "13",
                 glyph_id: "00FF",
                 glyph_id: "012C",
                 glyph_id: "0125",
                 glyph_id: "015A"
               ],
               ET: []
             ]
           ] =
             Parser.parse(
               """
               q
               100 0 0 100 0 0 cm
               /I1 Do
               Q
               q
               0.0 -1.2 m
               0 0 0 RG
               1 w
               65.46 -1.2 l
               0 0 50 60 re
               S
               Q
               BT
               /F1 12 Tf
               14.399999999999999 TL
               7 30 Td
               0 0 0 rg
               [ <00D5> 24 <00C0> <00ED> <00ED> <00FC> <0195> <01B7> <0138> <00FC> <010F> 12 <00ED> <00BB> <0197> ] TJ
               ET
               BT
               /F2 12 Tf
               14.399999999999999 TL
               0 0 0 rg
               [ <0105> 44 <00EA> <011E> <011E> <012C> <01F0> <0109> <0125> <01F0> <00C3> <0125> <012C> 35 <015A> 13 <0105> 13 <00EA> 63 <014B> <01F0> 13 <00FF> <012C> <0125> <015A> ] TJ
               ET
               """,
               :content_blocks
             )
  end

  test "text blocks" do
    assert Parser.parse(
             """
             BT
             q
             7.0 23.0 m
             0 0 0 RG
             0.5 w
             293.29999999999995 23.0 l
             /F1 12 Tf
             14.399999999999999 TL
             0 0 0 rg
             [ <00D5> 24 <00C0> <00ED> <00ED> <00FC> <0195> <01B7> <0138> <00FC> <010F> 12 <00ED> <00BB> <0197> ] TJ
             T*
             S
             Q
             ET
             BT
             /F2 12 Tf
             14.399999999999999 TL
             0 0 0 rg
             [ <0105> 44 <00EA> <011E> <011E> <012C> <01F0> <0109> <0125> <01F0> <00C3> <0125> <012C> 35 <015A> 13 <0105> 1 3 <00EA> 63 <014B> <01F0> 13 <00FF> <012C> <0125> <015A> ] TJ
             ET\
             """,
             :content_blocks
           ) == [
             text_block: [
               BT: [],
               q: [],
               m: [real: ["7", ".", "0"], real: ["23", ".", "0"]],
               RG: [{:integer, ["0"]}, {:integer, ["0"]}, {:integer, ["0"]}],
               w: [real: ["0", ".", "5"]],
               l: [real: ["293", ".", "29999999999995"], real: ["23", ".", "0"]],
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
               ],
               TStar: [],
               S: [],
               Q: [],
               ET: []
             ],
             text_block: [
               BT: [],
               Tf: ["2", "12"],
               TL: [real: ["14", ".", "399999999999999"]],
               rg: [integer: ["0"], integer: ["0"], integer: ["0"]],
               TJ: [
                 {:glyph_id, "0105"},
                 {:offset, "44"},
                 {:glyph_id, "00EA"},
                 {:glyph_id, "011E"},
                 {:glyph_id, "011E"},
                 {:glyph_id, "012C"},
                 {:glyph_id, "01F0"},
                 {:glyph_id, "0109"},
                 {:glyph_id, "0125"},
                 {:glyph_id, "01F0"},
                 {:glyph_id, "00C3"},
                 {:glyph_id, "0125"},
                 {:glyph_id, "012C"},
                 {:offset, "35"},
                 {:glyph_id, "015A"},
                 {:offset, "13"},
                 {:glyph_id, "0105"},
                 {:offset, "1"},
                 {:offset, "3"},
                 {:glyph_id, "00EA"},
                 {:offset, "63"},
                 {:glyph_id, "014B"},
                 {:glyph_id, "01F0"},
                 {:offset, "13"},
                 {:glyph_id, "00FF"},
                 {:glyph_id, "012C"},
                 {:glyph_id, "0125"},
                 {:glyph_id, "015A"}
               ],
               ET: []
             ]
           ]
  end
end
