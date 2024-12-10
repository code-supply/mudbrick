defmodule Mudbrick.Document do
  @type t :: %__MODULE__{
          compress: boolean(),
          objects: list()
        }

  defstruct compress: false,
            objects: []

  alias Mudbrick.Catalog
  alias Mudbrick.Document
  alias Mudbrick.Font
  alias Mudbrick.Image
  alias Mudbrick.Indirect
  alias Mudbrick.Metadata
  alias Mudbrick.PageTree
  alias Mudbrick.Stream

  @type option ::
          {:compress, boolean()}
          | {:fonts, map()}
          | {:images, map()}
          | {:producer, String.t()}
          | {:creator_tool, String.t()}
          | {:create_date, DateTime.t()}
          | {:modify_date, DateTime.t()}
          | {:title, String.t()}
          | {:creators, list(String.t())}

  @type options :: [option()]

  @doc false
  @spec new(options()) :: t()
  def new(opts) do
    compress = Keyword.get(opts, :compress, false)

    {doc, font_objects} =
      Font.add_objects(
        %Document{compress: compress},
        Keyword.get(opts, :fonts, [])
      )

    {doc, image_objects} =
      Image.add_objects(doc, Keyword.get(opts, :images, []))

    doc
    |> add([
      PageTree.new(fonts: font_objects, images: image_objects),
      Stream.new(
        compress: compress,
        data: Metadata.render(opts),
        additional_entries: %{
          Type: :Metadata,
          Subtype: :XML
        }
      )
    ])
    |> add(fn [page_tree, metadata] ->
      Catalog.new(page_tree: page_tree, metadata: metadata)
    end)
    |> finish()
  end

  @doc false
  def add(%Document{} = doc, values) when is_list(values) do
    List.foldr(values, {doc, []}, fn value, {doc, objects} ->
      {doc, obj} = add(doc, value)
      {doc, [obj | objects]}
    end)
  end

  @doc false
  def add({doc, just_added_object}, fun) when is_function(fun) do
    add(doc, fun.(just_added_object))
  end

  @doc false
  def add(%Document{objects: objects} = doc, value) do
    object = next_object(doc, value)
    {%Document{doc | objects: [object | objects]}, object}
  end

  @doc false
  def add_page_ref(%Indirect.Object{value: tree} = tree_obj, page) do
    %{tree_obj | value: PageTree.add_page_ref(tree, page.ref)}
  end

  @doc false
  def update({doc, just_added_object}, object, fun) do
    put(doc, %{object | value: fun.(just_added_object, object.value)})
  end

  @doc false
  def update(doc, object, fun) do
    put(doc, %{object | value: fun.(object.value)})
  end

  @doc false
  def finish({doc, object}, fun) do
    {doc, fun.(object)}
  end

  @doc false
  def finish({doc, _objects}) do
    doc
  end

  @doc false
  def finish(doc) do
    doc
  end

  @doc false
  def root_page_tree(doc) do
    find_object(doc, &match?(%PageTree{}, &1))
  end

  @doc false
  def update_root_page_tree(doc, fun) do
    Map.update!(doc, :objects, fn objects ->
      update_in(objects, [Access.find(&match?(%PageTree{}, &1.value))], &fun.(&1))
    end)
  end

  @doc false
  def catalog(doc) do
    find_object(doc, &match?(%Catalog{}, &1))
  end

  @doc false
  def object_with_ref(doc, ref) do
    Enum.at(doc.objects, -ref.number)
  end

  @doc false
  def find_object(%Document{objects: objects}, f) do
    Enum.find(objects, fn object ->
      f.(object.value)
    end)
  end

  defp put(doc, updated_object) do
    {
      Map.update!(doc, :objects, fn objects ->
        List.replace_at(objects, -updated_object.ref.number, updated_object)
      end),
      updated_object
    }
  end

  defp next_object(doc, value) do
    doc |> next_ref() |> Indirect.Object.new(value)
  end

  defp next_ref(doc) do
    doc |> next_object_number() |> Indirect.Ref.new()
  end

  defp next_object_number(doc) do
    length(doc.objects) + 1
  end
end
