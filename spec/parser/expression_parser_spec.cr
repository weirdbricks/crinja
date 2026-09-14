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
end
