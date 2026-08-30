# Inside code blocks, you can also assign values to variables. Assignments at top level (outside of
# blocks, macros or loops) are exported from the template like top level macros and can be imported
# by other templates.
#
# Assignments use the set tag and can have multiple targets:
#
# ```
# {% set navigation = [('index.html', 'Index'), ('about.html', 'About')] %}
# {% set key, value = call_something() %}
# ```
#
# It is also possible to use block assignments to capture the contents of a `set` block into a
# variable name. Instead of using an equals sign and a value, you just write the variable name and
# then everything until `{% endset %}` is captured.
#
# {% set navigation %}
#     <li><a href="/">Index</a>
#     <li><a href="/downloads">Downloads</a>
# {% endset %}
# ```
#
# See [Jinja2 Template Documentation](http://jinja.pocoo.org/docs/2.9/templates/#assignments) for details.
class Crinja::Tag::Set < Crinja::Tag
  name "set", "endset"

  private def interpret(io : IO, renderer : Crinja::Renderer, tag_node : TagNode)
    env = renderer.env
    args = ArgumentsParser.new(tag_node.arguments, renderer.env.config)

    if tag_node.arguments.size == 2
      # IDENTIFIER + EOF
      name = args.current_token.value
      args.next_token
      value = renderer.render(tag_node.block).value
      env.context[name] = SafeString.new(value)
      args.close
    elsif args.current_token.kind == Crinja::Parser::Token::Kind::IDENTIFIER &&
          (peeked = args.peek_token?) && peeked.kind == Crinja::Parser::Token::Kind::POINT
      # `{% set ns.attr = ... %}` - the one exception to `{% set %}`
      # otherwise only ever supporting a bare name target: mutates the
      # resolved `Namespace` object IN PLACE rather than rebinding
      # `env.context`, which is what makes the mutation visible outside
      # the current `{% for %}` iteration - every loop-body read of `ns`
      # still resolves to the same object reference set once before the
      # loop.
      target_name = args.current_token.value
      args.next_token # consume target identifier
      args.next_token # consume "."

      unless args.current_token.kind == Crinja::Parser::Token::Kind::IDENTIFIER
        raise TemplateSyntaxError.new(args.current_token, "expected attribute name in namespace assignment")
      end
      attr_name = args.current_token.value
      args.next_token # consume attribute identifier

      unless args.current_token.kind == Crinja::Parser::Token::Kind::KW_ASSIGN
        raise TemplateSyntaxError.new(args.current_token, "expected '=' in namespace attribute assignment")
      end
      args.next_token # consume "="

      value = env.evaluate(args.parse_expression)

      target = env.resolve(target_name)
      ns = target.raw
      unless ns.is_a?(Crinja::Namespace)
        raise TemplateSyntaxError.new(args.current_token, "'#{target_name}' is not a namespace object, cannot assign attribute '#{attr_name}'")
      end
      ns[attr_name] = value

      args.close
    elsif args.current_token.kind == Crinja::Parser::Token::Kind::IDENTIFIER &&
          (peeked2 = args.peek_token?) && peeked2.kind == Crinja::Parser::Token::Kind::COMMA
      # `{% set a, b = expr %}` - tuple-target assignment, distinct from
      # `parse_keyword_list`'s own `a = x, b = y` repeated-single-
      # assignment syntax below (disambiguated by whether the token right
      # after the first identifier is a comma, meaning another bare
      # target name follows, or `=`, meaning a value). Evaluates the
      # right-hand side ONCE and unpacks it positionally across every
      # target name.
      targets = [] of String
      targets << args.current_token.value
      args.next_token
      while args.current_token.kind == Crinja::Parser::Token::Kind::COMMA
        args.next_token
        unless args.current_token.kind == Crinja::Parser::Token::Kind::IDENTIFIER
          raise TemplateSyntaxError.new(args.current_token, "expected identifier in set tuple-target list")
        end
        targets << args.current_token.value
        args.next_token
      end

      unless args.current_token.kind == Crinja::Parser::Token::Kind::KW_ASSIGN
        raise TemplateSyntaxError.new(args.current_token, "expected '=' in set tuple assignment")
      end
      args.next_token

      items = env.evaluate(args.parse_expression).each.to_a
      targets.each_with_index do |target_var, i|
        env.context[target_var] = items[i]? || Crinja::UNDEFINED
      end

      args.close
    else
      args.parse_keyword_list.each do |identifier, expr|
        env.context[identifier.name] = env.evaluate(expr)
      end
      # raise TemplateSyntaxError.new(tag_node, "Tag `set` requires either a single name argument (set block) or at least one assignment", e)

      args.close
    end
  end

  def has_block?(node : TagNode)
    node.arguments.size <= 2
  end
end
