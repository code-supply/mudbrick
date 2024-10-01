defmodule Mudbrick.Document do
  defstruct [:catalog, :root_page_tree]

  alias Mudbrick.Catalog
  alias Mudbrick.Document
  alias Mudbrick.IndirectObject
  alias Mudbrick.IndirectObject.Reference
  alias Mudbrick.PageTree

  def new do
    page_tree = PageTree.new() |> IndirectObject.new(number: 2)

    catalog =
      Catalog.new(page_tree: Reference.new(page_tree))
      |> IndirectObject.new(number: 1)

    %Document{
      catalog: catalog,
      root_page_tree: page_tree
    }
  end

  defimpl String.Chars do
    @initial_generation "00000"
    @free_entries_first_generation "65535"

    def to_string(doc) do
      version = "%PDF-2.0"
      catalog = Mudbrick.PDFObject.from(doc.catalog)
      root_page_tree = Mudbrick.PDFObject.from(doc.root_page_tree)

      objects = [catalog, root_page_tree]
      sections = [version] ++ objects

      trailer =
        Mudbrick.PDFObject.from(%{
          Size: 3,
          Root: Mudbrick.IndirectObject.Reference.new(doc.catalog)
        })

      """
      #{Enum.join(sections, "\n")}
      xref
      0 #{length(objects) + 1}
      #{offsets(sections)}
      trailer
      #{trailer}
      startxref
      #{offset(sections)}
      %%EOF\
      """
    end

    defp offsets(sections) do
      {_, retval} =
        for section <- sections, reduce: {[], ""} do
          {past_sections, ""} ->
            {[section | past_sections],
             "#{padded_offset(past_sections)} #{@free_entries_first_generation} f "}

          {past_sections, acc} ->
            {[section | past_sections],
             "#{acc}\n#{padded_offset(past_sections)} #{@initial_generation} n "}
        end

      retval
    end

    defp padded_offset(strings) do
      strings
      |> offset()
      |> String.pad_leading(10, "0")
    end

    defp offset(strings) do
      strings
      |> Enum.map(&byte_size("#{&1}\n"))
      |> Enum.sum()
      |> Kernel.to_string()
    end
  end
end
