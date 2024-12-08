defmodule Mudbrick.ParserTest do
  use ExUnit.Case, async: true

  alias Mudbrick.Parser

  describe "parsing to AST" do
    test "booleans" do
      assert Parser.parse("true", :boolean) == [boolean: true]
    end

    test "empty dictionary" do
      assert Parser.parse("<<>>", :dictionary) == [{:dictionary, []}]
    end

    test "nonempty dictionary" do
      assert Parser.parse("<</Name 123 /Type /Font>>", :dictionary) ==
               [
                 dictionary: [
                   {:pair, [name: "Name", integer: ["123"]]},
                   {:pair, [name: "Type", name: "Font"]}
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
    property "objects" do
      base_object =
        one_of([
          atom(:alphanumeric),
          boolean(),
          integer()
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
