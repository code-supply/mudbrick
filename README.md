# Mudbrick

[API Documentation](https://hexdocs.pm/mudbrick/Mudbrick.html)

PDF generator, beelining for:

- PDF 2.0 support.
- In-process, pure functional approach.
- OpenType support.
- Special characters and ligatures, like ₛᵤ₆ₛ꜀ᵣᵢₚₜₛ for chemical compounds etc.

Currently working:

- OpenType fonts with ligatures, special characters and automatic kerning.
- Text positioning.
- Right and centre alignment.
- Coloured text.
- JPEG images.
- Compression.
- Underline with colour and thickness options.
- Basic line drawing.

To do:

- Other image formats.
- Font subsetting.
- Vector graphics.
- Strikethrough.
- Text highlight.

## Installation

```elixir
def deps do
  [
    {:mudbrick, "~> 0.0"}
  ]
end
```

## What's the deal with the name?

It's a play on Adobe, which means mudbrick in Spanish.

## See also

- [elixir-pdf](https://github.com/andrewtimberlake/elixir-pdf), a more mature
  library, supporting AFM instead of OTF fonts, but only the base
  WinAnsiEncoding and no special characters. Uses a GenServer for state.
- [erlguten](https://github.com/hwatkins/erlguten), an antiquated Erlang
  PDF generator.
- [opentype-elixir](https://github.com/jbowtie/opentype-elixir), used for OTF
  parsing.
- [ex_image_info](https://github.com/Group4Layers/ex_image_info), used for
  image metadata parsing.
