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
      return AST::Empty.new
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
  # `parse_less_greater`'s own comment just below for why (a bare `not`
  # is never a valid binary comparator on its own; leaving it out here is
  # what lets `parse_less_greater` see it as part of a `not in` pair
  # instead).
  private def parse_equal_not
    left = parse_less_greater

    while true
      if current_token.kind == Kind::OPERATOR
        case current_token.value
        when Symbol::OP_EQUAL, Symbol::OP_NOT_EQUAL
          operator = current_token.value
          next_token
          right = parse_less_greater
          left = AST::ComparisonExpression.new(operator, left, right).at(left, right)
        else
          return left
        end
      else
        return left
      end
    end
  end

  # `in`/`not in` sit at the same "comparison" precedence level as
  # `==`/`!=`/`<`/`>` in real Jinja2. `in` is lexed as a plain
  # `Kind::IDENTIFIER` (only `and`/`or`/`not` get their own
  # `Kind::OPERATOR` token, see `base_lexer.cr`'s `consume_name`), so it
  # needs its own explicit check here rather than fitting the
  # `parse_operator` macro's operator-token-list shape.
  private def parse_less_greater
    left = parse_tilde

    while true
      if current_token.kind == Kind::OPERATOR
        case current_token.value
        when Symbol::OP_LESS, Symbol::OP_GREATER, Symbol::OP_LESS_EQUAL, Symbol::OP_GREATER_EQUAL
          operator = current_token.value
          next_token
          right = parse_tilde
          left = AST::ComparisonExpression.new(operator, left, right).at(left, right)
          next
        end
      end

      if current_token.kind == Kind::IDENTIFIER && current_token.value == "in"
        next_token
        right = parse_tilde
        left = AST::ComparisonExpression.new("in", left, right).at(left, right)
        next
      end

      if current_token.kind == Kind::OPERATOR && current_token.value == Symbol::OP_NOT &&
         (peeked = peek_token?) && peeked.kind == Kind::IDENTIFIER && peeked.value == "in"
        next_token # consume "not"
        next_token # consume "in"
        right = parse_tilde
        left = AST::ComparisonExpression.new("not in", left, right).at(left, right)
        next
      end

      return left
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
        end || assert_token(Kind::IDENTIFIER) do
          AST::IdentifierLiteral.new(current_token.value).at(current_token.location)
        end

        identifier.location_end = next_token.location

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
          left = AST::TestExpression.new(left, identifier, call.argumentlist, call.keyword_arguments).at(left, call)

          if not_location
            left = AST::UnaryExpression.new("not", left).at(not_location)
          end
        else
          left = AST::FilterExpression.new(left, identifier, call.argumentlist, call.keyword_arguments).at(left, call)
        end
      else
        return left
      end
    end
  end

  # Real Jinja2/Python's unary `not` binds LOOSER than a comparison, so
  # `not a in b` means `not (a in b)`, and likewise `not a is b` means
  # `not (a is b)` - never `(not a) in/is b`. The two cases need separate
  # handling here because `in`/`not in` (`parse_less_greater`, above) and
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

          value = AST::TestExpression.new(value, identifier, call.argumentlist, call.keyword_arguments).at(value, call)
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
          expression = AST::IndexExpression.new(expression, slice_start.not_nil!).at(expression.location_start, end_location)
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
    end_tokens = if with_parenthesis
                   [Kind::RIGHT_PAREN]
                 else
                   [Kind::EOF, Kind::EXPR_END, Kind::TAG_END, Kind::OPERATOR, Kind::PIPE, Kind::TEST, Kind::RIGHT_BRACKET, Kind::RIGHT_PAREN]
                 end

    args = if !with_parenthesis && current_token.kind == Kind::IDENTIFIER && NO_PARENS_CALL_STOP_WORDS.includes?(current_token.value)
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
    expect Kind::RIGHT_PAREN if with_parenthesis
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
      node = AST::IntegerLiteral.new(current_token.value.to_i64).at(current_token.location)
      next_token
    when Kind::FLOAT
      node = AST::FloatLiteral.new(current_token.value.to_f64).at(current_token.location)
      next_token
    when Kind::STRING
      node = AST::StringLiteral.new(current_token.value).at(current_token.location)
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

    return node
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
        should_read = true
        next_token
      end
    end

    end_location = exps.last?.try(&.location_end) || start_location

    return AST::ExpressionList.new(exps).at(start_location, end_location)
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
    return AST::ArrayLiteral.new(exps.children).at(start_location, end_location)
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
        should_read = true
        next_token
      end
    end

    end_location = current_token.location

    expect Kind::RIGHT_CURLY

    return AST::DictLiteral.new(hash).at(start_location, end_location)
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
