require "./spec_helper"

def splat_env
  env = Crinja.new
  env.functions["foo"] = Crinja.function do
    Crinja::Value.new(
      arguments.varargs.map(&.to_s).join("") +
      arguments.kwargs.values.map(&.to_s).join("")
    )
  end
  env
end

def render_splat(tpl)
  splat_env.from_string(tpl).render
end

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
    render(%("Hello, {{ "World" ~ "\\" " }}{{ 2 }} {{ "A" | lower }}ll{{ "}}" }}!), {"name" => "John"}, autoescape: true).should eq("\"Hello, World&#34; 2 all}}!")
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

  # Django-style numeric attribute access: real Jinja2's `parse_subscript`
  # (jinja2/parser.py 3.1.6) accepts an integer token directly after a
  # member-access dot and compiles it to the same item lookup as `[0]`
  # (the syntax Django templates use for list indexing), and its float_re's
  # `(?<!\.)` lookbehind (jinja2/lexer.py) keeps a chained `.digit` from
  # merging into one float token, so `[[1]].0.0` is two chained index
  # accesses. Expected outputs verified against BOTH real Jinja2 3.1.6 and
  # a real `ansible-playbook` 2.19 run (`debug: msg:` tasks, outputs
  # identical in both). This fork used to lex the second `.0` of
  # `].0.0` as one FLOAT "0.0" and fail `Expected IDENTIFIER, got FLOAT`
  # (differential-harness finding); ordinary float literals and `foo.bar`
  # attribute access must stay untouched.
  describe "Django-style numeric attribute access" do
    it "renders dot index into a list" do
      render("{{ [1, 2, 3].0 }}").should eq("1")
    end

    it "renders chained dot indexes into a nested list" do
      render("{{ [[1]].0.0 }}").should eq("1")
    end

    it "renders ordinary float literal unaffected" do
      render("{{ 1.5 }}").should eq("1.5")
    end

    it "renders ordinary attribute access unaffected" do
      render("{{ user.name }}", {"user" => {"name" => "John"}}).should eq("John")
    end
  end

  # Real Jinja2's `parse_call_args` (jinja2/parser.py 3.1.6) recognizes
  # `*expr` (token "mul", at most once) and `**expr` (token "pow", at most
  # once) splats in every parenthesized argument list - function, filter
  # AND test calls - expanding them at call time into positional args and
  # keyword args respectively. Ordering follows real Jinja2's own codegen
  # (`signature` in jinja2/compiler.py emits plain args, plain kwargs,
  # `*dyn_args`, `**dyn_kwargs`, in that order, regardless of source
  # position): the positional splat expands AFTER all plain positional
  # args, the keyword splat merges AFTER all plain kwargs. Verified live
  # against real Jinja2 3.1.6 AND a real `ansible-playbook` 2.19 run with
  # `debug: msg:` tasks (function-call splat grammar is pre-finalization
  # parsing, untouched by Ansible's `finalize`/native-types
  # customizations): `['a','b','c'] | join(*['-'])` -> `a-b-c` and
  # `'abc' | replace(**{'old': 'b', 'new': 'X'})` -> `aXc` render
  # identically in both. This fork's call-argument parser had no splat
  # recognition at all - `{{ foo('a', c='d', e='f', *['b'], **{'g': 'h'})
  # }}` (real Jinja2 with the concatenating `foo` below: `abdfh`) raised
  # `Unexpected OPERATOR` at the `*` (differential-harness finding against
  # real Jinja2 3.1.6's own upstream test suite).
  describe "function-call argument splats (*expr / **expr)" do
    it "renders the confirmed harness case with both splats" do
      render_splat("{{ foo('a', c='d', e='f', *['b'], **{'g': 'h'}) }}").should eq("abdfh")
    end

    it "renders a call with only a positional splat" do
      render_splat("{{ foo(*['x', 'y']) }}").should eq("xy")
    end

    it "renders a call with only a keyword splat" do
      render_splat("{{ foo(**{'c': 'd', 'e': 'f'}) }}").should eq("df")
    end

    it "keeps a normal call without splats completely unaffected" do
      render_splat("{{ foo('a', 'b', c='d') }}").should eq("abd")
      render("{{ [1, 2] | join('-') }}").should eq("1-2")
      render("{{ 'x' | upper }}").should eq("X")
      render("{{ 4 is divisibleby 2 }}").should eq("True")
    end

    it "expands the positional splat after all plain positional args" do
      render_splat("{{ foo('a', c='d', *['b']) }}").should eq("abd")
    end

    it "splat targets can be variables, not just literals" do
      render_splat("{% set l = ['x'] %}{{ foo('a', *l) }}").should eq("ax")
      render_splat("{% set d = {'g': 'h'} %}{{ foo(c='d', **d) }}").should eq("dh")
    end

    it "splats any iterable into positional args like real Python" do
      render_splat("{{ foo(*'ab') }}").should eq("ab")
      render_splat("{% set d = {'g': 'h'} %}{{ foo(*d) }}").should eq("g")
    end

    it "supports splats in filter and test calls" do
      render("{{ ['a','b','c'] | join(*['-']) }}").should eq("a-b-c")
      render("{{ 'abc' | replace(**{'old': 'b', 'new': 'X'}) }}").should eq("aXc")
      render("{{ 4 is divisibleby(*[2]) }}").should eq("True")
    end

    it "merges keyword-splat entries after plain kwargs" do
      render("{{ dict(c='d', **{'g': 'h'}) }}").should eq("{'c': 'd', 'g': 'h'}")
    end

    it "still tolerates a trailing comma" do
      render_splat("{{ foo('a',) }}").should eq("a")
    end

    it "rejects two positional splats like real Jinja2" do
      expect_raises(Crinja::TemplateSyntaxError, "invalid syntax for function call expression") do
        render_splat("{{ foo(*['a'], *['b']) }}")
      end
    end

    it "rejects two keyword splats like real Jinja2" do
      expect_raises(Crinja::TemplateSyntaxError, "invalid syntax for function call expression") do
        render_splat("{{ foo(**{'a': 1}, **{'b': 2}) }}")
      end
    end

    it "rejects a plain positional arg after a splat like real Jinja2" do
      expect_raises(Crinja::TemplateSyntaxError, "invalid syntax for function call expression") do
        render_splat("{{ foo(*['a'], 'b') }}")
      end
    end

    it "rejects a plain positional arg after kwargs like real Jinja2" do
      expect_raises(Crinja::TemplateSyntaxError, "invalid syntax for function call expression") do
        render_splat("{{ foo(c='d', 'e') }}")
      end
    end

    it "rejects a positional splat after a keyword splat like real Jinja2" do
      expect_raises(Crinja::TemplateSyntaxError, "invalid syntax for function call expression") do
        render_splat("{{ foo(**{'k': 1}, *['a']) }}")
      end
    end

    it "rejects a kwarg after a keyword splat like real Jinja2" do
      expect_raises(Crinja::TemplateSyntaxError, "invalid syntax for function call expression") do
        render_splat("{{ foo(**{'k': 1}, j='2') }}")
      end
    end

    it "raises a TypeError on a duplicate keyword like real Python" do
      expect_raises(Crinja::TypeError) do
        render_splat("{{ foo(c='1', **{'c': '2'}) }}")
      end
    end
  end

  # Real Jinja2 normalizes template data newlines in `Lexer.wrap`
  # (jinja2/lexer.py 3.1.6): every data value - fixed text and raw-block
  # content alike - goes through `_normalize_newlines`, replacing
  # `newline_re = re.compile(r"(\r\n|\r|\n)")` with the environment's
  # `newline_sequence` (default `\n`, which real Ansible also keeps), so
  # a template with CRLF or bare-CR line endings renders LF-only
  # (Jinja2's own upstream regression test `test_normalizing`). Verified
  # live against a real Jinja2 3.1.6 Environment AND a real
  # `ansible-playbook` 2.19 run (`template:` action over CRLF and bare-CR
  # source files containing expressions, output inspected byte-wise with
  # `cat -A`). This fork used to leave the `\r` characters of the source
  # in the rendered output.
  describe "CRLF / bare-CR template source newline normalization" do
    it "renders a CRLF-ended template with LF-only line endings" do
      render("1\r\n2\r\n3\r\n4\r\n").should eq("1\n2\n3\n4\n")
    end

    it "normalizes CRLF around template expressions" do
      render("1\r\n{{ 'a' }}\r\n2\r\n").should eq("1\na\n2\n")
    end

    it "normalizes bare CR like real Jinja2's newline_re" do
      render("a\rb\rc").should eq("a\nb\nc")
    end

    it "normalizes raw-block content like other data tokens" do
      render("{% raw %}1\r\n2\r\n{% endraw %}").should eq("1\n2\n")
    end

    it "keeps block-tag newline handling working across CRLF endings" do
      render("1\r\n{% if true %}\r\n2\r\n{% endif %}\r\n3", trim_blocks: true).should eq("1\n2\n3")
    end
  end
end
