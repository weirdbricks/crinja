require "../spec_helper.cr"

describe Crinja::Tag::Raw do
  it "ignores raw content" do
    render(<<-'TPL').should eq <<-'RENDERED'
        {% raw %}
            <ul>
            {% for item in seq %}
                <li>{{ item }}</li>
            {% endfor %}
            </ul>
        {% endraw %}
        TPL

            <ul>
            {% for item in seq %}
                <li>{{ item }}</li>
            {% endfor %}
            </ul>

        RENDERED
  end

  it "ignores empty raw" do
    render(%({% raw %}{% endraw %})).should eq ""
  end

  # Regression: whitespace-control modifiers on `{% raw %}`/`{% endraw %}`
  # used to fail to parse at all ("Unclosed tag, missing: endraw"), found
  # by the differential harness against real Jinja2 3.1.6's own upstream
  # test suite; every expected output below was verified against both a
  # real `jinja2.Environment` and a real `ansible-playbook` run.
  it "strips whitespace outside a raw block for dashes on both tags" do
    render("1  {%- raw -%}   2   {%- endraw -%}   3").should eq "123"
  end

  it "leaves plain raw blocks and their content untouched" do
    render("1  {% raw %}   2   {% endraw %}   3").should eq "1     2      3"
  end

  it "trims only one side for one-sided dashes" do
    render("{%- raw %}   2   {% endraw -%}").should eq "   2   "
  end

  it "rstrips raw content for a dash before endraw" do
    render("{% raw %}   2   {%- endraw %}").should eq "   2"
  end

  it "never applies trim_blocks/lstrip_blocks config to raw content" do
    render("{% raw %}\n  2\n  {% endraw %}", trim_blocks: true).should eq "\n  2\n  "
    render("{% raw %}\n  2\n  {% endraw %}", lstrip_blocks: true).should eq "\n  2\n  "
  end

  it "supports plus modifiers on raw tags" do
    render("x{%+ raw %}y{%+ endraw %}z").should eq "xyz"
    render("x{% raw %}y{% endraw +%}z").should eq "xyz"
  end
end
