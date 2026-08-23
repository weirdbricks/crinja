require "../spec_helper"

private def text_value(node, trim_blocks = false, lstrip_blocks = false)
  Crinja::Renderer.trim_text(node.as(Crinja::AST::FixedString), trim_blocks, lstrip_blocks)
end

describe "whitespace" do
  it "trims whitespace after tag" do
    template = parse(%(<div>\n    {% if true -%}\n        yay\n    {% endif %}\n</div>))
    text_value(template.nodes.children[1].as(Crinja::AST::TagNode).block.children[0]).should eq("yay\n    ")
  end

  it "trims before tag" do
    template = parse(%(<div>\n    {% if true %}\n        yay\n    {%- endif %}\n</div>))
    text_value(template.nodes.children[1].as(Crinja::AST::TagNode).block.children[0]).should eq("\n        yay")
  end

  it "trims before tag with lstrip blocks" do
    template = parse(%(<div>\n    {% if true %}\n        yay\n    {%- endif %}\n</div>))
    text_value(template.nodes.children[1].as(Crinja::AST::TagNode).block.children[0], false, true).should eq("\n        yay")
  end

  it "trims before and after tag" do
    template = parse(%(<div>\n    {% if true -%}\n        yay\n    {%- endif %}\n</div>))
    text_value(template.nodes.children[1].as(Crinja::AST::TagNode).block.children[0]).should eq("yay")
  end

  it "trims empty text left side correctly" do
    template = parse(%({% if true %}\n    {%- set foo="bar" -%}\n  {% endif %}))
    text_value(template.nodes.children[0].as(Crinja::AST::TagNode).block.children[0]).should eq("")
    text_value(template.nodes.children[0].as(Crinja::AST::TagNode).block.children[2]).should eq("")
    template.render.should eq ""
  end

  it "trims empty text right side correctly" do
    template = parse(%({% if true -%}\n    {% set foo="bar" %}\n  {%- endif %}))
    text_value(template.nodes.children[0].as(Crinja::AST::TagNode).block.children[0]).should eq("")
    text_value(template.nodes.children[0].as(Crinja::AST::TagNode).block.children[2]).should eq("")
    template.render.should eq ""
  end

  it "trims empty text both sides correctly" do
    template = parse(%({% if true -%}\n    {%- set foo="bar" -%}\n  {%- endif %}))
    text_value(template.nodes.children[0].as(Crinja::AST::TagNode).block.children[0]).should eq("")
    text_value(template.nodes.children[0].as(Crinja::AST::TagNode).block.children[2]).should eq("")
    template.render.should eq ""
  end

  it "trims around blocks" do
    template = parse(%(  {%- for item in item_list -%}\n    {{ item }}{% if not loop.last %},{% endif -%}\n  {%- endfor -%}))
    text_value(template.nodes.children[1].as(Crinja::AST::TagNode).block.children[0]).should eq("")
    text_value(template.nodes.children[1].as(Crinja::AST::TagNode).block.children[3]).should eq("")
  end

  it "trims around blocks with `trim_blocks`" do
    env = Crinja.new
    env.config.trim_blocks = true
    string = %(  {%- for item in item_list -%}\n    {{ item }}{% if not loop.last %},{% endif %}\n  {%- endfor -%})
    template = Crinja::Template.new(string)
    text_value(template.nodes.children[1].as(Crinja::AST::TagNode).block.children[0]).should eq("")
    text_value(template.nodes.children[1].as(Crinja::AST::TagNode).block.children[3]).should eq("")
  end

  # Round 170 (2026-08-23): the actual gap `StringTrimmer.trim` left
  # open - explicit `-` whitespace control only stripped the FIRST line
  # of a text segment spanning multiple lines (a blank line, or more,
  # between the tag and real content), leaving the rest untouched. Real
  # Jinja2 strips the ENTIRE contiguous whitespace run on that side,
  # however many lines it spans - verified directly against a real
  # `jinja2.Environment` render for every case below before writing the
  # expected value here.
  describe "multi-line explicit dash (round170 gap)" do
    it "strips a leading run of several blank lines after `-%}`" do
      template = parse(%(<div>\n    {% if true -%}\n\n\n        yay\n    {% endif %}\n</div>))
      text_value(template.nodes.children[1].as(Crinja::AST::TagNode).block.children[0]).should eq("yay\n    ")
    end

    it "strips a trailing run of several blank lines before `{%-`" do
      template = parse(%(<div>\n    {% if true %}\n        yay\n\n\n    {%- endif %}\n</div>))
      text_value(template.nodes.children[1].as(Crinja::AST::TagNode).block.children[0]).should eq("\n        yay")
      template.render.should eq "<div>\n    \n        yay\n</div>"
    end

    # NOTE: this one only checks the if-block's OWN inner text segment
    # (which IS this fix's scope) - the text AFTER `{%- endif %}` is
    # affected by a SEPARATE, pre-existing parser bug (`@trim_left`
    # instance-variable state leaking across a nested block's own
    # end-tag boundary, giving the sibling text after certain nested
    # blocks a spurious `trim_left = true` it never earned from an
    # actual adjacent dash) - out of scope here, tracked separately in
    # KNOWN_MISSING.md.
    it "strips multi-line whitespace runs on BOTH sides of the if-block's own inner text" do
      template = parse(%(<div>\n    {% if true -%}\n\n        yay\n\n    {%- endif %}\n</div>))
      text_value(template.nodes.children[1].as(Crinja::AST::TagNode).block.children[0]).should eq("yay")
    end

    it "matches buluma.collectd's own Filter/Include block shape" do
      string = %(<Include "/x">\n{% for f in files -%}\n\n    Filter "{{ f }}"\n\n{% endfor %}</Include>)
      template = Crinja::Template.new(string)
      template.render({"files" => ["*.conf"]}).should eq(%(<Include "/x">\nFilter "*.conf"\n\n</Include>))
    end
  end
end
