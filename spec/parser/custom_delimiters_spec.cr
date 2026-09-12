require "../spec_helper"

# Configurable Jinja delimiters (Jinja2's `block_start_string`/
# `block_end_string`/`variable_start_string`/`variable_end_string`/
# `comment_start_string`/`comment_end_string` environment options).
# Real Ansible's `template:` module exposes all six as task parameters,
# so the lexer must accept arbitrary delimiter strings instead of the
# hard-coded `{%`/`%}`/`{{`/`}}`/`{#`/`#}` shapes.
describe "custom Jinja delimiters" do
  it "tokenizes with non-default delimiters" do
    config = Crinja::Config.new
    config.block_start_string = "<%"
    config.block_end_string = "%>"
    config.variable_start_string = "<<"
    config.variable_end_string = ">>"
    config.comment_start_string = "<#"
    config.comment_end_string = "#>"

    lexer = Crinja::Parser::TemplateLexer.new config, %(Hello << name >> <% if x %>!<# note #><% end %>)

    tokens = lexer.tokenize

    expected = [
      {Kind::FIXED, "Hello "},
      {Kind::EXPR_START, "<<"},
      {Kind::IDENTIFIER, "name"},
      {Kind::EXPR_END, ">>"},
      {Kind::FIXED, " "},
      {Kind::TAG_START, "<%"},
      {Kind::IDENTIFIER, "if"},
      {Kind::IDENTIFIER, "x"},
      {Kind::TAG_END, "%>"},
      {Kind::FIXED, "!"},
      {Kind::NOTE, "<# note"},
      {Kind::TAG_START, "<%"},
      {Kind::IDENTIFIER, "end"},
      {Kind::TAG_END, "%>"},
      {Kind::EOF, ""},
    ]

    tokens.map { |token| {token.kind, token.value} }.should eq(expected)
  end

  it "renders variables, blocks and comments with non-default delimiters" do
    env = Crinja.new
    env.config.block_start_string = "<%"
    env.config.block_end_string = "%>"
    env.config.variable_start_string = "<<"
    env.config.variable_end_string = ">>"
    env.config.comment_start_string = "<#"
    env.config.comment_end_string = "#>"
    env.config.trim_blocks = true

    template = env.from_string(<<-'TEMPLATE')
      <% for item in items %>
      << item >> {{ also_literal }} {{ braces }}
      <% endfor %>
      <# a comment #>
      TEMPLATE

    template.render({"items" => ["a", "b"]}).should eq("a {{ also_literal }} {{ braces }}\nb {{ also_literal }} {{ braces }}\n")
  end

  it "keeps default delimiters working unchanged when unconfigured" do
    render("Hello {{ name }}{% if x %}!{% endif %}{# c #}", {"name" => "World", "x" => true}).should eq("Hello World!")
  end

  it "supports whitespace-control markers with non-default delimiters" do
    env = Crinja.new
    env.config.block_start_string = "<%"
    env.config.block_end_string = "%>"
    env.config.variable_start_string = "<<"
    env.config.variable_end_string = ">>"
    env.config.trim_blocks = false
    env.config.lstrip_blocks = true

    template = env.from_string("A\n  <% if true %>\nB\n<% endif %>\n")

    template.render.should eq("A\n\nB\n")

    env.config.trim_blocks = true

    template = env.from_string("A\n  <% if true %>\nB\n<% endif %>\n")

    template.render.should eq("A\nB\n")

    # `{%+` - the explicit lstrip_blocks override keeps its meaning with
    # non-default delimiters too:
    template = env.from_string("A\n  <%+ if true %>\nB\n<% endif %>\n")

    template.render.should eq("A\n  B\n")

    # `-%>` / `+%>` - right-side whitespace control:
    env.config.trim_blocks = false
    env.config.lstrip_blocks = false

    template = env.from_string("A\n<% if true -%>   \nB\n<% endif %>\n")

    template.render.should eq("A\nB\n")

    env.config.trim_blocks = true

    template = env.from_string("A\n<% if true +%>\nB\n<% endif %>\n")

    template.render.should eq("A\n\nB\n")
  end

  it "raw blocks respect non-default block delimiters" do
    env = Crinja.new
    env.config.block_start_string = "<%"
    env.config.block_end_string = "%>"

    template = env.from_string("<% raw %>{{ not_rendered }}<% endraw %>x")

    template.render.should eq("{{ not_rendered }}x")
  end

  it "raises the real termination error on a mismatched end delimiter" do
    env = Crinja.new
    env.config.block_start_string = "<%"
    env.config.block_end_string = "%>"

    # `}}` matches the (default) variable_end_string but not the block
    # scope's own end - the lexer's same "Terminated" error as with the
    # classic delimiters (`{% if x }}`).
    expect_raises(Crinja::TemplateSyntaxError) do
      env.from_string("<% if true }}")
    end
  end
end
