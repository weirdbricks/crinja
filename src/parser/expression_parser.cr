require "log"
require "./parser_helper"

class Crinja::Parser::ExpressionParser
  include ParserHelper

  getter config

  def initialize(stream, @config = Config.new)
    super(stream)
  end

  # Helper macro to prevent duplicate code for operator precedence parsing
  macro parse_operator(name, next_operator, *operators)
    private def parse_{{name.id}}
        left = parse_{{next_operator.id}}

        while true
          if current_token.kind == Kind::OPERATOR
            case current_token.value
            when {{
                   operators.map { |field|
                     "Symbol::OP_#{field.id}".id
                   }.splat
                 }}
              operator = current_token.value
              next_token
              right = parse_{{next_operator.id}}
              left = ({{ yield }}).at(left, right)
            else
              return left
            end
          else
            return left
          end
        end
      end
  end

  def parse(expected_end_token : Kind = Kind::EOF)
    case current_token.kind
    when expected_end_token
      # there is no content in this expression
      AST::Empty.new
    else
      expression = parse_expression

      if current_token.kind != expected_end_token
        raise "expression was not fully parsed: #{current_token}"
      end

      expression
    end
  end

  def parse_expressions(expected_end_token : Kind = Kind::EOF)
    expressions = Array(ExpressionNode).new
    while true
      case current_token.kind
      when expected_end_token
        return AST::Expressions.new(expressions).at(current_token.location)
      else
        list = parse_expression_list([expected_end_token])
        if list.children.size == 1
          expressions << list.children[0]
        else
          expressions << list
        end
      end
    end
  end

  def parse_expression
    parse_condexpr.tap do |expression|
      expression.location_end = current_token.location
    end
  end

  # Real Jinja2/Python's inline conditional (ternary) - `<expr1> if
  # <condition> else <expr2>` - mirrors real Jinja2's own
  # `parser.py#parse_condexpr`: right-associative (the else-branch may
  # itself be another ternary), and the `else` clause is optional
  # (yields Undefined when the condition is false and there's no else).
  private def parse_condexpr
    true_value = parse_logical_or

    if current_token.kind == Kind::IDENTIFIER && current_token.value == "if"
      next_token
      condition = parse_logical_or

      false_value = nil
      if current_token.kind == Kind::IDENTIFIER && current_token.value == "else"
        next_token
        false_value = parse_condexpr
      end

      true_value = AST::CondExpr.new(condition, true_value, false_value).at(true_value)
    end

    true_value
  end

  # `parse_expression` is the single shared entry point for every
  # expression-parsing context, including `{% for x in ITERABLE %}`'s own
  # `ITERABLE` slot - which collides with the for-tag's OWN, separate
  # grammar feature: `{% for x in y if COND %}`, an item filter clause
  # where COND may reference the loop variable itself. Without this
  # separate entry point, `parse_condexpr` sees the bare `if` right after
  # the iterable and greedily treats it as an inline ternary's own `if`,
  # evaluating COND once, eagerly, before the loop ever binds its item
  # variable at all. Real Jinja2 has this exact same potential ambiguity
  # in its own grammar and resolves it exactly this way: parse the
  # for-loop's iterable with ternary-parsing disabled, then explicitly
  # check for a literal `if` token afterward as the for-tag's own
  # separate clause (see `tag/for.cr`'s own `parse_for_tag`).
  def parse_expression_no_condexpr
    parse_logical_or.tap do |expression|
      expression.location_end = current_token.location
    end
  end

  parse_operator :logical_or, :logical_and, OR do
    AST::BinaryExpression.new operator, left, right
  end
  parse_operator :logical_and, :equal_not, AND do
    AST::BinaryExpression.new operator, left, right
  end

  # `NOT` deliberately excluded from this level's own operator set - see
  # the comparison level just below for why (a bare `not` is never a
  # valid binary comparator on its own; leaving it out here is what lets
  # the comparison level see it as part of a `not in` pair instead).
  # Real Jinja2 has all comparison operators (`==`, `!=`, `<`, `>`,
  # `<=`, `>=`, `in`, `not in`) at ONE precedence level, between `and`
  # and `~` (see `jinja2/parser.py#parse_compare`), so this fork's two
  # levels (`==`/`!=` above `<`/`>`) are merged here - which is also
  # what lets `a == b < c` chain instead of nesting.
  private def parse_equal_not
    left = parse_tilde

    operands = [] of AST::ComparisonOperand

    while true
      if current_token.kind == Kind::OPERATOR
        case current_token.value
        when Symbol::OP_EQUAL, Symbol::OP_NOT_EQUAL, Symbol::OP_LESS,
             Symbol::OP_GREATER, Symbol::OP_LESS_EQUAL, Symbol::OP_GREATER_EQUAL
          operator = current_token.value
          next_token
          right = parse_tilde
          operands << AST::ComparisonOperand.new(operator, right)
          next
        end
      end

      # `in` is lexed as a plain `Kind::IDENTIFIER` (only `and`/`or`/`not`
      # get their own `Kind::OPERATOR` token, see `base_lexer.cr`'s
      # `consume_name`), so it needs its own explicit check here rather
      # than fitting the `parse_operator` macro's operator-token-list shape.
      if current_token.kind == Kind::IDENTIFIER && current_token.value == "in"
        next_token
        right = parse_tilde
        operands << AST::ComparisonOperand.new("in", right)
        next
      end

      if current_token.kind == Kind::OPERATOR && current_token.value == Symbol::OP_NOT &&
         (peeked = peek_token?) && peeked.kind == Kind::IDENTIFIER && peeked.value == "in"
        next_token # consume "not"
        next_token # consume "in"
        right = parse_tilde
        operands << AST::ComparisonOperand.new("not in", right)
        next
      end

      break
    end

    # A single comparison keeps the exact same node as before this
    # change - the common single-comparison case is completely
    # unaffected (see `PATCHES.md`).
    if operands.empty?
      left
    elsif operands.size == 1
      AST::ComparisonExpression.new(operands[0].operator, left, operands[0].expr).at(left, operands[0].expr)
    else
      AST::ChainedComparisonExpression.new(left, operands).at(left, operands.last.expr)
    end
  end

  parse_operator :tilde, :add_sub, TILDE do
    AST::BinaryExpression.new operator, left, right
  end
  parse_operator :add_sub, :mult_div, PLUS, MINUS do
    AST::BinaryExpression.new operator, left, right
  end
  parse_operator :mult_div, :mod, TIMES, DIV, INT_DIV do
    AST::BinaryExpression.new operator, left, right
  end
  parse_operator :mod, :filter, MODULO do
    AST::BinaryExpression.new operator, left, right
  end

  private def parse_filter
    left = parse_unary_expression

    while true
      case current_token.kind
      when Kind::PIPE, Kind::TEST
        is_test = current_token.kind == Kind::TEST

        next_token

        not_location = nil
        if is_test
          if_token Kind::OPERATOR, "not" do
            not_location = current_token.location

            next_token
          end
        end

        identifier = if_token(Kind::NONE) do
          AST::IdentifierLiteral.new(current_token.value).at(current_token.location)
        end || if current_token.kind == Kind::BOOL && (current_token.value == "true" || current_token.value == "false")
          # Real Jinja2 registers `true`/`false` (and `none`) as TESTS,
          # so `x is true` / `x is not false` are valid templates there.
          # Crinja's grammar only accepted an IDENTIFIER in the test-name
          # slot, so the BOOL literal token crashed the render with
          # "Expected IDENTIFIER, got BOOL" before the (correctly
          # registered) boolean-identity tests could ever run. Accept the
          # literal token as the test NAME here - only in the position
          # directly after `is`/`|`, so plain `{{ true }}` literals are
          # unaffected.
          AST::IdentifierLiteral.new(current_token.value).at(current_token.location)
        end || assert_token(Kind::IDENTIFIER) do
          AST::IdentifierLiteral.new(current_token.value).at(current_token.location)
        end

        identifier.location_end = next_token.location

        # Real Ansible allows a filter (or test) to be referenced by its
        # fully-qualified collection name (`ansible.builtin.ternary`,
        # `community.general.something`), exactly like a module - it
        # resolves to the exact same filter registered under the bare
        # trailing name. Crinja's own grammar only ever expected a single
        # bare IDENTIFIER after `|`/`is` - any dotted filter name crashed
        # the whole template render ("Unexpected POINT") instead of
        # resolving to the same filter a bare `| ternary(...)` call
        # already works with. Found via robertdebock.vsftpd's own
        # `vsftpd.conf.j2`, which uses `| ansible.builtin.ternary(...)`
        # throughout for every yes/no setting.
        while current_token.kind == Kind::POINT
          next_token
          segment = assert_token(Kind::IDENTIFIER) { current_token.value }
          identifier = AST::IdentifierLiteral.new(segment).at(identifier.location_start)
          identifier.location_end = next_token.location
        end

        with_parenthesis = false
        if current_token.kind == Kind::LEFT_PAREN
          next_token
          with_parenthesis = true
        elsif config.liquid_compatibility_mode && current_token.kind == Kind::DICT_ASSIGN
          # django/liquid style format `val | filter: arg, arg`
          next_token
        end

        call = parse_call_expression identifier, with_parenthesis: with_parenthesis

        if is_test
          left = AST::TestExpression.new(left, identifier, call.argumentlist, call.keyword_arguments, call.dynamic_kwargs).at(left, call)

          if not_location
            left = AST::UnaryExpression.new("not", left).at(not_location)
          end
        else
          left = AST::FilterExpression.new(left, identifier, call.argumentlist, call.keyword_arguments, call.dynamic_kwargs).at(left, call)
        end
      else
        return left
      end
    end
  end

  # Real Jinja2/Python's unary `not` binds LOOSER than a comparison, so
  # `not a in b` means `not (a in b)`, and likewise `not a is b` means
  # `not (a is b)` - never `(not a) in/is b`. The two cases need separate
  # handling here because `in`/`not in` (`parse_equal_not`, above) and
  # `is`/`is not` TESTS (`parse_filter`, below - one level HIGHER in this
  # chain, since it calls `parse_unary_expression` for its own `left`)
  # sit at different points in the precedence chain relative to this
  # method.
  private def parse_unary_expression
    start_location = current_token.location

    if current_token.kind == Kind::OPERATOR
      case operator = current_token.value
      when Symbol::OP_PLUS, Symbol::OP_MINUS, Symbol::OP_NOT
        next_token
        value = parse_unary_expression

        if operator == Symbol::OP_NOT && current_token.kind == Kind::IDENTIFIER && current_token.value == "in"
          next_token
          right = parse_tilde
          value = AST::ComparisonExpression.new("in", value, right).at(value, right)
        end

        if operator == Symbol::OP_NOT && current_token.kind == Kind::TEST
          next_token

          not_location = nil
          if_token Kind::OPERATOR, "not" do
            not_location = current_token.location
            next_token
          end

          identifier = if_token(Kind::NONE) do
            AST::IdentifierLiteral.new(current_token.value).at(current_token.location)
          end || assert_token(Kind::IDENTIFIER) do
            AST::IdentifierLiteral.new(current_token.value).at(current_token.location)
          end
          identifier.location_end = next_token.location

          call = parse_call_expression identifier, with_parenthesis: false

          value = AST::TestExpression.new(value, identifier, call.argumentlist, call.keyword_arguments, call.dynamic_kwargs).at(value, call)
          value = AST::UnaryExpression.new("not", value).at(not_location, value.location_end) if not_location
        end

        return AST::UnaryExpression.new(operator, value).at(start_location, value.location_end)
      when Symbol::OP_TIMES
        # splash operator
        next_token
        value = parse_unary_expression
        return AST::SplashOperator.new(value).at(start_location, value.location_end)
      else
        # continue with next rule
      end
    end

    parse_pow
  end

  private def parse_pow
    left = parse_parenthesis_expression
    while true
      if (current_token.kind == Kind::OPERATOR) && (current_token.value == Parser::Symbol::OP_POW)
        operator = current_token.value
        next_token
        right = parse_unary_expression
        left = AST::BinaryExpression.new(operator, left, right).at(left, right)
      else
        return left
      end
    end
  end

  # Real Python/Jinja2 allow a postfix trailer - `(call)`, `[index or
  # slice]`, `.attr` - after ANY primary expression, not just a bare
  # identifier: `(a + b)[0]`, `(x if y else z).attr`. Shared by both
  # `parse_parenthesis_expression` (a parenthesized subexpression is a
  # primary too) and `parse_variable_expression` (the original, and far
  # more common, case) rather than duplicated between them.
  private def parse_postfix_trailers(expression : AST::ExpressionNode) : AST::ExpressionNode
    while true
      case current_token.kind
      when Kind::LEFT_PAREN
        next_token
        expression = parse_call_expression(expression)
      when Kind::LEFT_BRACKET
        next_token

        slice_start = current_token.kind == Kind::DICT_ASSIGN ? nil : parse_expression

        if current_token.kind == Kind::DICT_ASSIGN
          next_token

          slice_stop = (current_token.kind == Kind::DICT_ASSIGN || current_token.kind == Kind::RIGHT_BRACKET) ? nil : parse_expression

          slice_step = nil
          if current_token.kind == Kind::DICT_ASSIGN
            next_token
            slice_step = current_token.kind == Kind::RIGHT_BRACKET ? nil : parse_expression
          end

          end_location = current_token.location
          expect Kind::RIGHT_BRACKET
          expression = AST::SliceExpression.new(expression, slice_start, slice_stop, slice_step).at(expression.location_start, end_location)
        else
          end_location = current_token.location
          expect Kind::RIGHT_BRACKET
          expression = AST::IndexExpression.new(expression, slice_start.not_nil!).at(expression.location_start, end_location) # ameba:disable Lint/NotNil
        end
      when Kind::POINT
        next_token
        member = AST::Empty.new

        if current_token.kind == Kind::IDENTIFIER || current_token.kind == Kind::INTEGER
          member = AST::IdentifierLiteral.new(current_token.value).at(current_token.location)
          member.location_end = next_token.location
        else
          unexpected_token Kind::IDENTIFIER
        end

        if member.is_a? AST::IdentifierLiteral
          expression = AST::MemberExpression.new(expression, member).at(expression, member)
        end
      else
        return expression
      end
    end
  end

  private def parse_parenthesis_expression
    if_token Kind::LEFT_PAREN do
      # parse subexpression in parenthesis
      start_location = current_token.location

      next_token

      # An empty `()` is a valid empty-tuple literal: real Jinja2 parses
      # parens via `parse_tuple(explicit_parentheses=True)`
      # (jinja2/parser.py), whose `is_tuple_end` check breaks the loop on
      # `rparen` even with no args, and `explicit_parentheses` makes the
      # empty result a `nodes.Tuple` instead of failing - so `{{ () }}`
      # is the empty tuple (rendered `[]` under real ansible-playbook's
      # native-types finalization). This fork instead fed the bare
      # RIGHT_PAREN into `parse_expression` and raised `Unexpected
      # RIGHT_PAREN` (differential-harness finding). Only inside parens
      # is this legal: bare `{{ , }}`-style emptiness elsewhere still
      # fails, matching `explicit_parentheses=False`.
      if current_token.kind == Kind::RIGHT_PAREN
        end_location = current_token.location
        next_token
        return parse_postfix_trailers(AST::TupleLiteral.new([] of AST::ExpressionNode).at(start_location, end_location))
      end

      expression = parse_expression

      if current_token.kind == Kind::COMMA
        # we're in a tuple with only single parenthesis
        next_token

        exps = parse_expression_list([Kind::RIGHT_PAREN])
        entries = exps.children
        entries.unshift expression

        end_location = current_token.location

        expression = AST::TupleLiteral.new(entries).at(start_location, end_location)
      end
      expect Kind::RIGHT_PAREN

      return parse_postfix_trailers(expression)
    end

    parse_variable_expression
  end

  private def parse_variable_expression
    identifier = parse_literal
    identifier.location_end = current_token.location
    parse_postfix_trailers(identifier)
  end

  # A no-parens filter/test call's argument list has no way to stop at a
  # reserved keyword - `in`/`if`/`else`/`and`/`or`/`recursive` aren't
  # their own token `Kind` (only `and`/`or`/`not` get `Kind::OPERATOR`,
  # see `base_lexer.cr`), so without this check a no-parens call greedily
  # swallows the next keyword as an implicit argument
  # (`x | string in [...]` corrupted by `string`'s own zero-arg call
  # eating `in`; `x if y is sometest else z` corrupted by `sometest`'s
  # own zero-arg call eating `else`, breaking the surrounding inline
  # ternary entirely). Real Jinja2's own grammar only ever allows a
  # SINGLE bare argument for a no-parens call (`is divisibleby 3`, `is
  # sameas other`) - stopping BEFORE parsing any argument at all when the
  # very next token is one of these reserved words at least fixes the
  # zero-argument case (the overwhelmingly common one) without
  # reproducing that full one-argument grammar here.
  NO_PARENS_CALL_STOP_WORDS = {"in", "if", "else", "and", "or", "recursive"}

  private def parse_call_expression(identifier, with_parenthesis = true)
    if with_parenthesis
      parse_call_args(identifier)
    else
      parse_call_arguments_no_parenthesis(identifier)
    end
  end

  # Real Jinja2's `parse_call_args` (jinja2/parser.py 3.1.6), the grammar
  # for every parenthesized call: function calls, filter calls and test
  # calls all share it. Its argument loop recognizes - besides plain
  # positional args and `name=value` kwargs - a `*expr` SPLAT (token
  # "mul") expanding into positional args and a `**expr` SPLAT (token
  # "pow") expanding into keyword args, each allowed AT MOST ONCE
  # (`ensure(dyn_args is None ...)` / `ensure(dyn_kwargs is None)` -
  # real Jinja2 rejects `f(*a, *b)`, `f(**a, **b)`, `f(**a, *b)` with
  # "invalid syntax for function call expression"). The remaining
  # ordering rules encode Python's own call grammar: a plain positional
  # arg is only allowed while no splat and no kwargs have been seen
  # (`ensure(dyn_args is None and dyn_kwargs is None and not kwargs)`),
  # a `name=value` kwarg only while no `**` splat has been seen, and a
  # `*` splat only while no `**` splat has been seen - so `f('a', *['b'],
  # c='d', **{'g': 'h'})` parses but `f(*['a'], 'b')`, `f(c='d', 'e')`
  # and `f(**{'k': 1}, j='2')` all fail (all verified live against real
  # Jinja2 3.1.6). Because of those rules a `*expr` splat is always the
  # LAST positional argument, so it is kept inline as a `SplashOperator`
  # child of the argument list (whose evaluator expands it in place,
  # giving real Jinja2's codegen order: plain args, then `*dyn_args`);
  # the `**expr` splat is stored in the call node's `dynamic_kwargs`
  # slot (the AST equivalent of `nodes.Call.dyn_kwargs`). Trailing
  # commas are legal (real Jinja2's own "support for trailing comma"
  # re-test of `rparen` right after `expect("comma")`).
  #
  # This fork previously reused the generic expression-list machinery
  # for call arguments, which has no notion of splats: the keyword
  # list's own `parse_literal` loop raised `Unexpected OPERATOR` at the
  # `*` of `{{ foo('a', c='d', e='f', *['b'], **{'g': 'h'}) }}` (the
  # confirmed differential-harness finding against real Jinja2 3.1.6's
  # own upstream test suite - real Jinja2 renders it as `abdfh`).
  private def parse_call_args(identifier)
    args = [] of AST::ExpressionNode
    kwargs = Hash(AST::IdentifierLiteral, AST::ExpressionNode).new
    dynamic_kwargs = nil

    start_location = current_token.location
    require_comma = false

    while current_token.kind != Kind::RIGHT_PAREN
      if require_comma
        expect Kind::COMMA

        # support for trailing comma
        break if current_token.kind == Kind::RIGHT_PAREN

        require_comma = false
      end

      if current_token.kind == Kind::OPERATOR && current_token.value == Symbol::OP_TIMES
        if dynamic_kwargs || args.any?(&.is_a?(AST::SplashOperator))
          raise "invalid syntax for function call expression"
        end
        splat_location = current_token.location
        next_token
        value = parse_expression
        args << AST::SplashOperator.new(value).at(splat_location, value.location_end)
      elsif current_token.kind == Kind::OPERATOR && current_token.value == Symbol::OP_POW
        if dynamic_kwargs
          raise "invalid syntax for function call expression"
        end
        next_token
        dynamic_kwargs = parse_expression
      else
        expression = parse_expression

        if current_token.kind == Kind::KW_ASSIGN
          if dynamic_kwargs
            raise "invalid syntax for function call expression"
          end
          keyword = expression.as?(AST::IdentifierLiteral)
          unless keyword
            raise "invalid syntax for function call expression"
          end
          next_token
          kwargs[keyword] = parse_expression
        else
          if dynamic_kwargs || args.any?(&.is_a?(AST::SplashOperator)) || !kwargs.empty?
            raise "invalid syntax for function call expression"
          end
          args << expression
        end
      end

      require_comma = true
    end

    end_location = current_token.location
    expect Kind::RIGHT_PAREN

    AST::CallExpression.new(identifier, AST::ExpressionList.new(args).at(start_location, end_location), kwargs, dynamic_kwargs).at(identifier.location_start, end_location)
  end

  private def parse_call_arguments_no_parenthesis(identifier)
    # Real Jinja2's grammar for a no-parenthesis filter/test
    # call (`is divisibleby 3`, `x | string`) takes at most
    # ONE bare argument, so the argument list must also end
    # at a COMMA: filters bind tighter than any binary
    # operator, so an argument like `'a' + port | string, ''`
    # (tuple element or call argument) legitimately places a
    # COMMA directly after the filter name. Without COMMA in
    # this list, parse_expression_list tried to parse the
    # COMMA itself as an implicit argument ("Unexpected
    # COMMA"). Found via rolehippie.nullmailer's
    # `remotes.j2` (round 811337 of krikri-playbook's
    # real-host benchmark).
    end_tokens = [Kind::EOF, Kind::EXPR_END, Kind::TAG_END, Kind::OPERATOR, Kind::PIPE, Kind::TEST, Kind::RIGHT_BRACKET, Kind::RIGHT_PAREN, Kind::COMMA]

    args = if current_token.kind == Kind::IDENTIFIER && NO_PARENS_CALL_STOP_WORDS.includes?(current_token.value)
             AST::ExpressionList.new([] of AST::ExpressionNode).at(current_token.location)
           else
             parse_expression_list(end_tokens)
           end

    keyword = nil
    if_token Kind::KW_ASSIGN do
      keyword = args.children.pop
    end

    kwargs = if keyword
               parse_keyword_list(end_tokens, keyword: keyword)
             else
               Hash(AST::IdentifierLiteral, AST::ExpressionNode).new
             end

    end_location = current_token.location
    AST::CallExpression.new(identifier, args, kwargs).at(identifier.location_start, end_location)
  end

  private def parse_literal
    case current_token.kind
    when Kind::LEFT_PAREN
      next_token
      node = parse_expression
      expect Kind::RIGHT_PAREN
    when Kind::IDENTIFIER
      node = parse_identifier
    when Kind::INTEGER
      # `prefix: true` so the `0x`/`0X`/`0o`/`0O`/`0b`/`0B` integer
      # literals real Jinja2's `integer_re` accepts (jinja2/lexer.py)
      # convert the same way Python's own `int(text, 0)` does -
      # `{{ 0x123abc }}` is 1194684 (differential-harness finding).
      # Same Int64 value type and same overflow behavior as plain
      # decimal literals.
      node = AST::IntegerLiteral.new(current_token.value.to_i64(prefix: true)).at(current_token.location)
      next_token
    when Kind::FLOAT
      node = AST::FloatLiteral.new(current_token.value.to_f64).at(current_token.location)
      next_token
    when Kind::STRING
      # Real Jinja2 merges adjacent string literals into one string:
      # `parse_primary` (jinja2/parser.py, 3.1.6) loops on
      # `self.stream.current.type == "string"` collecting consecutive
      # STRING tokens into a single `nodes.Const("".join(buf))`, Python's
      # own adjacent-string-literal syntax (`"foo" "bar"` == `"foobar"`).
      # Only bare adjacency counts: any non-string token (an operator,
      # comma, expression end) breaks the loop, so `{{ "foo" ~ "bar" }}`
      # stays an operator concat and `{{ "foo" }} {{ "bar" }}` stays two
      # separate print statements. Found via the differential harness
      # running real Jinja2 3.1.6's upstream suite against this fork
      # (this fork raised `expression was not fully parsed` on the
      # second string); verified identical - including inside parens
      # and list literals - in a real ansible-playbook 2.19 run.
      values = [current_token.value]
      end_location = current_token.location
      while (peek = peek_token?) && peek.kind == Kind::STRING
        next_token
        values << current_token.value
        end_location = current_token.location
      end
      node = AST::StringLiteral.new(values.join).at(current_token.location, end_location)
      next_token
    when Kind::BOOL
      node = AST::BooleanLiteral.new(current_token.value.downcase == "true").at(current_token.location)
      next_token
    when Kind::NONE
      node = AST::NullLiteral.new.at(current_token.location)
      next_token
    when Kind::LEFT_BRACKET
      node = parse_array_literal
    when Kind::LEFT_CURLY
      node = parse_dict_literal
    else
      unexpected_token value: "an expression"
    end

    node
  end

  private def parse_identifier
    node = AST::IdentifierLiteral.new(current_token.value).at(current_token.location)
    next_token
    node
  end

  private def parse_expression_list(end_tokens : Array(Kind))
    exps = [] of AST::ExpressionNode
    start_location = current_token.location

    should_read = !end_tokens.includes? current_token.kind
    while should_read
      should_read = false

      exps << parse_expression

      if current_token.kind == Kind::COMMA
        next_token
        # A trailing comma before the closing bracket is legal and ignored
        # in EVERY bracketed collection literal real Jinja2 parses:
        # `parse_tuple` loops on `if self.is_tuple_end(...): break` right
        # after consuming a comma, `parse_list`/`parse_dict` re-test
        # `rbracket`/`rbrace` after `expect("comma")`, and
        # `parse_call_args` even carries an explicit "support for trailing
        # comma" comment (jinja2/parser.py 3.1.6). This fork raised
        # `Unexpected RIGHT_PAREN` on `{{ (1, 2,) }}`, `{{ [1, 2,] }}` and
        # `{{ {1: 2,} }}` because it unconditionally tried to parse another
        # expression after the comma (differential-harness finding against
        # real Jinja2 3.1.6's own upstream test suite).
        should_read = !end_tokens.includes?(current_token.kind)
      end
    end

    end_location = exps.last?.try(&.location_end) || start_location

    AST::ExpressionList.new(exps).at(start_location, end_location)
  end

  def parse_keyword_list(end_tokens : Array(Kind) = [Kind::EOF], keyword_separator_token : Kind = Kind::KW_ASSIGN, keyword = nil)
    hash = Hash(AST::IdentifierLiteral, AST::ExpressionNode).new

    should_read = !end_tokens.includes? current_token.kind
    while should_read
      should_read = false

      if keyword.nil?
        keyword = parse_literal
      end

      if keyword.is_a?(AST::IdentifierLiteral)
        expect keyword_separator_token

        value = parse_expression

        hash[keyword] = value
      else
        unexpected_token Kind::IDENTIFIER
      end

      keyword = nil

      if current_token.kind == Kind::COMMA
        should_read = true
        next_token
      end
    end

    hash
  end

  private def parse_array_literal
    start_location = current_token.location

    expect Kind::LEFT_BRACKET
    exps = parse_expression_list([Kind::RIGHT_BRACKET])

    end_location = current_token.location
    expect Kind::RIGHT_BRACKET
    AST::ArrayLiteral.new(exps.children).at(start_location, end_location)
  end

  private def parse_dict_literal
    start_location = current_token.location

    expect Kind::LEFT_CURLY

    hash = Hash(AST::ExpressionNode, AST::ExpressionNode).new

    should_read = current_token.kind != Kind::RIGHT_CURLY

    while should_read
      should_read = false

      key = parse_expression
      expect Kind::DICT_ASSIGN
      value = parse_expression

      hash[key] = value

      if current_token.kind == Kind::COMMA
        next_token
        # Same trailing-comma tolerance as `parse_expression_list` above:
        # real Jinja2's `parse_dict` breaks on `rbrace` right after a
        # comma, so `{{ {1: 2,} }}` is a valid 1-pair dict, not a syntax
        # error.
        should_read = current_token.kind != Kind::RIGHT_CURLY
      end
    end

    end_location = current_token.location

    expect Kind::RIGHT_CURLY

    AST::DictLiteral.new(hash).at(start_location, end_location)
  end

  private def parse_identifier_list
    list = [] of AST::IdentifierLiteral

    while true
      list << parse_identifier

      break if current_token.kind != Kind::COMMA
      next_token
    end

    list
  end
end
