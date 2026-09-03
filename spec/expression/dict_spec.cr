require "../spec_helper"

describe Crinja::AST::DictLiteral do
  it "parses dict" do
    evaluate_expression(%({ "foo": "bar", target: "world" }), {"target" => "hello"}).should eq(%({'foo': 'bar', 'hello': 'world'}))
  end

  it "parses dict at end of expression" do
    render(%({{ { "foo": "bar" }}})).should eq %({'foo': 'bar'})
  end

  it "parses \"}}}\" at end of expression" do
    render(%({{ "foo" }}})).should eq %(foo})
  end

  it "supports .copy() as a real Python dict method, returning an independent shallow copy" do
    # Found via krikri's own ipr-cnrs.nftables role:
    # `nft_global_default_rules.copy()` rendered "... .copy is
    # undefined" outright - plain Hash had no crinja_call entry for
    # "copy" at all (only keys/values/items/get were implemented).
    render(%({{ {"a": 1}.copy() }})).should eq %({'a': 1})
  end
end
