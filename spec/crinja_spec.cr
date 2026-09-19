require "./spec_helper"

describe Crinja do
  it ".render" do
    Crinja.render("Hello {{ name }}!", {name: "World"}).should eq "Hello World!"
  end

  it "renders a simple template without any template syntax" do
    render("Hello World").should eq("Hello World")
  end

  it "renders a simple variable expression" do
    render("Hello, {{ name }}!", {"name" => "John"}).should eq("Hello, John!")
  end

  it "renders a simple hello world with name" do
    render("Hello, {{ user.name | lower | upper }}!", {"user" => {"name" => "John"}}).should eq("Hello, JOHN!")
  end

  it "renders a simple attribute accessor" do
    render("Hello, {{ users[id].name | upper }}!", {"users" => {"john" => {"name" => "John"}}, "id" => "john"}).should eq("Hello, JOHN!")
  end

  it "renders simple literals" do
    render(%("Hello, {{ "World" ~ "\\" " }}{{ 2 }} {{ "A" | lower }}ll{{ "}}" }}!), {"name" => "John"}, autoescape: true).should eq("\"Hello, World&quot; 2 all}}!")
  end

  it "renders if tag" do
    render(%("Hello, {% if world %}World{% else %}Everyone{% endif %}!), {"world" => true}).should eq("\"Hello, World!")
  end

  it "renders else tag" do
    render(%("Hello, {% if world %}World{% else %}Everyone{% endif %}!), {"world" => false}).should eq("\"Hello, Everyone!")
  end

  it "respects comments" do
    # Round170: explicit `-#}`/`{#-` fully strips ALL adjacent
    # whitespace (matching real Jinja2, verified directly) - not just
    # the one newline this expectation previously encoded.
    render(%(Hello, \n{#- foob\nbar -#}\nWorld!)).should eq("Hello,World!")
  end

  it "renders simple test" do
    render(%({% if 4 is even %}even{% else %}odd{% endif %})).should eq("even")
  end

  # Real Jinja2 parses parens via `parse_tuple(explicit_parentheses=True)`
  # (jinja2/parser.py): `()` is an empty tuple, `(x,)` (mandatory comma) is
  # a 1-tuple, `(x)` is NOT a tuple, and a trailing comma is optional and
  # ignored in any bracketed collection literal (`parse_list`/`parse_dict`
  # re-test the closing bracket right after `expect("comma")`). This fork
  # raised `Unexpected RIGHT_PAREN` on the empty tuple and every trailing
  # comma (differential-harness finding against real Jinja2 3.1.6's own
  # upstream test suite). Expected outputs verified against BOTH real
  # Jinja2 3.1.6 and a real `ansible-playbook` 2.19 run: Python tuples are
  # lists to Ansible's native-types finalization, so every tuple here
  # renders bracketed (`{{ () }}` -> `[]`, not vanilla Jinja2's `()`
  # repr), while the bare parenthesized `{{ (1) }}` stays the integer.
  describe "tuple and trailing-comma collection literals" do
    it "renders empty tuple" do
      render("{{ () }}").should eq("[]")
    end

    it "renders single-element tuple" do
      render("{{ (1,) }}").should eq("[1]")
    end

    it "renders multi-element tuple" do
      render("{{ (1, 2) }}").should eq("[1, 2]")
    end

    it "renders parenthesized single expression as the expression itself" do
      render("{{ (1) }}").should eq("1")
    end

    it "renders tuple equality" do
      render("{{ (1, 2) == (1, 2) }}").should eq("True")
    end

    it "renders single-element tuple length" do
      render("{{ (1,)|length }}").should eq("1")
    end

    it "renders tuple with trailing comma" do
      render("{{ (1, 2,) }}").should eq("[1, 2]")
    end

    it "renders list with trailing comma" do
      render("{{ [1, 2,] }}").should eq("[1, 2]")
    end

    it "renders dict with trailing comma" do
      render("{{ {1: 2,} }}").should eq("{1: 2}")
    end
  end
end
