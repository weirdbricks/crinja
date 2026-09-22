require "../spec_helper"
# tests based on https://github.com/pallets/jinja/blob/master/tests/test_core_tags.py

private module ForLoopDepthSpec
  UNDER = 40
  OVER  = 60

  alias Node = Hash(String, Int32 | Array(Node) | Nil)

  def self.deep_node(depth : Int32) : Node
    h = Hash(String, Int32 | Array(Node) | Nil).new
    h["a"] = depth
    h["b"] = depth == 0 ? nil : [deep_node(depth - 1)] of Node
    h
  end

  TEMPLATE = "{% for item in seq recursive -%}[{{ item.a }}{% if item.b %}{{ loop(item.b) }}{% endif %}]{%- endfor %}"
end

describe Crinja::Tag::For do
  it "renders for loop with variables" do
    render(%({% for a in abc %}{{ loop.index }}: {{ a }}{% if loop.last %}.{% endif %}{% endfor %}), {"abc" => ["a", "b", "c"]}).should eq("1: a2: b3: c.")
  end

  it "renders for loop" do
    render(%({% for a in ['a', 'b', 'c'] %}{{ loop.index }}: {{ a }}{% if not loop.last %}, {% endif %}{% endfor %})).should eq("1: a, 2: b, 3: c")
  end

  it "renders simple" do
    render(%({% for i in numbers %}{{ i }}{% endfor %}), {"numbers" => [1, 2, 3, 4, 5]}).should eq("12345")
  end

  it "raises when seq is undefined" do
    # Ported from pallets/jinja's test_else, which asserts on vanilla
    # Jinja2's lenient default-Undefined behavior (renders the else
    # clause). Ansible's environment is stricter: iterating an
    # undefined variable in a `{% for %}` always raises, verified live
    # against real ansible-playbook (ahuffman.resolv role, round 159).
    expect_raises(Crinja::TypeError, "can't iterate over undefined") do
      render(%({% for item in seq %}XXX{% else %}...{% endfor %}))
    end
  end

  it "raises when seq is undefined even with an else-scoped var of the same name" do
    expect_raises(Crinja::TypeError, "can't iterate over undefined") do
      render(%({% for item in seq %}XXX{% else %}{{ item }}{% endfor %}), {"item" => "42"})
    end
  end

  it "raises for empty blocks when seq is undefined" do
    expect_raises(Crinja::TypeError, "can't iterate over undefined") do
      render(%(<{% for item in seq %}{% else %}{% endfor %}>))
    end
  end

  it "renders context vars" do
    bindings = {"seq" => [42, 24]}
    tpl = <<-'TPL'
          {% for item in seq -%}
          {{ loop.index }}|{{ loop.index0 }}|{{ loop.revindex }}|{{
                loop.revindex0 }}|{{ loop.first }}|{{ loop.last }}|{{
               loop.length }}###{% endfor %}
          TPL

    render(tpl, bindings).split("###").map(&.split("|")).should eq([
      ["1", "0", "2", "1", "True", "False", "2"],
      ["2", "1", "1", "0", "False", "True", "2"],
      [""],
    ])
  end

  it "renders cycle" do
    render(%({% for item in seq %}{{
            loop.cycle('<1>', '<2>') }}{% endfor %}{%
            for item in seq %}{{ loop.cycle(*through) }}{% endfor %}), {"seq" => (0..3), "through" => ["<1>", "<2>"]}, autoescape: false).should eq("<1><2>" * 4)
  end

  it "renders with correct scoping" do
    render(%({% for item in seq %}{% endfor %}{{ item }}), {"seq" => (0..1)}).should eq("")
  end

  pending "https://github.com/crystal-lang/crystal/issues/5694" do
    it "varlen" do
      iter = (0..4).each
      render(%({% for item in iter %}{{ item }}{% endfor %}), {"iter" => iter}).should eq("01234")
    end

    it "iterator issue" do
      index = 0
      Crinja::Tag::For::ForLoop.new(Crinja::Value.new((0..4).each)).each do |value|
        value.should eq index
        index += 1
      end
      index.should eq 5
    end
  end

  it "noniter" do
    expect_raises(Crinja::TypeError) do
      render(%({% for item in none %}...{% endfor %}))
    end
  end

  it "recursive" do
    render(<<-'TPL',
      {% for item in seq recursive -%}
      [{{ item.a }}{% if item.b %}<{{ loop(item.b) }}>{% endif %}]
      {%- endfor %}
      TPL
      {"seq" => [
        {"a" => 1, "b" => [{"a" => 1}, {"a" => 2}]},
        {"a" => 2, "b" => [{"a" => 1}, {"a" => 2}]},
        {"a" => 3, "b" => [{"a" => "a"}]},
      ]}, trim_blocks: true).should eq("[1<[1][2]>][2<[1][2]>][3<[a]>]")
    # Round170: `-%}`/`{%-` trim markers are now honored inside a
    # RECURSIVE for-body re-render too (previously they weren't, leaving
    # the source newlines - see git history) - this now matches real
    # Python jinja2 exactly, verified directly.
  end

  it "recursive_depth0" do
    %({% for item in seq recursive -%}
    [{{ loop.depth0 }}:{{ item.a }}{% if item.b %}<{{ loop(item.b) }}>{% endif %}]
    {%- endfor %})

    render(<<-'TPL',
      {% for item in seq recursive -%}
      [{{ loop.depth0 }}:{{ item.a }}{% if item.b %}<{{ loop(item.b) }}>{% endif %}]
      {%- endfor %}
      TPL
      {"seq" => [
        {"a" => 1, "b" => [{"a" => 1}, {"a" => 2}]},
        {"a" => 2, "b" => [{"a" => 1}, {"a" => 2}]},
        {"a" => 3, "b" => [{"a" => 'a'}]},
      ]}, trim_blocks: true).should eq("[0:1<[1:1][1:2]>][0:2<[1:1][1:2]>][0:3<[1:a]>]")
    # Round170: now matches real Python jinja2 exactly - see the
    # "recursive" test's note.
  end

  it "recursive_depth" do
    %({% for item in seq recursive -%}
      [{{ loop.depth }}:{{ item.a }}{% if item.b %}<{{ loop(item.b) }}>{% endif %}]
        {%- endfor %})
    render(<<-'TPL',
      {% for item in seq recursive -%}
      [{{ loop.depth }}:{{ item.a }}{% if item.b %}<{{ loop(item.b) }}>{% endif %}]
      {%- endfor %}
      TPL
      {"seq" => [
        {"a" => 1, "b" => [{"a" => 1}, {"a" => 2}]},
        {"a" => 2, "b" => [{"a" => 1}, {"a" => 2}]},
        {"a" => 3, "b" => [{"a" => "a"}]},
      ]}, trim_blocks: true).should eq("[1:1<[2:1][2:2]>][1:2<[2:1][2:2]>][1:3<[2:a]>]")
    # Round170: now matches real Python jinja2 exactly - see the
    # "recursive" test's note.
  end

  it "looploop" do
    render(<<-'TPL',
      {% for row in table -%}
      {%- set rowloop = loop -%}
      {%- for cell in row -%}
      [{{ rowloop.index }}|{{ loop.index }}]
      {%- endfor %}
      {%- endfor %}
      TPL
      {"table" => ["ab", "cd"]}, trim_blocks: true, lstrip_blocks: true).should eq "[1|1][1|2][2|1][2|2]"
  end

  it "loop_errors" do
    expect_raises(Crinja::UndefinedError) do
      render(%({% for item in [1] if loop.index == 0 %}...{% endfor %}))
    end
    render(%({% for item in [] %}...{% else %}{{ loop }}{% endfor %})).should eq ""
  end

  it "loop_filter" do
    render(%({% for item in range(10) if item is even %}[{{ item }}]{% endfor %})).should eq "[0][2][4][6][8]"
    render(%({%- for item in range(10) if item is even %}[{{ loop.index }}:{{ item }}]{% endfor %})).should eq "[1:0][2:2][3:4][4:6][5:8]"
  end

  it "loop_unassignable" do
    expect_raises(Crinja::TemplateSyntaxError) do
      render %({% for loop in seq %}...{% endfor %})
    end
  end

  it "scoped_special_var" do
    render(%({% for s in seq %}[{{ loop.first }}{% for c in s %}|{{ loop.first }}{% endfor %}]{% endfor %}), {
      "seq" => ["ab", "cd"],
    }).should eq "[True|True|False][False|True|False]"
  end

  it "scoped_loop_var" do
    render(%({% for x in seq %}{{ loop.first }}{% for y in seq %}{% endfor %}{% endfor %}), {"seq" => "ab"}).should eq "TrueFalse"
    render(%({% for x in seq %}{% for y in seq %}{{ loop.first }}{% endfor %}{% endfor %}), {"seq" => "ab"}).should eq "TrueFalseTrueFalse"
  end

  it "recursive_empty_loop_iter" do
    render(%({%- for item in foo recursive -%}{%- endfor -%}), {"foo" => [] of String}).should eq ""
  end

  it "recursive for-loop renders nesting just under the max recursion depth" do
    render(
      ForLoopDepthSpec::TEMPLATE,
      {"seq" => [ForLoopDepthSpec.deep_node(ForLoopDepthSpec::UNDER - 1)]}
    ).should contain("[1[0]]")
  end

  it "raises a catchable error when recursive for-loop exceeds the max recursion depth" do
    # Before the depth guard, ~20000 nesting levels crashed the whole
    # process with an uncatchable stack overflow (verified with a probe).
    expect_raises(Crinja::Error, "maximum recursion depth exceeded in recursive for-loop") do
      render(ForLoopDepthSpec::TEMPLATE, {"seq" => [ForLoopDepthSpec.deep_node(ForLoopDepthSpec::OVER - 1)]})
    end
  end

  pending "call_in_loop" do
    render(<<-'TPL').should eq "[1][2][3]"
        {%- macro do_something() -%}
            [{{ caller() }}]
        {%- endmacro %}
        {%- for i in [1, 2, 3] %}
            {%- call do_something() -%}
                {{ i }}
            {%- endcall %}
        {%- endfor -%}
        TPL
  end

  it "scoping_bug" do
    render(<<-'TPL', {"foo" => [1]}).should eq "...1......2..."
        {%- for item in foo %}...{{ item }}...{% endfor -%}
        {%- macro item(a) %}...{{ a }}...{% endmacro -%}
        {{- item(2) -}}
        TPL
  end

  it "unpacking" do
    render(%({% for a, b, c in [[1, 2, 3]] %}{{ a }}|{{ b }}|{{ c }}{% endfor %})).should eq "1|2|3"
  end

  it "intended_scoping_with_set" do
    bindings = {"x" => 0, "seq" => [1, 2, 3]}
    render(%({% for item in seq %}{{ x }}{% set x = item %}{{ x }}{% endfor %}), bindings).should eq "010203"
    render(%({% set x = 9 %}{% for item in seq %}{{ x }}{% set x = item %}{{ x }}{% endfor %}), bindings).should eq "919293"
  end

  it "loop variable shadows global function of the same name" do
    env = Crinja.new
    env.functions["foo"] = Crinja.function do
      Crinja::Value.new("called")
    end

    template = env.from_string(%({% for foo in seq %}{{ foo }}{% endfor %}))
    template.render({"seq" => ["a", "b"]}).should eq "ab"

    template = env.from_string(%({% for entry in seq %}{{ foo() }}{% endfor %}))
    template.render({"seq" => ["a", "b"]}).should eq "calledcalled"
  end

  it "iterates a dict yielding KEYS for a single loop variable (Python semantics)" do
    # Real Jinja2 iterates a dict exactly like Python: `for k in dict:`
    # yields keys. The two-variable form keeps iterating (key, value)
    # pairs - see the krikri-playbook fork's design note in
    # src/lib/tag/for.cr for why (real-world roles like jtyr.nsswitch
    # depend on the pairs behavior). This used to also yield pairs
    # here, so a downstream string operation on the loop variable
    # failed with "Cast from Crinja::Tuple to (Crinja::SafeString |
    # String) failed" (found via PowerDNS.pdns in krikri-playbook's
    # round 300 Kata campaign).
    render(%({% for k in dict %}{{ k }};{% endfor %}), {"dict" => {"b" => 2, "a" => 1}})
      .should eq("b;a;")
  end

  it "iterates a dict yielding (key, value) pairs for two loop variables" do
    # Deliberate leniency beyond real Jinja2 (which hard-fails two-var
    # unpacking of a dict's string keys): kept because real-world roles
    # shipped on it. The pairs are built by the for tag itself since
    # crystal-play-0.9.25 - Value#each yields keys-only now.
    render(%({% for k, v in dict %}{{ k }}={{ v }};{% endfor %}), {"dict" => {"b" => 2, "a" => 1}})
      .should eq("b=2;a=1;")
  end

  it "renders loop.previtem and loop.nextitem with Undefined only at the boundaries" do
    # Real Jinja2's LoopContext keeps _before/_current/_after bookkeeping
    # (jinja2/runtime.py): previtem/nextitem are the adjacent items and a
    # genuine Undefined object at the first/last boundary - which is why
    # `|default('x')` fires exactly once per side. Verified live against
    # Jinja2 3.1.6; this fork used to render `x-0-x|x-1-x|...` because
    # previtem/nextitem were never implemented (differential harness).
    tpl = <<-'TPL'
        {% for item in seq -%}
                    {{ loop.previtem|default('x') }}-{{ item }}-{{
                    loop.nextitem|default('x') }}|
                {%- endfor %}
        TPL
    render(tpl, {"seq" => [0, 1, 2, 3]}).should eq("x-0-1|0-1-2|1-2-3|2-3-x|")
  end

  it "renders loop.changed with first-call and previous-argument-tuple semantics" do
    # Real Jinja2's LoopContext.changed(*value) returns True on the first
    # call and whenever the WHOLE argument tuple differs from the previous
    # call's tuple (jinja2/runtime.py `if self._last_changed_value !=
    # value`). Verified live against Jinja2 3.1.6; this fork raised
    # `loop.changed is undefined` because the method did not exist on the
    # loop object at all (differential harness).
    tpl = <<-'TPL'
        {% for item in seq -%}
                    {{ loop.changed(item) }},
                {%- endfor %}
        TPL
    render(tpl, {"seq" => [nil, nil, 1, 2, 2, 3, 4, 4, 4]})
      .should eq("True,False,True,True,False,True,True,False,False,")
  end

  it "scopes loop.previtem/loop.nextitem per recursion level" do
    # Real Jinja2 creates a fresh LoopContext per recursion level (the
    # recursive `loop(...)` call renders the body with a NEW loop context),
    # so a nested loop's previtem/nextitem refer to siblings within the
    # nested list, not the outer one. Verified live against Jinja2 3.1.6;
    # this fork's Recursive subclass also builds a new loop per level, so
    # the fix had to merely live on per-instance state, not shared state.
    tpl = <<-'TPL'
        {% for item in seq recursive -%}
                    [{{ loop.previtem.a if loop.previtem is defined else 'x' }}.{{
                    item.a }}.{{ loop.nextitem.a if loop.nextitem is defined else 'x'
                    }}{% if item.b %}<{{ loop(item.b) }}>{% endif %}]
                {%- endfor %}
        TPL
    seq = [
      {"a" => 1, "b" => [{"a" => 2, "b" => false}, {"a" => 3, "b" => false}]},
      {"a" => 4, "b" => false},
      {"a" => 5, "b" => [{"a" => 6, "b" => false}]},
    ]
    render(tpl, {"seq" => seq}).should eq("[x.1.4<[x.2.3][2.3.x]>][1.4.5][4.5.x<[x.6.x]>]")
  end
end
