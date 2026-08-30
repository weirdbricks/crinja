# The renderer traverses through an abstract syntax tree to render all template nodes to a string or IO.

# :nodoc:
class Crinja::Renderer
  getter template

  # :nodoc:
  property extend_parent_templates : Array(Template) = [] of Template

  # :nodoc:
  property blocks : Hash(String, Array(AST::NodeList))
  @blocks = Hash(String, Array(AST::NodeList)).new do |hash, k|
    hash[k] = Array(AST::NodeList).new
  end

  # Returns the environment.
  getter env : Crinja

  # Creates a new evaluator for the template *template* with optional environment *env*. If no
  # environment is provided, the environment of the template is used.
  def initialize(@template : Template, env : Crinja? = nil)
    @env = env || @template.env
  end

  private macro visit(*node_types)
    # :nodoc:
    def render(node : {{
                        (node_types.map do |type|
                          "AST::#{type.id}"
                        end).join(" | ").id
                      }})
      {{ yield }}
    rescue e : Crinja::Error
      # Add location info to runtime exception.
      e.at(node) unless e.has_location?
      raise e
    end
  end

  def render(template : Template)
    String.build do |io|
      render(io, template)
    end
  end

  def render(io : IO, template : Template)
    env.context.autoescape = env.config.autoescape?(template.filename)

    env.context.macros.merge(template.macros)
    output = render(template.nodes)

    @extend_parent_templates.each do |parent_template|
      output = render(parent_template.nodes)

      env.context.extend_path_stack.pop
    end

    resolve_block_stubs(output)

    output.value(io)
  end

  visit NodeList do
    self.render(node.children)
  end

  def render(nodes : Array(AST::TemplateNode))
    OutputList.new.tap do |output|
      nodes.each do |node|
        output << self.render(node)
      end
    end
  end

  # Real Jinja2's `trim_blocks` config only removes a SINGLE newline
  # character immediately following a block tag - it does nothing at all
  # when there's no newline there to remove.
  #
  # Explicit `-` whitespace control (`node.trim_left`/`node.trim_right`)
  # means something categorically stronger than the implicit trim_blocks/
  # lstrip_blocks config: real Jinja2 strips ALL contiguous whitespace on
  # that side - unbounded, potentially crossing several blank lines -
  # right up to the first non-whitespace character (verified directly
  # against a real `jinja2.Environment` render, not assumed: `{% if true
  # -%}\n        yay\n    {% endif %}` renders as bare `yay` immediately
  # following the preceding static text, with NOT ONE of the newline/
  # space characters between the tag and `yay` surviving). The implicit
  # trim_blocks/lstrip_blocks config, by contrast, is deliberately much
  # narrower - it only ever removes a SINGLE newline character (trim_
  # blocks) or the whitespace-only prefix of the tag's OWN line
  # (lstrip_blocks), never reaching past it into further lines.
  #
  # `Util::StringTrimmer.trim` only ever implements that second, narrower
  # shape (first-line-only lstrip / last-line-only rstrip, optionally
  # dropping one adjacent newline) - correct for the implicit case, but
  # wrong for explicit `-` on any text segment spanning more than one
  # line (a blank line, or more, between the tag and real content) -
  # only the FIRST such line's whitespace got stripped, leaving the rest
  # untouched (found via `buluma.collectd`'s own `collectd.conf.j2`,
  # round170 - first found and left unfixed on a different template in
  # round85).
  #
  # Fixed here, not in `StringTrimmer.trim` itself: an explicitly-marked
  # side is fully `lstrip`/`rstrip`-ed UP FRONT (real Crystal/Python
  # semantics - strips every contiguous whitespace character, spanning
  # any number of newlines, unconditionally) before ever reaching `trim`,
  # and that side's own `left`/`right` flag into `trim` is then forced
  # false so `trim` doesn't reprocess it - it only still runs its
  # existing (unchanged, still fully spec-covered) narrow logic for
  # whichever side is trimmed solely by the IMPLICIT trim_blocks/
  # lstrip_blocks config with no explicit `-` present. This keeps every
  # one of `StringTrimmer.trim`'s own existing behaviors and specs
  # completely untouched - only this call site's OWN dispatch changes.
  def self.trim_text(node, trim_blocks = false, lstrip_blocks = false)
    string = node.string

    # Explicit `-` whitespace control: full strip on that side (strong).
    string = string.lstrip if node.trim_left
    string = string.rstrip if node.trim_right

    # Implicit trim_blocks: remove a SINGLE newline immediately following a
    # block tag (matches Jinja2). Does not fire for `+%}` (no_trim_left) and
    # does not stack with an explicit `-` on that side (already stripped).
    if trim_blocks && node.left_is_block && !node.no_trim_left && !node.trim_left && string.starts_with?('\n')
      string = string[1..]
    end

    # Implicit lstrip_blocks: strip the whitespace sitting on the block tag's
    # OWN line (the suffix after the last newline), KEEPING the newline. Faithful
    # to Jinja2's algorithm:
    #   - only fires when the tag is preceded by a newline (never for inline
    #     tags whose gap is a bare space - the `line_starting` edge is
    #     approximated by requiring a newline),
    #   - only strips when that suffix is entirely whitespace (NBSP included,
    #     matching Python's \s), so mixed content like "foo  " is left alone,
    #   - never fires for `{%+` (no_lstrip_right) or an explicit `-` (trim_right).
    if lstrip_blocks && node.right_is_block && !node.no_lstrip_right && !node.trim_right
      if string.empty? || !(nl = string.rindex('\n'))
        # no newline -> inline gap, nothing to strip
      elsif string[(nl + 1)..].each_char.all?(&.whitespace?)
        string = string[0..nl]
      end
    end

    string
  end

  visit FixedString do
    RenderedOutput.new Crinja::Renderer.trim_text(node, env.config.trim_blocks, env.config.lstrip_blocks)
  end

  visit TagNode do
    env.tags[node.name].interpret_output(self, node)
  end

  visit EndTagNode do
    RenderedOutput.new ""
  end

  visit Note do
    RenderedOutput.new ""
  end

  visit PrintStatement do
    expr = node.expression
    if expr.is_a?(AST::CallExpression) &&
       (id = expr.identifier) && id.is_a?(AST::IdentifierLiteral) &&
       (id.as(AST::IdentifierLiteral)).name == "super"
      return render_super(expr.as(AST::CallExpression))
    end

    result = env.evaluate(expr)

    # Real Ansible's own Jinja `Environment` sets a `finalize` callback
    # (`templar.py`: `'' if x is None else x`) that runs ONLY on a
    # template's own top-level `{{ }}` output, converting a bare `None`
    # result to nothing at all - verified directly against real
    # `ansible-playbook`, both for a `template:` file (`{{ extra_var
    # }}` on its own line renders as a blank line, not "None") and for
    # a plain `debug: msg:` substitution. Deliberately scoped to just
    # THIS call site (not `Finalizer#stringify(Nil)`/`env.stringify`
    # itself, both shared with `join`/`~`/`+`, which real Ansible's own
    # `join('|')` etc. verified DO still render a `None` item as
    # Python's real `"None"` - the finalize hook genuinely only fires
    # at the template's own outermost print boundary, not on every
    # internal filter/operator's own value-to-string conversion).
    RenderedOutput.new(result.raw.nil? ? "" : env.stringify(result))
  end

  # global function `super` needs access to this renderer and thus needs to be implemented
  # as a language feature.
  private def render_super(expression)
    block_context = env.context.block_context

    if block_context.nil?
      RenderedOutput.new("")
    else
      block_context = {name: block_context[:name], index: block_context[:index] + 1}
      block_chain = @blocks[block_context[:name]]

      if block_chain.size <= block_context[:index]
        raise RuntimeError.new("cannot call super block").at(expression)
      end

      super_block = block_chain[block_context[:index]]
      env.context.block_context = block_context

      self.render(super_block)
    end
  end

  private def resolve_block_stubs(output, block_names = Array(String).new)
    output.each_block do |placeholder|
      name = placeholder.name
      unless block_names.includes?(name)
        block_chain = @blocks[name]

        if block_chain.size > 0
          block = block_chain.first

          scope = env.context
          unless (original_scope = placeholder.scope).nil?
            scope = original_scope
          end

          env.with_scope(scope) do
            env.context.block_context = {name: name, index: 0}

            output = render(block)

            block_names << name
            resolve_block_stubs(output, block_names)

            block_names.pop

            env.context.block_context = nil
          end

          placeholder.resolve(output.value)
        end
      end

      placeholder.resolve("") unless placeholder.resolved?
    end
  end
end
