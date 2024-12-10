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

    # test "PDF with text" do
    #   alias Mudbrick.TestHelper
    #   import Mudbrick

    #   input =
    #     new(fonts: %{bodoni: TestHelper.bodoni_regular()})
    #     |> page()
    #     |> text("hello, world!")
    #     |> Mudbrick.Document.finish()

    #   binary =
    #     input
    #     |> Mudbrick.render()
    #     |> IO.iodata_to_binary()

    #   assert binary ==
    #            binary
    #            |> Parser.parse()
    #            |> Mudbrick.render()
    #            |> IO.iodata_to_binary()
    # end

    property "objects" do
      base_object =
        one_of([
          atom(:alphanumeric),
          boolean(),
          integer(),
          float(min: -999, max: 999)
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
