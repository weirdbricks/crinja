class Crinja::Tag::Raw < Crinja::Tag
  name "raw", "endraw"

  private def interpret(io : IO, renderer : Crinja::Renderer, tag_node : TagNode)
    ArgumentsParser.new(tag_node.arguments, renderer.env.config).close
    if (fixed = tag_node.block.children.first).is_a?(AST::FixedString)
      # Real Jinja2 keeps raw content fully exempt from the trim_blocks/
      # lstrip_blocks config (verified against a real jinja2.Environment:
      # `{% raw %}\n  2\n  {% endraw %}` renders with both edges intact
      # under trim_blocks=true and/or lstrip_blocks=true, where the same
      # `{% if %}` block loses them) - but its raw lexer (jinja2/lexer.py
      # 3.1.6) DOES let explicit `-` whitespace control reach the raw
      # block's edges: `raw -%}` swallows the whitespace right after the
      # opening tag (the raw_begin regex ends in `-%}\s*`) and
      # `{%- endraw` rstrips the raw data (the raw state's OptionalLStrip
      # rule), so `1  {%- raw -%}   2   {%- endraw -%}   3` renders `123`
      # in real Jinja2 and real ansible-playbook. The lexer/parser already
      # mark those flags on the raw content's FixedString node (same token
      # flags every other tag uses); only the explicit `-` sides are
      # applied here, never the implicit config trims.
      string = fixed.string
      string = string.lstrip if fixed.trim_left
      string = string.rstrip if fixed.trim_right
      io << string
    else
      raise TemplateSyntaxError.new(tag_node, "raw tag expexts exactly one fixed content node inside")
    end
  end
end
