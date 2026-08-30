require "../spec_helper"

# Tests based on https://github.com/pallets/jinja/blob/d905cf0b6c6121d900ea384f72970b862c879bc7/tests/test_tests.py

describe Crinja::Test do
  describe "callable" do
    it "should find callable" do
      evaluate_expression(%(foo is callable), {"foo" => Crinja.function() { }}).should eq("True")
    end

    it "should find not callable" do
      evaluate_expression(%(foo is callable), {"foo" => "bar"}).should eq("False")
    end
  end

  it "defined" do
    render(%({{ missing is defined }}|{{ true is defined }})).should eq "False|True"
  end

  it "not" do
    render(%({{ missing is not defined }}|{{ true is not defined }})).should eq "True|False"
  end

  it "even" do
    render(%({{ 1 is even }}|{{ 2 is even }})).should eq "False|True"
  end

  it "odd" do
    render(%({{ 1 is odd }}|{{ 2 is odd }})).should eq "True|False"
  end

  it "lower" do
    render(%({{ "foo" is lower }}|{{ "FOO" is lower }})).should eq "True|False"
  end

  it "upper" do
    render(%({{ "FOO" is upper }}|{{ "foo" is upper }})).should eq "True|False"
  end

  it "equalto" do
    render(
      %({{ foo is equalto 12 }}|{{ foo is equalto 0 }}|{{ foo is equalto (3 * 4) }}|) \
      %({{ bar is equalto "baz" }}|{{ bar is equalto "zab" }}|{{ bar is equalto ("ba" + "z") }}|) \
      %({{ bar is equalto bar }}|{{ bar is equalto foo }}),
      {:foo => 12, :bar => "baz"}).should eq "True|False|True|True|False|True|True|False"
  end

  it "sequence" do
    render(%({{ [1, 2, 3] is sequence }}|{{ "foo" is sequence }}|{{ 42 is sequence }})).should eq "True|True|False"
  end

  it "sameas" do
    render(%({{ foo is sameas false }}|{{ 0 is sameas false }}), {:foo => false}).should eq "True|False"
  end

  describe "typechecks" do
    it { evaluate_expression(%( 42 is undefined )).should eq "False" }
    it { evaluate_expression(%( 42 is defined )).should eq "True" }
    it { evaluate_expression(%( 42 is none )).should eq "False" }
    it { evaluate_expression(%( none is none )).should eq "True" }
    it { evaluate_expression(%( 42 is number )).should eq "True" }
    it { evaluate_expression(%( 42 is string )).should eq "False" }
    it { evaluate_expression(%( "foo" is string )).should eq "True" }
    it { evaluate_expression(%( "foo" is sequence )).should eq "True" }
    it { evaluate_expression(%( [1] is sequence )).should eq "True" }
    it { evaluate_expression(%( range is callable )).should eq "True" }
    it { evaluate_expression(%( 42 is callable )).should eq "False" }
    it { evaluate_expression(%( range(5) is iterable )).should eq "True" }
    it { evaluate_expression(%( {} is mapping )).should eq "True" }
    it { evaluate_expression(%( mydict is mapping ), {:mydict => Crinja::Variables.new}).should eq "True" }
    it { evaluate_expression(%( [] is mapping )).should eq "False" }
    it { evaluate_expression(%( 10 is number )).should eq "True" }
    it { evaluate_expression(%( (10 ** 2) is number )).should eq "True" }
    it { evaluate_expression(%( 3.14159 is number )).should eq "True" }
  end

  # TODO: Implementation of complex numbers?
  pending "complex number" do
    evaluate_expression(%( complex is number ), {:complex => 0.0}).should eq "True"
  end

  it "greaterthan" do
    render(%({{ 1 is greaterthan 0 }}|{{ 0 is greaterthan 1 }})).should eq "True|False"
  end

  it "lessthan" do
    render(%({{ 0 is lessthan 1 }}|{{ 1 is lessthan 0 }})).should eq "True|False"
  end

  it "no_paren_for_arg1" do
    evaluate_expression(%(foo is sameas none), {:foo => nil}).should eq "True"
  end

  it "escaped" do
    render(%({{ x is escaped }}|{{ y is escaped }}), {:x => "foo", :y => Crinja::SafeString.escape("foo")}, autoescape: true).should eq "False|True"
  end

  it "in" do
    render(
      %({{ "o" is in "foo" }}|{{ "foo" is in "foo" }}|{{ "b" is in "foo" }}|) \
      %({{ 1 is in [1, 2] }}|) \
      %({{ 3 is in [1, 2] }}|{{ "foo" is in {"foo": 1} }}|{{ "baz" is in {"bar": 1} }}|) \
      %({{ 1 is in ((1, 2)) }}|{{ 3 is in ((1, 2)) }})
    ).should eq("True|True|False|" \
                "True|False|True|False|" \
                "True|False")
  end

  it "error in plus list" do
    evaluate_expression(%(1 is in [1, 2])).should eq "True"
  end

  describe "divisibleby" do
    it "should be true" do
      evaluate_expression(%(56 is divisibleby(7))).should eq("True")
    end
    it "should be false" do
      evaluate_expression(%(57 is divisibleby(7))).should eq("False")
    end
  end

  describe "multi-arg parenthesized test call" do
    # `is name(arg1, arg2)` never consumed the opening `(` at all (the
    # `!is_test &&` guard in expression_parser.cr's filter/test-suffix
    # loop only ever set with_parenthesis: true for a FILTER, never a
    # TEST) - the whole `(arg1, arg2)` was then reparsed from scratch as
    # a single parenthesized tuple-literal EXPRESSION (parse_literal's
    # own `Kind::LEFT_PAREN` branch), landing as ONE positional argument
    # instead of two. A test declared with 2 keyword args (like a real
    # krikri caller's `version(compare_to, operator)`) received
    # the whole tuple packed into the FIRST arg and never saw the
    # second at all - silently defaulting it instead of raising, so this
    # was invisible unless you specifically checked the second arg's
    # value. Found downstream in krikri benchmarking
    # prometheus.prometheus.prometheus's own `is version('2.7.0', '>=')`
    # idiom.
    it "binds both parenthesized positional arguments separately, not as one tuple" do
      Crinja.test({a: 0, b: 0}, :two_arg_probe) { arguments["a"].to_i == 3 && arguments["b"].to_i == 4 }
      evaluate_expression(%(0 is two_arg_probe(3, 4))).should eq("True")
    end
  end

  it "test_custom_test" do
    items = [] of ::Tuple(String, String)
    matching = Crinja.test({x: nil}) { items << {target.as_s, arguments["x"].as_s}; false }

    env = Crinja.new
    env.tests["matching"] = matching
    tmpl = env.from_string("{{ ('us-west-1' is matching '(us-east-1|ap-northeast-1)') " \
                           "or 'stage' is matching '(dev|stage)' }}"
    )
    tmpl.render.should eq "False"
    items.should eq [{"us-west-1", "(us-east-1|ap-northeast-1)"},
                     {"stage", "(dev|stage)"}]
  end
end
