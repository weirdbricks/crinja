require "../spec_helper"

describe Crinja::Parser do
  it "parses a simple template string" do
    config = Crinja::Config.new
    lexer = Crinja::Parser::TemplateLexer.new config, %(Hello World)
    token = lexer.next_token
    token.kind.should eq(Kind::FIXED)
    token.value.should eq("Hello World")
  end

  it "parses a template string with simple expression" do
    config = Crinja::Config.new
    lexer = Crinja::Parser::TemplateLexer.new config, %(Hello {{ name }})
    token = lexer.next_token
    token.kind.should eq(Kind::FIXED)
    token.value.should eq("Hello ")
  end

  it "tokenizes simple template" do
    config = Crinja::Config.new
    lexer = Crinja::Parser::TemplateLexer.new config, %(Hello {{ name | uppercase }}!)

    tokens = lexer.tokenize

    expected = [
      {Kind::FIXED, "Hello "},
      {Kind::EXPR_START, "{{"},
      {Kind::IDENTIFIER, "name"},
      {Kind::PIPE, "|"},
      {Kind::IDENTIFIER, "uppercase"},
      {Kind::EXPR_END, "}}"},
      {Kind::FIXED, "!"},
      {Kind::EOF, ""},
    ]

    tokens.map do |token|
      {token.kind, token.value}
    end.should eq(expected)
  end

  it "tokenizes template with variable member and filters" do
    config = Crinja::Config.new
    lexer = Crinja::Parser::TemplateLexer.new config, %(Hello, {{ user.name | lower | upper }}!)

    tokens = lexer.tokenize

    expected = [
      {Kind::FIXED, "Hello, "},
      {Kind::EXPR_START, "{{"},
      {Kind::IDENTIFIER, "user"},
      {Kind::POINT, "."},
      {Kind::IDENTIFIER, "name"},
      {Kind::PIPE, "|"},
      {Kind::IDENTIFIER, "lower"},
      {Kind::PIPE, "|"},
      {Kind::IDENTIFIER, "upper"},
      {Kind::EXPR_END, "}}"},
      {Kind::FIXED, "!"},
      {Kind::EOF, ""},
    ]

    tokens.map do |token|
      {token.kind, token.value}
    end.should eq(expected)
  end

  it "recognizes whitespace trim" do
    lexer = Crinja::Parser::TemplateLexer.new Crinja::Config.new, %( {%- if true -%}\n {{ "Hallo" }}\n  {%- endif %})

    expected = [
      {Kind::FIXED, " "},
      {Kind::TAG_START, "{%-"},
      {Kind::IDENTIFIER, "if"},
      {Kind::BOOL, "true"},
      {Kind::TAG_END, "-%}"},
      {Kind::FIXED, "\n "},
      {Kind::EXPR_START, "{{"},
      {Kind::STRING, "Hallo"},
      {Kind::EXPR_END, "}}"},
      {Kind::FIXED, "\n  "},
      {Kind::TAG_START, "{%-"},
      {Kind::IDENTIFIER, "endif"},
      {Kind::TAG_END, "%}"},
      {Kind::EOF, ""},
    ]

    lexer.tokenize.map do |token|
      {token.kind, token.value}
    end.should eq(expected)
  end

  it "tokenizes member access with single char name" do
    lexer = Crinja::Parser::TemplateLexer.new Crinja::Config.new, %({{ item.a }})

    expected = [
      {Kind::EXPR_START, "{{"},
      {Kind::IDENTIFIER, "item"},
      {Kind::POINT, "."},
      {Kind::IDENTIFIER, "a"},
      {Kind::EXPR_END, "}}"},
      {Kind::EOF, ""},
    ]

    lexer.tokenize.map do |token|
      {token.kind, token.value}
    end.should eq(expected)
  end

  it "tokenizes member access with single char name" do
    lexer = Crinja::Parser::ExpressionLexer.new Crinja::Config.new, %(foo(n=n-1))

    expected = [
      {Kind::IDENTIFIER, "foo"},
      {Kind::LEFT_PAREN, "("},
      {Kind::IDENTIFIER, "n"},
      {Kind::KW_ASSIGN, "="},
      {Kind::IDENTIFIER, "n"},
      {Kind::OPERATOR, "-"},
      {Kind::INTEGER, "1"},
      {Kind::RIGHT_PAREN, ")"},
      {Kind::EOF, ""},
    ]

    lexer.tokenize.map do |token|
      {token.kind, token.value}
    end.should eq(expected)
  end

  # Real Jinja2's float_re (jinja2/lexer.py 3.1.6) carries a `(?<!\.)`
  # lookbehind: a number whose raw text starts right after a `.` can never
  # lex as a float, so `].0.0` tokenizes as `.` `0` `.` `0` (verified
  # against a real Environment.lex) and `[[1]].0.0` is two chained
  # Django-style index accesses, not a member dot followed by float
  # `0.0`. This lexer used to merge the second `.0` into one FLOAT
  # "0.0" (differential-harness finding); ordinary `1.5` keeps its
  # fractional part because its digits don't start right after a dot.
  it "tokenizes number after member dot as integer, never float" do
    lexer = Crinja::Parser::ExpressionLexer.new Crinja::Config.new, %([[1]].0.0)

    expected = [
      {Kind::LEFT_BRACKET, "["},
      {Kind::LEFT_BRACKET, "["},
      {Kind::INTEGER, "1"},
      {Kind::RIGHT_BRACKET, "]"},
      {Kind::RIGHT_BRACKET, "]"},
      {Kind::POINT, "."},
      {Kind::INTEGER, "0"},
      {Kind::POINT, "."},
      {Kind::INTEGER, "0"},
      {Kind::EOF, ""},
    ]

    lexer.tokenize.map do |token|
      {token.kind, token.value}
    end.should eq(expected)
  end

  it "tokenizes ordinary float literal with fractional part" do
    lexer = Crinja::Parser::ExpressionLexer.new Crinja::Config.new, %(1.5)

    lexer.tokenize.map do |token|
      {token.kind, token.value}
    end.should eq([{Kind::FLOAT, "1.5"}, {Kind::EOF, ""}])
  end

  it "tokenizes non-ascii" do
    lexer = Crinja::Parser::TemplateLexer.new Crinja::Config.new, %(£{{ "foo" }})
    expected = [
      {Kind::FIXED, "£"},
      {Kind::EXPR_START, "{{"},
      {Kind::STRING, "foo"},
      {Kind::EXPR_END, "}}"},
      {Kind::EOF, ""},
    ]

    lexer.tokenize.map do |token|
      {token.kind, token.value}
    end.should eq(expected)
  end
end
