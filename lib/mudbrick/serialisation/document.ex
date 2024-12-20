defimpl Mudbrick.Object, for: Mudbrick.Document do
  @initial_generation "00000"
  @free_entries_first_generation "65535"

  alias Mudbrick.Document
  alias Mudbrick.Object

  def to_iodata(%Document{objects: raw_objects} = doc) do
    header = "%PDF-2.0\n%����"
    objects = raw_objects |> Enum.reverse() |> Enum.map(&Object.to_iodata/1)
    sections = [header | objects]

    trailer =
      Object.to_iodata(%{
        Size: length(objects) + 1,
        Root: Document.catalog(doc).ref
      })

    [
      Enum.intersperse(sections, ?\n),
      "\nxref\n",
      ["0 ", Kernel.to_string(length(objects) + 1), "\n"],
      offsets(sections),
      "\ntrailer\n",
      trailer,
      "\nstartxref\n",
      offset(sections),
      "\n%%EOF"
    ]
  end

  defp offsets(sections) do
    {_, retval} =
      for section <- sections, reduce: {[], []} do
        {[], []} ->
          {
            [section],
            [padded_offset([]), " ", @free_entries_first_generation, " f "]
          }

        {past_sections, iolist} ->
          {
            [section | past_sections],
            [iolist, "\n", padded_offset(past_sections), " ", @initial_generation, " n "]
          }
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
    |> Enum.map(&IO.iodata_length([&1, "\n"]))
    |> Enum.sum()
    |> Kernel.to_string()
  end
end
