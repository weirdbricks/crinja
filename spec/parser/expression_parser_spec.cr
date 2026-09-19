require "../spec_helper.cr"

describe Crinja::Parser::ExpressionParser do
  it "parses string literals" do
    expression = parse_expression(%( "foo"))
    expression.should be_a(Crinja::AST::StringLiteral)
  end

  it "parses binary expressions" do
    expression = parse_expression(%(1 + 2))
    expression.should be_a(Crinja::AST::BinaryExpression)
    Crinja.new.evaluate(expression).should eq Crinja::Value.new(3)
  end

  it "parses member operator" do
    expression = parse_expression(%(foo.bar))
    expression.should be_a(Crinja::AST::MemberExpression)
  end

  it "parses single parenthesis tuple" do
    expression = parse_expression(%(("foo", 1)))
    expression.should be_a(Crinja::AST::TupleLiteral)
  end

  # Real Jinja2 parses parens via `parse_tuple(explicit_parentheses=True)`
  # (jinja2/parser.py), so an empty `()` is a valid empty-tuple literal:
  # `is_tuple_end` breaks the arg loop on `rparen` and `explicit_parentheses`
  # turns the empty arg list into a `nodes.Tuple` instead of the
  # "Expected an expression" failure bare emptiness gets. This fork raised
  # `Unexpected RIGHT_PAREN` instead (differential-harness finding against
  # real Jinja2 3.1.6's own upstream test suite).
  it "parses empty tuple literal" do
    expression = parse_expression("()")
    expression.should be_a(Crinja::AST::TupleLiteral)
    expression.as(Crinja::AST::TupleLiteral).children.size.should eq(0)
  end

  # Python/Jinja2's one-element tuple spelling is a MANDATORY trailing
  # comma: `(1,)` is the 1-tuple, while `(1)` without it is just a
  # parenthesized expression (real Jinja2's `parse_tuple` only sets
  # `is_tuple` when it sees a comma). Both parse, but to different nodes.
  it "parses single-element tuple literal" do
    expression = parse_expression("(1,)")
    expression.should be_a(Crinja::AST::TupleLiteral)
    expression.as(Crinja::AST::TupleLiteral).children.size.should eq(1)
  end

  it "parses parenthesized single expression as expression, not tuple" do
    expression = parse_expression("(1)")
    expression.should be_a(Crinja::AST::IntegerLiteral)
  end

  # A trailing comma before the closing bracket is legal and ignored in
  # every bracketed collection literal real Jinja2 parses: `parse_tuple`
  # loops on `is_tuple_end` after consuming a comma, `parse_list` and
  # `parse_dict` re-test the closing bracket after `expect("comma")`, and
  # `parse_call_args` carries an explicit "support for trailing comma"
  # comment (jinja2/parser.py 3.1.6). This fork raised `Unexpected
  # RIGHT_PAREN` on all of these (differential-harness finding).
  it "parses trailing comma in tuple literal" do
    expression = parse_expression("(1, 2,)")
    expression.should be_a(Crinja::AST::TupleLiteral)
    expression.as(Crinja::AST::TupleLiteral).children.size.should eq(2)
  end

  it "parses trailing comma in list literal" do
    expression = parse_expression("[1, 2,]")
    expression.should be_a(Crinja::AST::ArrayLiteral)
    expression.as(Crinja::AST::ArrayLiteral).children.size.should eq(2)
  end

  it "parses trailing comma in dict literal" do
    expression = parse_expression("{1: 2,}")
    expression.should be_a(Crinja::AST::DictLiteral)
  end

  # Real Jinja2 binds `|` tighter than binary operators, so a filter
  # call often lands directly in front of the COMMA that separates
  # tuple elements or call arguments (`'a' + port | string, ''`).
  # Real Jinja2's no-parenthesis call grammar takes AT MOST ONE bare
  # argument, so such a filter's argument list must end at the COMMA
  # instead of trying to parse the COMMA itself as an argument.
  # (Found via rolehippie.nullmailer's `remotes.j2`, round 811337 of
  # krikri-playbook's real-host benchmark.)
  it "stops a no-parenthesis filter call at a COMMA (tuple)" do
    expression = parse_expression(%(("a" | upper, "z")))
    expression.should be_a(Crinja::AST::TupleLiteral)
  end

  it "stops a no-parenthesis filter call at a COMMA (call arguments)" do
    expression = parse_expression(%(range(1 + 2 | abs, 4)))
    expression.should be_a(Crinja::AST::CallExpression)
  end

  it "parses integer as identifier member" do
    expression = parse_expression(%(foo.1))
    expression.should be_a(Crinja::AST::MemberExpression)
  end

  it "parse double parenthesis" do
    expression = parse_expression("dict(foo=(1, 2))")
    expression.should be_a(Crinja::AST::CallExpression)
  end

  it "parses expression as named argument value" do
    expression = parse_expression("self(n=n-1)")
    expression.should be_a(Crinja::AST::CallExpression)
  end

  it "parses integer as member access" do
    expression = parse_expression("foo.1.bar")
    expression.should be_a(Crinja::AST::MemberExpression)
  end

  # Django-style numeric attribute access: real Jinja2's `parse_subscript`
  # (jinja2/parser.py 3.1.6) accepts an INTEGER token directly after a
  # member-access dot and turns it into a Getitem index (the same syntax
  # Django templates use for list indexing), and its float_re's `(?<!\.)`
  # lookbehind (jinja2/lexer.py) keeps a following `.digit` from merging
  # into one float - so `[[1]].0.0` is two chained index accesses, both
  # real Jinja2 3.1.6 and a real ansible-playbook run render it `1`. This
  # fork used to lex the second `.0` as FLOAT "0.0" and fail with
  # `Expected IDENTIFIER, got FLOAT` (differential-harness finding).
  it "parses Django-style dot index into a list" do
    expression = parse_expression("[1, 2, 3].0")
    expression.should be_a(Crinja::AST::MemberExpression)
    expression.as(Crinja::AST::MemberExpression).member.name.should eq("0")
  end

  it "parses chained Django-style dot indexes" do
    expression = parse_expression("[[1]].0.0")
    expression.should be_a(Crinja::AST::MemberExpression)
    inner = expression.as(Crinja::AST::MemberExpression).identifier
    inner.should be_a(Crinja::AST::MemberExpression)
    inner.as(Crinja::AST::MemberExpression).member.name.should eq("0")
    expression.as(Crinja::AST::MemberExpression).member.name.should eq("0")
  end

  it "parses escaped backslashes" do
    expression = parse_expression(%q("foo\\bar"))
    expression.should be_a(Crinja::AST::StringLiteral)
    expression.as(Crinja::AST::StringLiteral).value.should eq %q(foo\bar)
  end

  it "parses escaped newlines" do
    expression = parse_expression(%q("foo\nbar"))
    expression.should be_a(Crinja::AST::StringLiteral)
    expression.as(Crinja::AST::StringLiteral).value.should eq "foo\nbar"
  end

  it "parses escaped quotes" do
    expression = parse_expression(%q("\"foo\"\'bar\'"))
    expression.should be_a(Crinja::AST::StringLiteral)
    expression.as(Crinja::AST::StringLiteral).value.should eq %q("foo"'bar')
  end

  # Real Jinja2's parse_primary merges adjacent string literals into a
  # single string (Python's adjacent-string-literal syntax); all cases
  # below verified against real Jinja2 3.1.6 and a real
  # ansible-playbook 2.19 run.
  it "merges adjacent string literals into one" do
    expression = parse_expression(%q("foo" "bar"))
    expression.should be_a(Crinja::AST::StringLiteral)
    expression.as(Crinja::AST::StringLiteral).value.should eq "foobar"
  end

  it "merges three adjacent string literals into one" do
    expression = parse_expression(%q("foo" "bar" "baz"))
    expression.should be_a(Crinja::AST::StringLiteral)
    expression.as(Crinja::AST::StringLiteral).value.should eq "foobarbaz"
  end

  it "merges adjacent string literals with mixed quote styles" do
    expression = parse_expression(%q("foo" 'bar'))
    expression.should be_a(Crinja::AST::StringLiteral)
    expression.as(Crinja::AST::StringLiteral).value.should eq "foobar"
  end

  it "parses a single string literal unaffected" do
    expression = parse_expression(%q("foo"))
    expression.should be_a(Crinja::AST::StringLiteral)
    expression.as(Crinja::AST::StringLiteral).value.should eq "foo"
  end

  it "does not merge string literals separated by an operator" do
    expression = parse_expression(%q("foo" ~ "bar"))
    expression.should be_a(Crinja::AST::BinaryExpression)
    expression.as(Crinja::AST::BinaryExpression).operator.should eq "~"
  end
end
