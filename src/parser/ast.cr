require "./character_stream"

# :nodoc:
module Crinja::AST
  class ASTNode
    property! location_start : Parser::StreamPosition?
    property! location_end : Parser::StreamPosition?

    # Set the location_start and location_end values to *location_start*
    def at(@location_start)
      @location_end = location_start
      self
    end

    # Set the location_start and location_end values
    def at(@location_start, @location_end)
      self
    end

    # Set the location_start and location_end values to these of *node*
    def at(node : ASTNode)
      at(node.location_start, node.location_end)
    end

    # Set the location to the start of *left* and the end of *right*
    def at(left : ASTNode, right : ASTNode)
      at(left.location_start, right.location_end)
    end
  end

  # Helper macro to describe ASTNodes in a nice and clean way
  macro template_node(name, *properties)
    class {{name.id}} < TemplateNode
      {% for property in properties %}
        property {{property.var}} : {{property.type}}
      {% end %}

      def initialize({{
                       properties.map do |field|
                         "@#{field.id}".id
                       end.splat
                     }})
      end
    end
  end

  abstract class ExpressionNode < ASTNode
  end

  abstract class TemplateNode < ASTNode
  end

  # Helper macro to describe ExpressionNodes in a nice and clean way
  macro expression_node(name, *properties)
    class {{name.id}} < ExpressionNode
      {% for property in properties %}
        property {{property.var}} : {{property.type}}
      {% end %}

      def initialize({{
                       properties.map do |field|
                         "@#{field.id}".id
                       end.splat
                     }})
      end
    end
  end

  expression_node Empty

  expression_node BinaryExpression,
    operator : String,
    left : ExpressionNode,
    right : ExpressionNode

  expression_node ComparisonExpression,
    operator : String,
    left : ExpressionNode,
    right : ExpressionNode

  # One `(op, expr)` pair of a chained comparison - the exact shape real
  # Jinja2's `nodes.Operand` has (see `ChainedComparisonExpression`).
  class ComparisonOperand
    property operator : String
    property expr : ExpressionNode

    def initialize(@operator, @expr)
    end
  end

  # Real Jinja2's own grammar (verified against installed Jinja2 3.1.6,
  # `jinja2/parser.py#parse_compare` and `jinja2/nodes.py#Compare`) does
  # NOT nest comparison operators left-to-right into a binary tree: a
  # Python-style chained comparison `a OP1 b OP2 c` is syntactic sugar
  # for an implicit `and` between each adjacent pair, so Jinja2's own
  # `nodes.Compare` AST node stores the left operand plus a LIST of
  # `nodes.Operand(op, expr)` pairs, deliberately to support N-ary
  # chaining exactly like Python's own comparison grammar. Nesting
  # `(a OP1 b) OP2 c` instead evaluates the intermediate boolean as the
  # left operand of OP2 - a genuine type error in both real Python and
  # this fork (`Crinja::TypeError: Cannot compare Bool value`), found
  # via the differential harness running real Jinja2 3.1.6's own
  # upstream test suite against this fork (`{{ 4 < 2 < 3 }}` -> `False`
  # in real Jinja2, since `4 < 2` short-circuits the chain, never a
  # `False < 3` comparison). Evaluation must short-circuit like real
  # Python too: stop at the first False pair, never evaluating later
  # operands past that point (verified: `{{ f() < g() < h() }}` with
  # `f() < g()` False does not call `h()`), with each middle operand
  # evaluated at most once even though it appears in two comparisons.
  expression_node ChainedComparisonExpression,
    first : ExpressionNode,
    operands : Array(ComparisonOperand)

  expression_node UnaryExpression,
    operator : String,
    right : ExpressionNode

  expression_node CallExpression,
    identifier : ExpressionNode,
    argumentlist : ExpressionList,
    keyword_arguments : Hash(IdentifierLiteral, ExpressionNode)

  expression_node FilterExpression,
    target : ExpressionNode,
    identifier : IdentifierLiteral,
    argumentlist : ExpressionList,
    keyword_arguments : Hash(IdentifierLiteral, ExpressionNode)

  expression_node TestExpression,
    target : ExpressionNode,
    identifier : IdentifierLiteral,
    argumentlist : ExpressionList,
    keyword_arguments : Hash(IdentifierLiteral, ExpressionNode)

  expression_node MemberExpression,
    identifier : ExpressionNode,
    member : IdentifierLiteral

  expression_node IndexExpression,
    identifier : ExpressionNode,
    argument : ExpressionNode

  # Python slice syntax - `expr[start:stop]`, `expr[start:stop:step]`,
  # any component optional (`expr[:22]`, `expr[2:]`, `expr[::-1]`).
  expression_node SliceExpression,
    receiver : ExpressionNode,
    slice_start : ExpressionNode?,
    slice_stop : ExpressionNode?,
    slice_step : ExpressionNode?

  # Inline ternary - `<true_value> if <condition> else <false_value>`.
  expression_node CondExpr,
    condition : ExpressionNode,
    true_value : ExpressionNode,
    false_value : ExpressionNode?

  expression_node ExpressionList,
    children : Array(ExpressionNode)

  expression_node IdentifierList,
    children : Array(ExpressionNode)

  expression_node NullLiteral

  expression_node IdentifierLiteral,
    name : String

  expression_node SplashOperator,
    right : ExpressionNode

  expression_node StringLiteral,
    value : String

  expression_node FloatLiteral,
    value : Float64

  expression_node IntegerLiteral,
    value : Int64

  expression_node BooleanLiteral,
    value : Bool

  expression_node ArrayLiteral,
    children : Array(ExpressionNode)

  expression_node TupleLiteral,
    children : Array(ExpressionNode)

  expression_node DictLiteral,
    children : Hash(ExpressionNode, ExpressionNode)

  expression_node ValuePlaceholder,
    value : Value

  template_node NodeList,
    children : Array(TemplateNode),
    block : Bool

  template_node PrintStatement,
    expression : ExpressionNode

  expression_node Expressions,
    children : Array(ExpressionNode)

  template_node TagNode,
    name : String,
    arguments : Array(Parser::Token),
    block : NodeList,
    end_tag : EndTagNode?

  template_node EndTagNode,
    name : String,
    arguments : Array(Parser::Token)

  template_node Note,
    note : String

  template_node FixedString,
    string : String,
    trim_left : Bool,
    left_is_block : Bool,
    trim_right : Bool,
    right_is_block : Bool,
    no_trim_left : Bool,
    no_lstrip_right : Bool
end
