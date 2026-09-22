require "../spec_helper"

# These specs are derived from the original Jinja2 filter specs
# https://github.com/pallets/jinja/blob/bbe0a4174c2846487bef4328b309fddd8638da39/tests/test_filters.py

@[Crinja::Attributes]
private class User
  include Crinja::Object::Auto

  getter username, is_active

  def initialize(@username : String, @is_active : Bool = true)
  end

  def to_s(io)
    io << username
  end
end

@[Crinja::Attributes]
private class IdUser
  include Crinja::Object::Auto

  getter id, name

  def initialize(@id : Int32, @name : String)
  end

  def to_s(io)
    io << name
  end
end

@[Crinja::Attributes]
private class Date
  include Crinja::Object::Auto

  getter day : Int32
  getter month : Int32
  getter year : Int32

  def initialize(@day, @month, @year)
  end
end

@[Crinja::Attributes]
private class Article
  include Crinja::Object::Auto
  getter title : String
  getter date : Date

  def initialize(@title, *date)
    @date = Date.new(*date)
  end
end

describe Crinja::Filter do
  it "calling" do
    Crinja.new.call_filter("sum", [1, 2, 3]).should eq Crinja::Value.new(6)
  end

  it "capitalize" do
    evaluate_expression(%("foo bar"|capitalize)).should eq "Foo bar"
  end

  it "center" do
    evaluate_expression(%("foo"|center(9))).should eq "   foo   "
  end

  describe "default" do
    it "retuns default for missing" do
      evaluate_expression(%(missing|default('no'))).should eq "no"
    end

    it "does not overwrite false" do
      evaluate_expression(%(false|default('no'))).should eq "False"
    end

    it "overwrites false if boolean=true" do
      evaluate_expression(%(false|default('no', true))).should eq "no"
    end

    it "does not overwrite given" do
      evaluate_expression(%(given|default('no')), {"given" => "yes"}).should eq "yes"
    end

    it "recognizes short-form `d`" do
      evaluate_expression(%(missing|d(false))).should eq "False"
    end
  end

  describe "dictsort" do
    it "sorts" do
      bindings = {"foo" => {"aa" => 0, "b" => 1, "c" => 2, "AB" => 3}}
      evaluate_expression(%(foo|dictsort), bindings).should eq %([['aa', 0], ['AB', 3], ['b', 1], ['c', 2]])
    end

    it "sorts caseinsensitive" do
      bindings = {"foo" => {"aa" => 0, "b" => 1, "c" => 2, "AB" => 3}}
      evaluate_expression(%(foo|dictsort(true)), bindings).should eq %([['AB', 3], ['aa', 0], ['b', 1], ['c', 2]])
    end

    it "sorts by value" do
      bindings = {"foo" => {"aa" => 0, "b" => 1, "c" => 2, "AB" => 3}}
      evaluate_expression(%(foo|dictsort(false, "value")), bindings).should eq %([['aa', 0], ['b', 1], ['c', 2], ['AB', 3]])
    end
  end

  describe "sort" do
    it "sorts a list" do
      bindings = {"foo" => ["c", "aa", "AB", "b"]}
      evaluate_expression(%(foo|sort), bindings).should eq %(['aa', 'AB', 'b', 'c'])
    end

    it "sorts a dict into its KEYS, like Python's sorted(dict)" do
      # Real Jinja2's `sort` on a dict yields the sorted keys, not
      # (key, value) tuples. The tuple behavior is what krikri-playbook
      # lived with until the round 300 dict-iteration fix - it made
      # `{% for backend in pdns_backends | sort() %}` bind tuples
      # (found via PowerDNS.pdns, round 300 Kata campaign). dictsort
      # above still yields (key, value) pairs - use it when the role
      # wants pairs in a specific order.
      bindings = {"foo" => {"b" => 1, "aa" => 0, "AB" => 3, "c" => 2}}
      evaluate_expression(%(foo|sort), bindings).should eq %(['aa', 'AB', 'b', 'c'])
    end

    it "sorts a list of (key, value) pairs (the .items() shape) lexicographically by first element" do
      # Oefenweb.bash's own .bash_aliases.j2 uses
      # `{% for key, value in bash_aliases.items() | sort %}` - the
      # input is an Array of Arrays (not a Hash), so the dict-keys
      # special case does not fire; the existing Array-of-Tuple
      # comparison routing sorts by first element.
      bindings = {"foo" => [["c", 2], ["a", 0], ["b", 1]]}
      evaluate_expression(%(foo|sort), bindings).should eq %([['a', 0], ['b', 1], ['c', 2]])
    end
  end

  describe "batch" do
    it "batches" do
      evaluate_expression(%(foo|batch(3)|list), {"foo" => (0..9)}).should eq "[[0, 1, 2], [3, 4, 5], [6, 7, 8], [9]]"
    end

    it "batches with fill" do
      evaluate_expression(%(foo|batch(3, "X")|list), {"foo" => (0..9)}).should eq %([[0, 1, 2], [3, 4, 5], [6, 7, 8], [9, 'X', 'X']])
    end

    it "size-and-fill" do
      render(<<-'TPL',
        {% for row in items|batch(3, '-') -%}
        {% for column in row %} {{ column }} {% endfor %} |
        {% endfor %}
        TPL
        {items: ["a", "b", "c", "d", "e", "f", "g"]}).should eq " a  b  c  |\n d  e  f  |\n g  -  -  |\n"
    end

    it "size-only" do
      render(<<-'TPL',
        {% for row in items|batch(3) -%}
        {% for column in row %} {{ column }} {% endfor %} |
        {% endfor %}
        TPL
        {items: ["a", "b", "c", "d", "e", "f", "g"]}).should eq " a  b  c  |\n d  e  f  |\n g  |\n"
    end
  end

  describe "slice" do
    it "slices" do
      evaluate_expression(%(foo|slice(3)|list), {"foo" => (0..9)}).should eq "[[0, 1, 2, 3], [4, 5, 6], [7, 8, 9]]"
    end

    it "slices with fill" do
      evaluate_expression(%(foo|slice(3, "X")|list), {"foo" => (0..9)}).should eq %([[0, 1, 2, 3], [4, 5, 6, 'X'], [7, 8, 9, 'X']])
    end
  end

  # NOTE: markupsafe encodes '"' as the NUMERIC entity '&#34;' and "'" as
  # '&#39;' (Crystal's HTML.escape would use the named '&quot;') - verified
  # against real markupsafe and real ansible-playbook 2.19.
  it "escape" do
    evaluate_expression(%('<">&'|escape)).should eq "&lt;&#34;&gt;&amp;"
    evaluate_expression(%(x|escape), {x: Crinja::SafeString.new("<div />")}).should eq "<div />"
  end

  # Regression spec for crystal-play-0.9.51: the escape filter (and every
  # code path sharing its table) must use markupsafe's NUMERIC entities
  # for all non-ampersand special characters.
  it "escape uses markupsafe's numeric entity table for all special characters" do
    evaluate_expression(%('<'|escape)).should eq "&lt;"
    evaluate_expression(%('>'|escape)).should eq "&gt;"
    evaluate_expression(%('&'|escape)).should eq "&amp;"
    evaluate_expression(%('"'|escape)).should eq "&#34;"
    evaluate_expression(%("'"|escape)).should eq "&#39;"
    evaluate_expression(%( "<>&'\\"" |escape)).should eq "&lt;&gt;&amp;&#39;&#34;"
    evaluate_expression(%(x|escape), {x: "<>&'\""}).should eq "&lt;&gt;&amp;&#39;&#34;"
  end

  it "strips tags" do
    html = %(  <p>just a small   \n <a href="#">example</a> link</p>\n<p>to a webpage</p> <!-- <p>and some commented stuff</p> -->)
    evaluate_expression(%(foo|striptags), {"foo" => html}).should eq "just a small example link to a webpage"
  end

  describe "filesizeformat" do
    it do
      evaluate_expression(%(100|filesizeformat)).should eq "100 Bytes"
      evaluate_expression(%(1000|filesizeformat)).should eq "1.0 kB"
      evaluate_expression(%(1000000|filesizeformat)).should eq "1.0 MB"
      evaluate_expression(%(1000000000|filesizeformat)).should eq "1.0 GB"
      evaluate_expression(%(1000000000000|filesizeformat)).should eq "1.0 TB"
      evaluate_expression(%(100|filesizeformat(true))).should eq "100 Bytes"
      evaluate_expression(%(1000000|filesizeformat(true))).should eq "976.6 KiB"
      evaluate_expression(%(1000000000|filesizeformat(true))).should eq "953.7 MiB"
      evaluate_expression(%(1000000000000|filesizeformat(true))).should eq "931.3 GiB"
    end

    it "issue59" do
      evaluate_expression(%(300|filesizeformat)).should eq "300 Bytes"
      evaluate_expression(%(3000|filesizeformat)).should eq "3.0 kB"
      evaluate_expression(%(3000000|filesizeformat)).should eq "3.0 MB"
      evaluate_expression(%(3000000000|filesizeformat)).should eq "3.0 GB"
      evaluate_expression(%(3000000000000|filesizeformat)).should eq "3.0 TB"
      evaluate_expression(%(300|filesizeformat(true))).should eq "300 Bytes"
      evaluate_expression(%(3000|filesizeformat(true))).should eq "2.9 KiB"
      evaluate_expression(%(3000000|filesizeformat(true))).should eq "2.9 MiB"
    end
  end

  it "first" do
    evaluate_expression(%(foo|first), {"foo" => (0..9)}).should eq "0"
    evaluate_expression(%("foo"|first)).should eq "f"
  end

  it "float" do
    evaluate_expression(%("42"|float)).should eq "42.0"
    evaluate_expression(%("ajsghasjgd"|float)).should eq "0.0"
    evaluate_expression(%("32.32"|float)).should eq "32.32"
  end

  it "format" do
    evaluate_expression(%("%s|%s"|format("a", "b"))).should eq "a|b"
  end

  it "indent" do
    text = ([(["foo", "bar"] * 2).join(" ")] * 2).join "\n"
    evaluate_expression(%(foo|indent(2)), {"foo" => text}).should eq "foo bar foo bar\n  foo bar foo bar"
    evaluate_expression(%(foo|indent(2, true)), {"foo" => text}).should eq "  foo bar foo bar\n  foo bar foo bar"
  end

  describe "indent (crystal-play-0.9.42: port of real Jinja2 do_indent)" do
    # Expected outputs verified live against real Jinja2 3.1.6 AND a
    # real ansible-playbook 2.19 run with debug: msg: tasks (indent is
    # a pure string transformation, untouched by Ansible's
    # finalize/native-types customizations).
    it "does not add a trailing indent after the final newline" do
      foo = %q(\nfoo bar\n"baz"\n).gsub("\\n", "\n")
      evaluate_expression(%(foo|indent(2, false, false)), {"foo" => foo}).should eq "\n  foo bar\n  \"baz\"\n"
    end

    it "first=true indents the first line, still no trailing indent" do
      foo = %q(\nfoo bar\n"baz"\n).gsub("\\n", "\n")
      evaluate_expression(%(foo|indent(2, true, false)), {"foo" => foo}).should eq "  \n  foo bar\n  \"baz\"\n"
    end

    it "blank=true indents every line including the phantom trailing line (trailing indent IS expected)" do
      foo = %q(\nfoo bar\n"baz"\n).gsub("\\n", "\n")
      evaluate_expression(%(foo|indent(2, false, true)), {"foo" => foo}).should eq "\n  foo bar\n  \"baz\"\n  "
    end

    it "first=true indents a single-line input with no newline at all" do
      evaluate_expression(%("jinja"|indent(first=true))).should eq "    jinja"
      evaluate_expression(%("jinja"|indent(2, true))).should eq "  jinja"
    end

    it "input not ending in a newline still gets no trailing newline" do
      evaluate_expression(%("a\nb"|indent(2))).should eq "a\n  b"
    end
  end

  describe "int" do
    it "base-16" do
      evaluate_expression(%("0x4d32"|int(0, 16))).should eq "19762"
    end
    it "base-16-overwrite" do
      evaluate_expression(%("0x4d32"|int(0, 8))).should eq "19762"
    end
    it "base-8" do
      evaluate_expression(%("0o11"|int(0, 8))).should eq "9"
    end
    it "custom-fallback" do
      evaluate_expression(%(""|int(5))).should eq "5"
    end
    it "float" do
      evaluate_expression(%(3.52|int)).should eq "3"
    end
    it "force-fallback" do
      evaluate_expression(%(""|int)).should eq "0"
    end
    it "integer" do
      evaluate_expression(%(3|int)).should eq "3"
    end
    it "string" do
      evaluate_expression(%("3.52"|int)).should eq "3"
    end
    it "arbitrary-precision large number (beyond Int64)" do
      evaluate_expression(%("12345678901234567890"|int)).should eq "12345678901234567890"
    end
    it "arbitrary-precision large negative number (beyond Int64)" do
      evaluate_expression(%("-12345678901234567890123"|int)).should eq "-12345678901234567890123"
    end
    it "base kwarg interprets digits in that base" do
      evaluate_expression(%("011"|int(base=8))).should eq "9"
    end
    it "base kwarg falls back through float like do_int" do
      evaluate_expression(%("9"|int(base=8))).should eq "9"
    end
    it "accepts Python-style underscores" do
      evaluate_expression(%("1_000"|int)).should eq "1000"
    end
    it "huge float string keeps Python's exact integer" do
      evaluate_expression(%("1e300"|int)).should eq BigInt.new(1e300).to_s
    end
  end

  describe "items" do
    # Real Jinja2 3.1.6: `{{ {"a": 1, "b": 2}|items|list }}` renders
    # `[('a', 1), ('b', 2)]`; the pairs are `.items()` tuples, same
    # representation convention as `dictsort` above.
    it "yields (key, value) pairs for a Hash" do
      bindings = {"foo" => {"a" => 1, "b" => 2}}
      evaluate_expression(%(foo|items|list), bindings).should eq %([['a', 1], ['b', 2]])
    end

    # Real Jinja2's `do_items` forgives ONLY Undefined:
    # `if isinstance(value, Undefined): return` - an empty iterator,
    # no exception (verified live; real ansible-playbook's own
    # finalization rejects undefined vars at a different layer, but
    # the filter itself yields nothing).
    it "yields nothing for an Undefined target" do
      evaluate_expression(%(missing|items|list)).should eq "[]"
    end

    # Anything else that is not a Mapping raises TypeError
    # ("Can only get item pairs from a mapping.") in real Jinja2 3.1.6
    # and verbatim in real ansible-playbook 2.19 - no deprecation
    # warning, no empty fallback for non-Undefined inputs.
    it "raises TypeError for a non-Mapping target (list)" do
      expect_raises(Crinja::TypeError, "Can only get item pairs from a mapping.") do
        evaluate_expression(%([1, 2, 3]|items|list))
      end
    end

    it "raises TypeError for a non-Mapping target (string)" do
      expect_raises(Crinja::TypeError, "Can only get item pairs from a mapping.") do
        evaluate_expression(%("abc"|items|list))
      end
    end
  end

  describe "join" do
    it "join" do
      evaluate_expression(%( [1, 2, 3]|join("|") )).should eq "1|2|3"
    end

    it "joins with autoescape" do
      evaluate_expression(%( ["<foo>", "<span>foo</span>"|safe]|join ), autoescape: true).should eq "&lt;foo&gt;<span>foo</span>"
    end

    it "join_attribute" do
      evaluate_expression(%( users|join(', ', 'username') ), {"users" => [User.new("foo"), User.new("bar")]}).should eq "foo, bar"
    end
  end

  it "last" do
    evaluate_expression(%(foo|last), {foo: Range.new(0, 10, true)}).should eq "9"
  end

  describe "length" do
    it "array" do
      evaluate_expression(%([1, 2, 3, 4]|length)).should eq "4"
    end
    it "number" do
      expect_raises(Crinja::TypeError) do
        evaluate_expression(%(1234|length)).should eq ""
      end
    end
    it "object" do
      evaluate_expression(%({ "a": 1, "b": 2, "c": 3, "d": 4 }|length)).should eq "4"
    end
    it "number" do
      evaluate_expression(%('1234'|length)).should eq "4"
    end
  end

  it "lower" do
    evaluate_expression(%("Hello World" | lower)).should eq("hello world")
    evaluate_expression(%("hello world" | lower)).should eq("hello world")
  end

  it "pprint" do
    data = Range.new(0, 1000, true)
    # Real ansible-core 2.19 passes its own lazy-container types into
    # pprint, so pprint's list dispatcher (which would break the output
    # one item per line past 80 columns) never engages: a long list
    # renders as one single-line repr (verified live against
    # ansible-playbook 2.19.11).
    evaluate_expression(%(data|pprint), {data: data}).should eq "[#{data.to_a.join(", ")}]"
  end

  # Real Jinja2's do_pprint is Python's pprint.pformat, which reprs
  # strings with Python's repr() quoting: single quotes preferred, double
  # quotes only when the string contains a single quote but no double
  # quote, and escaped apostrophes when both are present.
  it "pprint quotes strings Python repr style" do
    evaluate_expression(%('foo'|pprint)).should eq "'foo'"
    evaluate_expression(%('bär'|pprint)).should eq "'bär'"
    evaluate_expression(%("it's"|pprint)).should eq %("it's")
    evaluate_expression(%('he said "hi"'|pprint)).should eq %q{'he said "hi"'}
    evaluate_expression(%('both \\' and "'|pprint)).should eq %q{'both \' and "'}
  end

  it "pprint escapes control characters Python repr style" do
    evaluate_expression(%('a\\x07b'|pprint)).should eq "'a\\x07b'"
    evaluate_expression(%('new\\nline'|pprint)).should eq "'new\\nline'"
    evaluate_expression(%('back\\\\slash'|pprint)).should eq "'back\\\\slash'"
    evaluate_expression(%('tab\\there'|pprint)).should eq "'tab\\there'"
  end

  it "pprint renders other scalar types Python repr style" do
    evaluate_expression(%(true|pprint)).should eq "True"
    evaluate_expression(%(false|pprint)).should eq "False"
    evaluate_expression(%(none|pprint)).should eq "None"
    evaluate_expression(%(42|pprint)).should eq "42"
    evaluate_expression(%(3.5|pprint)).should eq "3.5"
    evaluate_expression(%(1e20|pprint)).should eq "1e+20"
    evaluate_expression(%(1e15|pprint)).should eq "1000000000000000.0"
  end

  it "pprint renders containers Python repr style" do
    evaluate_expression(%([1, 'a', true, none]|pprint)).should eq "[1, 'a', True, None]"
    # Real ansible-core 2.19's lazy dicts bypass pprint's dict dispatcher,
    # so pprint's sort_dicts=True never engages: insertion order, not
    # vanilla pprint's sorted output (verified live).
    evaluate_expression(%({'b': 1, 'a': 2}|pprint)).should eq "{'b': 1, 'a': 2}"
    evaluate_expression(%({'k': 'v', 'n': 2}|pprint)).should eq "{'k': 'v', 'n': 2}"
    evaluate_expression(%([]|pprint)).should eq "[]"
    evaluate_expression(%({}|pprint)).should eq "{}"
    evaluate_expression(%([1]|pprint)).should eq "[1]"
  end

  it "pprint wraps a long string like pprint's string dispatcher" do
    # Verified live against real ansible-playbook 2.19.11: a long plain
    # string gets pprint's full string path (chunked reprs, parenthesized
    # at top level), unlike containers which stay single-line.
    evaluate_expression(%(s|pprint), {s: "hello world " * 8}).should eq \
      "('hello world hello world hello world hello world hello world hello world '\n 'hello world hello world ')"
  end

  it "random" do
    seq = Range.new(0, 100, true)
    10.times do
      evaluate_expression(%(seq|random), {seq: seq}).to_i.should be_in seq
    end
  end

  # Real Jinja2's `do_random` is `random.choice(seq)`: a string target is
  # an iterable of its own characters, so `{{ "1234567890"|random }}`
  # returns one of "0".."9" (differential-harness finding; the fork used
  # to raise `Cast from String to Indexable(T) failed`). Randomness can't
  # be pinned to one exact output, so assert membership over repeated
  # calls, like the existing range-target spec above.
  it "random picks a character from a string target" do
    20.times do
      evaluate_expression(%("1234567890"|random)).should be_in "1234567890".chars.map(&.to_s)
    end
  end

  it "random picks an element from a list target" do
    20.times do
      evaluate_expression(%(["a", "b", "c"]|random)).should be_in ["a", "b", "c"]
    end
  end

  # Real Jinja2's `do_random` catches the IndexError from
  # `random.choice` on an empty sequence and returns
  # `environment.undefined("No random item, sequence was empty.")`
  # (confirmed live: renders as ""), not a crash.
  it "random on an empty sequence returns Undefined" do
    evaluate_expression(%([]|random)).should eq ""
  end

  it "reverse" do
    evaluate_expression(%("foobar"|reverse)).should eq "raboof"
    evaluate_expression(%([1, 2, 3]|reverse|list)).should eq "[3, 2, 1]"
  end

  it "string" do
    list = [1, 2, 3, 4, 5]
    evaluate_expression(%(obj|string), {obj: list}).should eq list.to_s
  end

  describe "title" do
    it { evaluate_expression(%("foo bar"|title)).should eq "Foo Bar" }
    it { evaluate_expression(%("foo's bar"|title)).should eq "Foo's Bar" }
    it { evaluate_expression(%("foo   bar"|title)).should eq "Foo   Bar" }
    it { evaluate_expression(%("f bar f"|title)).should eq "F Bar F" }
    it { evaluate_expression(%("foo-bar"|title)).should eq "Foo-Bar" }
    it { evaluate_expression(%("foo\tbar"|title)).should eq "Foo\tBar" }
    it { evaluate_expression(%("FOO\tBAR"|title)).should eq "Foo\tBar" }
    it { evaluate_expression(%("foo (bar)"|title)).should eq "Foo (Bar)" }
    it { evaluate_expression(%("foo {bar}"|title)).should eq "Foo {Bar}" }
    it { evaluate_expression(%("foo [bar]"|title)).should eq "Foo [Bar]" }
    it { evaluate_expression(%("foo <bar>"|title)).should eq "Foo <Bar>" }

    it "from object" do
      evaluate_expression(%(data|title), {data: User.new("foo-bar")}).should eq "Foo-Bar"
    end
  end

  it "truncate" do
    evaluate_expression(%(data|truncate(15, true, ">>>")), {
      data:      "foobar baz bar" * 1000,
      smalldata: "foobar baz bar",
    }).should eq "foobar baz b>>>"
    evaluate_expression(%(data|truncate(15, false, ">>>")), {
      data:      "foobar baz bar" * 1000,
      smalldata: "foobar baz bar",
    }).should eq "foobar baz>>>"
    evaluate_expression(%(smalldata|truncate(15)), {
      data:      "foobar baz bar" * 1000,
      smalldata: "foobar baz bar",
    }).should eq "foobar baz bar"

    evaluate_expression(%("foo bar baz"|truncate(9))).should eq "foo bar baz"
    evaluate_expression(%("foo bar baz"|truncate(9, true))).should eq "foo bar baz"

    evaluate_expression(%("Joel is a slug"|truncate(7, true))).should eq "Joel..."
    evaluate_expression(%("Crystal"|truncate(5))).should eq "Cr..."
    evaluate_expression(%("Motorala"|truncate(length=4))).should eq "M..."
    evaluate_expression(%("Motorala"|truncate(length=6))).should eq "Motorala"
  end

  it "upper" do
    evaluate_expression(%("Hello World" | upper)).should eq("HELLO WORLD")
    evaluate_expression(%("hello world" | upper)).should eq("HELLO WORLD")
  end

  describe "urlize" do
    it "urlize" do
      evaluate_expression(%("foo http://www.example.com/ bar"|urlize)).should eq \
        %(foo <a href="http://www.example.com/" rel="noopener">) +
        %(http://www.example.com/</a> bar)
    end

    it "urlize rel policy" do
      env = Crinja.new
      env.policies["urlize.rel"] = Crinja::Value.new nil
      env.evaluate(%("foo http://www.example.com/ bar"|urlize)).should eq \
        %(foo <a href="http://www.example.com/">http://www.example.com/</a> bar)
    end

    it "urlize_target_parameter" do
      evaluate_expression(%("foo http://www.example.com/ bar"|urlize(target="_blank"))).should eq \
        %(foo <a href="http://www.example.com/" rel="noopener" target="_blank">) +
        %(http://www.example.com/</a> bar)
    end

    # Expected outputs verified live against real Jinja2 3.1.6 and a real
    # ansible-playbook 2.19 run (both render identically).
    it "urlize bare domain" do
      evaluate_expression(%("foo example.org bar"|urlize)).should eq \
        %(foo <a href="https://example.org" rel="noopener">example.org</a> bar)
      evaluate_expression(%("foo www.example.com bar"|urlize)).should eq \
        %(foo <a href="https://www.example.com" rel="noopener">www.example.com</a> bar)
    end

    it "urlize unknown scheme is not linkified without extra_schemes" do
      evaluate_expression(%("foo ftp://localhost bar"|urlize)).should eq "foo ftp://localhost bar"
    end

    it "urlize mailto" do
      evaluate_expression(%("foo mailto:email@example.com bar"|urlize)).should eq \
        %(foo <a href="mailto:email@example.com">email@example.com</a> bar)
    end

    it "urlize bare email" do
      evaluate_expression(%("foo email@example.com bar"|urlize)).should eq \
        %(foo <a href="mailto:email@example.com">email@example.com</a> bar)
    end

    it "urlize nofollow is sorted before noopener" do
      evaluate_expression(%("foo http://www.example.com/ bar"|urlize(nofollow=true))).should eq \
        %(foo <a href="http://www.example.com/" rel="nofollow noopener">) +
        %(http://www.example.com/</a> bar)
    end

    it "urlize escapes html entities in url" do
      evaluate_expression(%("foo http://example.com/path?a=1&b=2 bar"|urlize)).should eq \
        %(foo <a href="http://example.com/path?a=1&amp;b=2" rel="noopener">) +
        %(http://example.com/path?a=1&amp;b=2</a> bar)
    end

    it "urlize does not run the HTTP URL regex on over-long tokens" do
      # Backtracking guard: word tokens longer than 256 characters are
      # never matched against HTTP_URL_RE, so a crafted almost-URL
      # cannot trigger catastrophic regex backtracking. Real Jinja2
      # would still linkify a long http:// URL; this fork trades that
      # for the guard (see PATCHES.md, crystal-play-0.9.57).
      long_url = "http://example.com/" + ("a" * 300)
      evaluate_expression(%("foo #{long_url} bar"|urlize)).should eq("foo #{long_url} bar")
      almost_url = ("a." * 130) + "aaa"
      evaluate_expression(%("foo #{almost_url} bar"|urlize)).should eq("foo #{almost_url} bar")
    end

    it "urlize trim_url_limit truncates display after limit chars" do
      evaluate_expression(%("foo http://example.com/verylongurlthatgoesonandonandon bar"|urlize(trim_url_limit=20))).should eq \
        %(foo <a href="http://example.com/verylongurlthatgoesonandonandon" rel="noopener">) +
        %(http://example.com/v...</a> bar)
    end

    it "urlize extra_schemes" do
      evaluate_expression(
        %("foo tel:+1-514-555-1234 ftp://localhost bar"|urlize(extra_schemes=["tel:", "ftp:"]))
      ).should eq \
        %(foo <a href="tel:+1-514-555-1234" rel="noopener">tel:+1-514-555-1234</a> ) +
        %(<a href="ftp://localhost" rel="noopener">ftp://localhost</a> bar)
    end
  end

  it "wordcount" do
    evaluate_expression(%("foo bar baz"|wordcount)).should eq "3"
  end

  it "chaining" do
    evaluate_expression(%(['<foo>', '<bar>']|first|upper|escape)).should eq "&lt;FOO&gt;"
  end

  describe "sum" do
    it "sums" do
      evaluate_expression(%([1, 2, 3, 4, 5, 6]|sum)).should eq "21"
    end

    it "sums attribute" do
      values = [{"value" => 23}, {"value" => 1}, {"value" => 18}]
      evaluate_expression(%(values|sum('value')), {values: values}).should eq "42"
    end

    it "sums attributes nested" do
      values = [{"real": {"value" => 23}}, {"real": {"value" => 1}}, {"real": {"value" => 18}}]
      evaluate_expression(%(values|sum('real.value')), {values: values}).should eq "42"
    end

    it "sums attributes of pairs" do
      # Attribute-indexed sum means "resolve this attribute/index on each
      # ELEMENT". A bare dict iterates its KEYS (Python semantics), so the
      # pair-indexing shape needs an actual list of pairs.
      values = [["foo", 23], ["bar", 1], ["baz", 18]]
      evaluate_expression(%(values|sum('1')), {values: values}).should eq "42"
    end
  end

  describe "abs" do
    it "works with integer" do
      evaluate_expression(%(1 | abs)).should eq("1")
    end

    it "works with float" do
      evaluate_expression(%(-12.5 | abs)).should eq("12.5")
    end

    it "fails with string" do
      expect_raises(Crinja::Arguments::Error) do
        evaluate_expression(%("1" | abs))
      end
    end
  end

  it "round" do
    evaluate_expression(%(2.7|round)).should eq "3.0"
    evaluate_expression(%(2.1|round)).should eq "2.0"
    evaluate_expression(%(2.1234|round(3, 'floor'))).should eq "2.123"
    evaluate_expression(%(2.1|round(0, 'ceil'))).should eq "3.0"
    evaluate_expression(%(2|round(0, 'ceil'))).should eq "2.0"

    evaluate_expression(%(21.3|round(-1))).should eq "20.0"
    evaluate_expression(%(21.3|round(-1, 'ceil'))).should eq "30.0"
    evaluate_expression(%(21.3|round(-1, 'floor'))).should eq "20.0"
  end

  it "xmlattr" do
    kvpairs = evaluate_expression(%({'foo': 42, 'bar': 23, 'fish': none, ) \
                                  %('spam': missing, 'blub:blub': '<?>'}|xmlattr)).split(' ')

    kvpairs.should contain %(foo="42")
    kvpairs.should contain %(bar="23")
    kvpairs.should contain %(blub:blub="&lt;?&gt;")
    kvpairs.size.should eq 4
  end

  describe "sort" do
    it do
      evaluate_expression(%([2, 3, 1]|sort)).should eq "[1, 2, 3]"
      evaluate_expression(%([2, 3, 1]|sort(true))).should eq "[3, 2, 1]"
      evaluate_expression(%(["c", "A", "b", "D"]|sort|join)).should eq "AbcD"
      evaluate_expression(%(["c", "A", "b", "D"]|sort(case_sensitive=true)|join)).should eq "ADbc"
      evaluate_expression(%(['foo', 'Bar', 'blah']|sort)).should eq %(['Bar', 'blah', 'foo'])
    end

    it "custom_sort" do
      users = [
        IdUser.new(3, "mike"),
        IdUser.new(1, "john"),
        IdUser.new(4, "mick"),
        IdUser.new(2, "jane"),
      ]
      evaluate_expression(%(users|sort(attribute='id')|join(",")), {users: users}).should eq "john,jane,mike,mick"
    end
  end

  describe "groupby" do
    it "basic" do
      render(<<-'TPL'
        {%- for grouper, list in [{'foo': 1, 'bar': 2},
                                  {'foo': 2, 'bar': 3},
                                  {'foo': 1, 'bar': 1},
                                  {'foo': 3, 'bar': 4}]|groupby('foo') -%}
        {{ grouper }}{% for x in list %}: {{ x.foo }}, {{ x.bar }}{% endfor %}|
        {%- endfor %}
        TPL
      ).should eq "1: 1, 2: 1, 1|2: 2, 3|3: 3, 4|"
    end

    it "tuple_index" do
      render(<<-'TPL'
        {%- for grouper, list in [('a', 1), ('a', 2), ('b', 1)]|groupby(0) -%}
        {{ grouper }}{% for x in list %}:{{ x.1 }}{% endfor %}|
        {%- endfor %}
        TPL
      ).should eq "a:1:2|b:1|"
    end

    it "multidot" do
      articles = [
        Article.new("aha", 1, 1, 1970),
        Article.new("interesting", 2, 1, 1970),
        Article.new("really?", 3, 1, 1970),
        Article.new("totally not", 1, 1, 1971),
      ]
      render(<<-'TPL',
        {%- for year, list in articles|groupby('date.year') -%}
        {{ year }}{% for x in list %}[{{ x.title }}]{% endfor %}|
        {%- endfor %}
        TPL
        {articles: articles}).should eq "1970[aha][interesting][really?]|1971[totally not]|"
    end

    # Expected outputs verified live against real Jinja2 3.1.6's own
    # `do_groupby` (sorted + itertools.groupby, case-folded key unless
    # case_sensitive=true).
    it "case_insensitive (default) merges case-variant keys into one sorted group" do
      bindings = {"data" => [{"k" => "a", "v" => 1}, {"k" => "b", "v" => 2}, {"k" => "A", "v" => 3}]}
      render(<<-'TPL',
        {%- for k, vs in data|groupby('k', case_sensitive=false) -%}
        {{ k }}: {{ vs|map(attribute='v')|join(', ') }}|
        {%- endfor %}
        TPL
        bindings).should eq "a: 1, 3|b: 2|"
    end

    it "case_sensitive keeps case-variant keys separate, sorted by raw value" do
      bindings = {"data" => [{"k" => "a", "v" => 1}, {"k" => "b", "v" => 2}, {"k" => "A", "v" => 3}]}
      render(<<-'TPL',
        {%- for k, vs in data|groupby('k', case_sensitive=true) -%}
        {{ k }}: {{ vs|map(attribute='v')|join(', ') }}|
        {%- endfor %}
        TPL
        bindings).should eq "A: 3|a: 1|b: 2|"
    end

    it "default catches an item missing the attribute into that named group" do
      bindings = {"users" => [{"name" => "emma", "city" => "NY"}, {"name" => "smith", "city" => "WA"}, {"name" => "john"}]}
      render(<<-'TPL',
        {%- for city, items in users|groupby('city', default='NY') -%}
        {{ city }}: {{ items|map(attribute='name')|join(', ') }}|
        {%- endfor %}
        TPL
        bindings).should eq "NY: emma, john|WA: smith|"
    end

    it "missing attribute without default raises UndefinedError" do
      bindings = {"users" => [{"name" => "emma", "city" => "NY"}, {"name" => "john"}]}
      expect_raises(Crinja::UndefinedError) do
        render(<<-'TPL',
          {%- for city, items in users|groupby('city') -%}
          {{ city }}: {{ items|map(attribute='name')|join(', ') }}|
          {%- endfor %}
          TPL
          bindings)
      end
    end

    it "grouper and list are accessible as attributes" do
      bindings = {"users" => [{"name" => "emma", "city" => "NY"}, {"name" => "smith", "city" => "WA"}]}
      render(<<-'TPL',
        {%- for g in users|groupby('city') -%}
        {{ g.grouper }}: {{ g.list|map(attribute='name')|join(', ') }}|
        {%- endfor %}
        TPL
        bindings).should eq "NY: emma|WA: smith|"
    end
  end

  it "replace" do
    evaluate_expression(%(string|replace("o", 42)), {string: "<foo>"}).should eq "<f4242>"
    evaluate_expression(%(string|replace("o", 42)), {string: "<foo>"}, autoescape: true).should eq "&lt;f4242&gt;"
    evaluate_expression(%(string|replace("<", 42)), {string: "<foo>"}, autoescape: true).should eq "42foo&gt;"
    evaluate_expression(%(string|replace("o", ">x<")), {string: Crinja::SafeString.new("foo")}, autoescape: true).should eq "f&gt;x&lt;&gt;x&lt;"
  end

  it "forceescape" do
    evaluate_expression(%(x|forceescape), {x: Crinja::SafeString.new("<div />")}).should eq "&lt;div /&gt;"
  end

  it "safe" do
    evaluate_expression(%("<div>foo</div>"|safe), autoescape: true).should eq "<div>foo</div>"
    evaluate_expression(%("<div>foo</div>"), autoescape: true).should eq "&lt;div&gt;foo&lt;/div&gt;"
  end

  it "urlencode" do
    evaluate_expression(%("Hello, world!"|urlencode), autoescape: true).should eq "Hello%2C%20world%21"

    evaluate_expression(%(o|urlencode), {o: "Hello, world\u203d"}, autoescape: true).should eq "Hello%2C%20world%E2%80%BD"
    evaluate_expression(%(o|urlencode), {o: {0 => 1}}, autoescape: true).should eq "0=1"
    evaluate_expression(%(o|urlencode), {o: [{"f", 1}]}, autoescape: true).should eq "f=1"
    evaluate_expression(%(o|urlencode), {o: [{"f", 1}, {"z", 2}]}, autoescape: true).should eq "f=1&amp;z=2"
    evaluate_expression(%(o|urlencode), {o: [{"\u203d", 1}]}, autoescape: true).should eq "%E2%80%BD=1"
    evaluate_expression(%(o|urlencode), {o: {"\u203d": 1}}, autoescape: true).should eq "%E2%80%BD=1"
  end

  describe "map" do
    it "simple_map" do
      evaluate_expression(%(["1", "2", "3"]|map("int")|sum)).should eq "6"
    end

    it "attribute_map" do
      users = [
        User.new("john"),
        User.new("jane"),
        User.new("mike"),
      ]
      evaluate_expression(%(users|map(attribute="username")|join("|")), {users: users}).should eq "john|jane|mike"
    end

    it "empty_map" do
      evaluate_expression(%(none|map("upper")|list)).should eq "[]"
    end
  end

  describe "select/reject" do
    it "simple_select" do
      evaluate_expression(%([1, 2, 3, 4, 5]|select("odd")|join("|"))).should eq "1|3|5"
    end

    it "bool_select" do
      evaluate_expression(%([none, false, 0, 1, 2, 3, 4, 5]|select|join("|"))).should eq "1|2|3|4|5"
    end

    it "simple_reject" do
      evaluate_expression(%([1, 2, 3, 4, 5]|reject("odd")|join("|"))).should eq "2|4"
    end

    it "bool_reject" do
      evaluate_expression(%([none, false, 0, 1, 2, 3, 4, 5]|reject|join("|"))).should eq "None|False|0"
    end

    it "simple_select_attr" do
      users = [
        User.new("john", true),
        User.new("jane", true),
        User.new("mike", false),
      ]
      evaluate_expression(%(users|selectattr("is_active")|map(attribute="username")|join("|")), {users: users}).should eq "john|jane"
    end

    it "simple_reject_attr" do
      users = [
        User.new("john", true),
        User.new("jane", true),
        User.new("mike", false),
      ]
      evaluate_expression(%(users|rejectattr("is_active")|map(attribute="username")|join("|")), {users: users}).should eq "mike"
    end

    it "func_select_attr" do
      users = [
        IdUser.new(1, "john"),
        IdUser.new(2, "jane"),
        IdUser.new(3, "mike"),
      ]
      evaluate_expression(%(users|selectattr("id", "odd")|map(attribute="name")|join("|")),
        {users: users}).should eq "john|mike"
    end

    # Real Jinja2 3.1.6 registers the operator spellings (`"=="`, `"!="`,
    # `"<"`, `"<="`, `">"`, `">="`) as bare test names in its TESTS dict,
    # so `selectattr("id", "==", 2)` is plain core-Jinja2.
    it "operator spelling test names in selectattr" do
      users = [
        IdUser.new(1, "john"),
        IdUser.new(2, "jane"),
        IdUser.new(3, "mike"),
      ]
      evaluate_expression(%(users|selectattr("id", "==", 2)|map(attribute="name")|join("|")),
        {users: users}).should eq "jane"
      evaluate_expression(%(users|selectattr("id", "!=", 2)|map(attribute="name")|join("|")),
        {users: users}).should eq "john|mike"
      evaluate_expression(%(users|selectattr("id", "<", 3)|map(attribute="name")|join("|")),
        {users: users}).should eq "john|jane"
      evaluate_expression(%(users|selectattr("id", "<=", 2)|map(attribute="name")|join("|")),
        {users: users}).should eq "john|jane"
      evaluate_expression(%(users|selectattr("id", ">", 2)|map(attribute="name")|join("|")),
        {users: users}).should eq "mike"
      evaluate_expression(%(users|selectattr("id", ">=", 2)|map(attribute="name")|join("|")),
        {users: users}).should eq "jane|mike"
    end

    it "func_reject_attr" do
      users = [
        IdUser.new(1, "john"),
        IdUser.new(2, "jane"),
        IdUser.new(3, "mike"),
      ]
      evaluate_expression(%(users|rejectattr("id", "odd")|map(attribute="name")|join("|")),
        {users: users}).should eq "jane"
    end

    it "dotted_attr_select_reject" do
      stats = [
        {"stat" => {"exists" => true}},
        {"stat" => {"exists" => false}},
        {"stat" => {"exists" => true}},
      ]
      evaluate_expression(%(stats|selectattr("stat.exists")|length), {stats: stats}).should eq "2"
      evaluate_expression(%(stats|rejectattr("stat.exists")|length), {stats: stats}).should eq "1"
      evaluate_expression(%(stats|map(attribute="stat.exists")|join("|")), {stats: stats}).should eq "True|False|True"
    end

    it "dotted_attr_select_reject_undefined" do
      stats = [
        {"stat" => {"exists" => false}},
        {"stat" => {"gone" => true}},
      ]
      evaluate_expression(%(stats|selectattr("stat.exists")|length), {stats: stats}).should eq "0"
      evaluate_expression(%(stats|rejectattr("stat.exists")|length), {stats: stats}).should eq "2"
    end
  end

  describe "json_dump" do
    it "json_dump" do
      # original jinja2
      evaluate_expression(%(x|tojson), {x: {"foo" => "bar"}}, autoescape: true).should eq "{\n&#34;foo&#34;: &#34;bar&#34;\n}"
      # evaluate_expression(%(x|tojson), {x: %("bar')}, autoescape: true).should eq "&#34;&#34;bar\u0027&#34;"
      evaluate_expression(%(x|tojson), {x: %("bar')}, autoescape: true).should eq "&#34;\\&#34;bar&#39;&#34;"
    end

    pending "policies" do
      env = Crinja.new
      env.config.autoescape = true
      env.policies["json.dumps_function"] = Crinja.function do
        arguments.kwargs.should eq({"foo", "bar"})
        42
      end
      env.policies["json.dumps_kwargs"] = Crinja.value({"foo" => "bar"})
      env.evaluate(%(x|tojson), {x: 23}).should eq "42"
    end
  end

  it "attr" do
    evaluate_expression(%(data | attr("foo")), {data: {"foo" => "bar"}}).should eq "bar"
    evaluate_expression(%(arr | attr(0)), {arr: ["bar"]}).should eq ""
  end

  describe "list" do
    it "retuns array" do
      evaluate_expression(%([1, 2] | list)).should eq "[1, 2]"
    end
    it "splits string" do
      evaluate_expression(%("abc" | list)).should eq %(['a', 'b', 'c'])
    end
    it "fails for number" do
      expect_raises(Crinja::TypeError) do
        evaluate_expression(%(1 | list))
      end
    end
  end

  it "trim" do
    evaluate_expression(%("  foo. \n"|trim)).should eq "foo."
  end

  describe "trim with chars= (crystal-play-0.9.42: real Jinja2 do_trim(value, chars=None))" do
    # Expected outputs verified live against real Jinja2 3.1.6 AND a
    # real ansible-playbook 2.19 run: an explicit chars= argument is
    # Python str.strip(chars) semantics - it strips ONLY the given
    # characters from both ends, leaving any other leading/trailing
    # characters (spaces) untouched. Previously chars= was ignored
    # entirely and the whitespace-stripping result was returned.
    it "strips only chars, leaving surrounding spaces untouched" do
      evaluate_expression(%(foo|trim(chars)), {"foo" => " ..stays..", "chars" => "."}).should eq " ..stays"
    end

    it "strips only chars from each end" do
      evaluate_expression(%(foo|trim(chars)), {"foo" => " .stays", "chars" => "."}).should eq " .stays"
    end

    it "accepts chars positionally" do
      evaluate_expression(%("..x.."|trim("."))).should eq "x"
    end
  end

  describe "trim with chars= (crystal-play-0.9.42: real Jinja2 do_trim(value, chars=None))" do
    # Expected outputs verified live against real Jinja2 3.1.6 AND a
    # real ansible-playbook 2.19 run: an explicit chars= argument is
    # Python str.strip(chars) semantics - it strips ONLY the given
    # characters from both ends, leaving any other leading/trailing
    # characters (spaces) untouched. Previously chars= was ignored
    # entirely and the whitespace-stripping result was returned.
    it "strips only chars, leaving surrounding spaces untouched" do
      evaluate_expression(%(foo|trim(chars)), {"foo" => " ..stays..", "chars" => "."}).should eq " ..stays"
    end

    it "strips only chars from each end" do
      evaluate_expression(%(foo|trim(chars)), {"foo" => " .stays", "chars" => "."}).should eq " .stays"
    end

    it "accepts chars positionally" do
      evaluate_expression(%("..x.."|trim("."))).should eq "x"
    end
  end

  describe "wordwrap" do
    it "packs whole words onto each line, matching Python's own textwrap.wrap (what real Jinja2's wordwrap filter actually calls) - not fixed-width character chunking" do
      # Verified against real Python textwrap.wrap output directly, not
      # assumed: found via krikri's own robertdebock.functions
      # benchmark round - the previous fixed-width-chunk implementation
      # gave a completely different output shape for anything but
      # single-character "words".
      evaluate_expression(%(s|wordwrap), {s: "a" * 79}).should eq "a" * 79
      evaluate_expression(%(s|wordwrap), {s: "a" * 80}).split('\n').should eq ["a" * 79, "a"]
      evaluate_expression(%(s|wordwrap(10)), {s: "foo " * 3}).split('\n').should eq ["foo foo", "foo"]
      evaluate_expression(%(s|wordwrap), {s: "foo " * 20}).split('\n').should eq [Array.new(20, "foo").join(" ")]
      evaluate_expression(%(s|wordwrap(10, false)), {s: "foo " * 3}).split('\n').should eq ["foo foo", "foo"]
      # A long word continuing onto an already-non-empty line needs its
      # own separating space counted against the remaining width - "A"
      # + "regular"[...width] wrapped at 5 is "A reg", not "Aregu".
      evaluate_expression(%(s|wordwrap(5)), {s: "A regular line."}).split('\n').should eq ["A reg", "ular", "line."]
      # When only the separator itself fits (no room for any word
      # characters), the line still ends with a trailing space and none
      # of the word - real textwrap does this too.
      evaluate_expression(%(s|wordwrap(5)), {s: "A line with integers. 1, 2 & 3."}).split('\n').should eq ["A", "line", "with ", "integ", "ers.", "1, 2", "& 3."]
    end
  end
  # crystal-play-0.9.25: a bare dict iterates its KEYS (Python
  # semantics) for every consumer of Value#each/to_a. These pin the
  # behaviors krikri-playbook verified against real ansible-core 2.19.
  it "list filter on a dict yields keys" do
    evaluate_expression(%(d|list), {"d" => {"b" => 2, "a" => 1}}).should eq "['b', 'a']"
  end

  it "join filter on a dict joins keys" do
    evaluate_expression(%(d|join(',')), {"d" => {"b" => 2, "a" => 1}}).should eq "b,a"
  end

  it "first/last on a dict yield keys" do
    evaluate_expression(%(d|first), {"d" => {"b" => 2, "a" => 1}}).should eq "b"
    evaluate_expression(%(d|last), {"d" => {"b" => 2, "a" => 1}}).should eq "a"
  end

  it "min/max on a dict compare keys" do
    evaluate_expression(%(d|min), {"d" => {"b" => 2, "a" => 1, "c" => 3}}).should eq "a"
    evaluate_expression(%(d|max), {"d" => {"b" => 2, "a" => 1, "c" => 3}}).should eq "c"
  end

  it "min/max compare strings case-insensitively by default" do
    evaluate_expression(%(["a", "B"]|min)).should eq "a"
    evaluate_expression(%(["a", "B"]|max)).should eq "B"
    evaluate_expression(%(["B", "a"]|min)).should eq "a"
    evaluate_expression(%(["B", "a"]|max)).should eq "B"
  end

  it "min/max return the first item on case-insensitive ties" do
    evaluate_expression(%(["a", "A"]|min)).should eq "a"
    evaluate_expression(%(["a", "A"]|max)).should eq "a"
  end

  it "min/max respect an explicit case_sensitive=true" do
    evaluate_expression(%(["a", "B"]|min(case_sensitive=true))).should eq "B"
    evaluate_expression(%(["a", "B"]|max(case_sensitive=true))).should eq "a"
    evaluate_expression(%(["a", "A"]|min(case_sensitive=true))).should eq "A"
    evaluate_expression(%(["a", "A"]|max(case_sensitive=true))).should eq "a"
  end

  it "min/max on numbers is unaffected by case-insensitive keying" do
    evaluate_expression(%([3, 1, 2]|min)).should eq "1"
    evaluate_expression(%([3, 1, 2]|max)).should eq "3"
  end

  it "unique on a dict yields keys" do
    evaluate_expression(%(d|unique|list), {"d" => {"b" => 2, "a" => 1}}).should eq "['b', 'a']"
  end

  it "map on a dict maps over keys" do
    evaluate_expression(%(d|map('upper')|list), {"d" => {"b" => 2, "a" => 1}}).should eq "['B', 'A']"
  end

  it "select on a dict filters keys" do
    evaluate_expression(%(d|select('string')|list), {"d" => {"b" => 2, "a" => 1}})
      .should eq "['b', 'a']"
  end

  it "reverse on a dict reverses keys" do
    evaluate_expression(%(d|reverse|list), {"d" => {"b" => 2, "a" => 1, "c" => 3}}).should eq "['c', 'a', 'b']"
  end

  # crystal-play-0.9.26: ansible-core's native-types finalization converts
  # tuples to lists at every rendered-output position - a `{{ d1 |
  # dictsort }}` interpolated into text must produce bracketed nested
  # lists, not paren-reprs (verified against real ansible-core 2.19.4:
  # `{{ (1, 2) }}` -> `[1, 2]`, `{{ {'k': (1, 2)} }}` -> `{'k': [1, 2]}`).
  it "stringifies a Crinja::Tuple as a bracketed list, not parens" do
    tuple = Crinja::Tuple.from({Crinja::Value.new("a"), Crinja::Value.new(1)})
    Crinja::Finalizer.stringify(tuple).should eq("['a', 1]")
  end

  it "dictsort nested inside a dict value renders as bracketed lists" do
    evaluate_expression(%({'k': (foo|dictsort)}), {"foo" => {"a" => 1}})
      .should eq %({'k': [['a', 1]]})
  end

  # crystal-play-0.9.27: `| string` is Python str() BEFORE ansible-core's
  # native-types tuple->list conversion - the one place a tuple keeps its
  # paren repr (verified against real ansible-core 2.19.4:
  # `{{ d1 | dictsort | string }}` -> `[('a', 1), ('b', 2)]`).
  it "string filter keeps Python str() paren repr for tuples" do
    evaluate_expression(%(foo|dictsort|string), {"foo" => {"b" => 2, "a" => 1}})
      .should eq "[('a', 1), ('b', 2)]"
  end

  it "string filter on a bare tuple renders parens" do
    evaluate_expression(%(foo|dictsort|first|string), {"foo" => {"a" => 1}})
      .should eq "('a', 1)"
  end

end
