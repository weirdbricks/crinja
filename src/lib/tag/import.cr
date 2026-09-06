# Crinja supports putting often used code into macros. These macros can go into different templates
# and get imported from there. It’s important to know that imports can be cached and imported templates
# don’t have access to the current template variables, just the globals by default.
#
# See [Jinja2 Template Documentation](http://jinja.pocoo.org/docs/2.9/templates/#import) for details.
class Crinja::Tag::Import < Crinja::Tag
  name "import"

  private def interpret(io : IO, renderer : Renderer, tag_node : TagNode)
    env = renderer.env
    parser = ArgumentsParser.new(tag_node.arguments, renderer.env.config)
    name_expr = parser.parse_expression

    context_var = parser.if_identifier "as" do
      parser.next_token
      parser.current_token.value
    end

    # Real Jinja2's `{% import 'x.j2' as m with context %}` / `...
    # without context %}` modifier (default: without) - previously
    # unparsed entirely, so ANY template using it (with or without)
    # raised "Did not expect any more tokens, found: IDENTIFIER:with"
    # at `parser.close` below and failed the whole render. Parsed and
    # discarded here rather than implemented: this fork's existing
    # `context_var.nil?` behavior (share the current context) already
    # matches real Jinja2's `without context` DEFAULT for the bare
    # `{% import %}` form; `with context` on the `as name` form would
    # need macros to see the IMPORTING template's own local vars, which
    # nothing in the known role corpus depends on yet - fix on
    # encounter, per krikri's reactive-fix policy.
    #
    # `#parse_expression` leaves `current_token` already sitting ON the
    # next UNconsumed token (verified directly - no import), but the
    # "as" clause's own `if_identifier` block above reads
    # `current_token.value` (the `<name>` in `as <name>`) WITHOUT
    # advancing past it, so an extra `next_token` is needed only when
    # that branch actually fired - two different conventions for
    # "what's already been consumed" depending on which branch ran.
    parser.next_token if context_var

    if parser.current_token.kind == Kind::IDENTIFIER && {"with", "without"}.includes?(parser.current_token.value)
      modifier = parser.current_token.value
      parser.next_token
      unless parser.current_token.kind == Kind::IDENTIFIER && parser.current_token.value == "context"
        raise TemplateSyntaxError.new(parser.current_token, "Expected `context` after `#{modifier}`")
      end
    end

    parser.close

    include_name = env.evaluate(name_expr).to_s

    env.context.import_path_stack << include_name

    template = env.get_template(include_name)

    if context_var.nil?
      template.render(env)
    else
      child = Crinja.new(env)

      template.render(child)

      env.errors += child.errors

      template.macros.each do |key, value|
        env.context.macros["#{context_var}.#{key}"] = value
      end
    end
  end
end
