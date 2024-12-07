defmodule Mudbrick.ParserTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Mudbrick.Indirect
  alias Mudbrick.Parser

  describe "arrays" do
    property "roundtrip" do
      check all input <- list_of(one_of([boolean(), integer()])) do
        assert input
               |> Mudbrick.Object.to_iodata()
               |> IO.iodata_to_binary()
               |> Parser.parse(:array) == input
      end
    end
  end

  describe "indirect objects" do
    property "roundtrip" do
      check all reference_number <- positive_integer(),
                content <-
                  member_of([
                    true,
                    false
                    # Mudbrick.PageTree.new()
                  ]) do
        input =
          reference_number
          |> Indirect.Ref.new()
          |> Indirect.Object.new(content)

        assert input
               |> Mudbrick.Object.to_iodata()
               |> IO.iodata_to_binary()
               |> Parser.parse(:indirect_object) == input
      end
    end
  end

  # describe "minimal PDF" do
  #   test "roundtrips" do
  #     input = minimal()

  #     assert input
  #            |> Mudbrick.render()
  #            |> Parser.parse() ==
  #              input
  #   end
  # end

  # defp minimal() do
  #   Mudbrick.new()
  #   |> Mudbrick.page()
  #   |> Mudbrick.Document.finish()
  # end
end
