# The evaluator traverses through an abstract syntax tree to evaluate all expressions and return a
# final value.

# :nodoc:
class Crinja::Evaluator
  # Creates a new evaluator for the environment *env*.
  def initialize(@env : Crinja)
  end

  # Evaluates an expression inside this evaluatores environment and returns a `Value` object.
  def value(expression) : Value
    Value.new evaluate(expression)
  end

  # Evaluates an expression inside this evaluatores environment and returns a `Value` object.
  def evaluate(expression)
    raise expression.inspect
  end

  # Evaluates an expression inside this evaluatores environment and returns a `Value` object.
  # Raises if the expression returns an `Undefined`.
  def value!(expression) : Value
    value = value(expression)

    if value.undefined?
      raise UndefinedError.new(name_for_expression(expression))
    end

    value
  end

  private macro visit(*node_types)
    # :nodoc:
    def evaluate(expression : {{
                                (node_types.map do |type|
                                  "AST::#{type.id}"
                                end).join(" | ").id
                              }})

      {{ yield }}
    rescue e : Crinja::Error
      # Add location info to runtime exception.
      e.at(expression) unless e.has_location?
      raise e
    end
  end

  visit Empty do
    raise "empty expression"
  end

  visit BinaryExpression, ComparisonExpression do
    op = @env.operators[expression.operator]
    left = evaluate expression.left

    case op
    when Operator::Logic
      op.value(@env, Value.new(left)) { value(expression.right) }
    when Operator::Binary
      right = evaluate expression.right
      op.value(@env, Value.new(left), Value.new(right))
    else
      raise "unreachable: invalid operator"
    end
  end

  visit UnaryExpression do
    op = @env.operators[expression.operator].as(Operator::Unary)
    right = evaluate expression.right
    op.value(@env, Value.new(right))
  end

  visit CallExpression do
    identifier = expression.identifier

    # First check if there is a literal function or macro registered (like "function" or "group.function").
    if callable_name = identifier_or_member(identifier)
      value = @env.resolve_callable(callable_name)
      if value.callable?
        callable = value.as_callable.as(Callable | Callable::Proc)
      end
    end

    if !callable && identifier.is_a?(AST::MemberExpression)
      callable = call_on_member(identifier)
      # raise UndefinedError.new(name_for_expression(expression.identifier)) unless callable
    end

    unless callable
      begin
        callable = @env.resolve_callable!(value(identifier))
      rescue e : TypeError
        e.at(expression)
        raise e
      end
    end

    # FIXME: Shouldn't be needed.
    callable = callable.not_nil! # ameba:disable Lint/NotNil

    argumentlist = evaluate(expression.argumentlist).as(Array(Value))

    keyword_arguments = Variables.new.tap do |args|
      expression.keyword_arguments.each do |(keyword, value_expression)|
        args[keyword.name] = value value_expression
      end
    end

    @env.execute_call(callable, argumentlist, keyword_arguments)
  end

  private def call_on_member(expression : AST::MemberExpression)
    identifier = evaluate expression.identifier
    member = expression.member.name
    Resolver.resolve_method(member, identifier)
  end

  private def identifier_or_member(identifier : AST::IdentifierLiteral)
    identifier.name
  end

  private def identifier_or_member(expr : AST::MemberExpression)
    identifier = identifier_or_member(expr.identifier)
    member = identifier_or_member(expr.member)

    "#{identifier}.#{member}" if identifier && member
  end

  private def identifier_or_member(expr)
    nil
  end

  visit FilterExpression do
    evaluate_filter @env.filters[expression.identifier.name], expression
  end

  visit TestExpression do
    evaluate_filter(@env.tests[expression.identifier.name], expression).truthy?
  end

  private def evaluate_filter(callable, expression)
    argumentlist = evaluate(expression.argumentlist)

    keyword_arguments = Variables.new.tap do |args|
      expression.keyword_arguments.each do |(keyword, value_expression)|
        args[keyword.name] = value value_expression
      end
    end

    target = value expression.target
    @env.execute_call callable, argumentlist, keyword_arguments, target: target
  end

  # Chained access on an already-undefined base (`foo.bar.baz`,
  # `hostvars[x]['ansible_facts']...`, when `foo`/`hostvars[x]` don't
  # exist) must NOT raise here - it must keep returning Undefined all the
  # way up, exactly like real Ansible's own Jinja environment (its
  # `AnsibleUndefined`/`hostvars` chaining). Real bug found benchmarking
  # robertdebock.haproxy (round 41): its own template's extremely common
  # `server.address | default(hostvars[server.name]['ansible_facts']
  # ['default_ipv4']['address'])` idiom - a `default()` guard whose
  # fallback branch is only ever evaluated as a Python/Jinja *expression*,
  # never actually rendered when the primary value (`server.address`) is
  # already defined. Real ansible-playbook never errors here even though
  # `hostvars['some-non-inventory-name']` doesn't exist, because Jinja
  # only raises `UndefinedError` when an Undefined value is actually
  # forced into a string/bool/etc - never merely by chaining `.attr`/
  # `[key]` off of one. Before this fix, `object = value! expression.
  # identifier` unconditionally raised as soon as ANY link in the chain
  # was undefined, regardless of whether the final result was ever going
  # to be used - which crashed a role's entire template render (not just
  # that one dict lookup) any time a `default()` fallback happened to
  # reference an undefined intermediate value, extremely common with
  # `hostvars[..]` guards. Terminal rendering of a genuinely-undefined
  # value still resolves to an empty string via `Undefined#to_s`
  # (`StrictUndefined#to_s` still raises) - unaffected by this change,
  # since that check happens at print/finalize time, not here.
  visit MemberExpression do
    object = value expression.identifier
    return object if object.undefined?

    member = expression.member.name

    begin
      value = Resolver.resolve_attribute(member, object)
    rescue e : UndefinedError
      raise UndefinedError.new(name_for_expression(expression))
    end

    if value.undefined?
      value.as_undefined.name = name_for_expression(expression)
    end

    value
  end

  visit IndexExpression do
    object = value expression.identifier
    return object if object.undefined?

    argument = evaluate expression.argument

    begin
      value = Resolver.resolve_attribute(argument, object)
    rescue e : UndefinedError
      raise UndefinedError.new(name_for_expression(expression))
    end

    # FIXME
    value = value.not_nil! # ameba:disable Lint/NotNil

    if value.undefined?
      value.as_undefined.name = name_for_expression(expression)
    end

    value
  end

  visit CondExpr do
    if Value.new(evaluate(expression.condition)).truthy?
      evaluate(expression.true_value)
    elsif false_value = expression.false_value
      evaluate(false_value)
    else
      Undefined.new("if-expression")
    end
  end

  visit SliceExpression do
    receiver_value = value(expression.receiver)

    start = if node = expression.slice_start
              value(node).to_i
            end
    stop = if node = expression.slice_stop
             value(node).to_i
           end
    step = if node = expression.slice_step
             value(node).to_i
           else
             1
           end

    case raw = receiver_value.raw
    when Array(Value)
      PythonSlice.slice(raw, start, stop, step)
    when String
      PythonSlice.slice(raw.chars, start, stop, step).join
    when SafeString
      PythonSlice.slice(raw.to_s.chars, start, stop, step).join
    else
      raise TypeError.new(receiver_value, "'#{raw.class}' object is not sliceable")
    end
  end

  # Generic fallback for any AST node type without its own overload below
  # (a `CallExpression`, a literal used directly as a receiver, ...) -
  # degrades to the node's own `to_s` rather than raising, so a
  # not-yet-specifically-formatted receiver produces a less precise but
  # still useful error message instead of crashing the whole evaluation.
  private def name_for_expression(expression)
    expression.to_s
  end

  private def name_for_expression(expression : AST::IdentifierLiteral)
    expression.name
  end

  private def name_for_expression(expression : AST::MemberExpression)
    "#{name_for_expression(expression.identifier)}.#{expression.member.name}"
  end

  private def name_for_expression(expression : AST::IndexExpression)
    "#{name_for_expression(expression.identifier)}[#{evaluate expression.argument}]"
  end

  visit ExpressionList do
    values = [] of Value
    expression.children.each do |child|
      if child.is_a?(AST::SplashOperator)
        splash_value = value(child.right)
        raw = splash_value.raw
        if raw.is_a?(Array(Value))
          values += raw
        else
          raise TypeError.new(splash_value, "#{child.right} needs to be an array for splash operator").at(expression)
        end
      else
        values << value child
      end
    end
    values
  end

  visit IdentifierList do
    raise "identifier list not implemented"
  end

  visit NullLiteral do
    nil
  end

  visit IdentifierLiteral do
    @env.resolve(expression.name)
  end

  visit SplashOperator do
    evaluate(expression.right)
  end

  visit StringLiteral, FloatLiteral, IntegerLiteral, BooleanLiteral do
    expression.value
  end

  visit ArrayLiteral, TupleLiteral do
    expression.children.map do |child|
      value(child).as(Value)
    end
  end

  visit DictLiteral do
    Dictionary.new.tap do |dict|
      expression.children.each do |(keyword, value)|
        dict[value keyword] = value value
      end
    end
  end

  visit ValuePlaceholder do
    expression.value
  end
end
