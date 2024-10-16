defmodule Mudbrick.Page do
  defstruct contents: nil,
            fonts: %{},
            parent: nil,
            size: nil

  alias Mudbrick.Document
  alias Mudbrick.Font

  def new(opts \\ []) do
    struct!(__MODULE__, opts)
  end

  def add(doc, opts) do
    add_empty_page(doc, opts)
    |> add_to_page_tree()
  end

  defp add_empty_page(doc, opts) do
    case Keyword.pop(opts, :fonts) do
      {nil, opts} ->
        Document.add(doc, new_at_root(opts, doc))

      {fonts, opts} ->
        Font.add_objects(doc, fonts)
        |> Document.add(
          &(opts
            |> Keyword.put(:fonts, &1)
            |> new_at_root(doc))
        )
    end
  end

  defp new_at_root(opts, doc) do
    Keyword.put(opts, :parent, Document.root_page_tree(doc).ref) |> new()
  end

  defp add_to_page_tree({doc, page}) do
    {
      Document.update_root_page_tree(doc, fn page_tree ->
        Document.add_page_ref(page_tree, page)
      end),
      page
    }
  end

  defimpl Mudbrick.Object do
    def from(page) do
      {width, height} = page.size

      Mudbrick.Object.from(
        %{
          Type: :Page,
          Parent: page.parent,
          MediaBox: [0, 0, width, height]
        }
        |> Map.merge(
          case page.contents do
            nil ->
              %{}

            contents ->
              %{
                Contents: contents.ref,
                Resources: %{Font: font_dictionary(page.fonts)}
              }
          end
        )
      )
    end

    defp font_dictionary(fonts) do
      for {_human_identifier, object} <- fonts, into: %{} do
        {object.value.resource_identifier, object.ref}
      end
    end
  end
end
