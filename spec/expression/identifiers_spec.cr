require "../spec_helper"

describe "expressions with identifiers" do
  it "resolves a simple variable lookup" do
    expression = Crinja::AST::IdentifierLiteral.new("foo")

    env = Crinja.new
    env.context.merge!({"foo" => "bar"})

    env.evaluate(expression).should eq Crinja::Value.new("bar")
  end

  it "resolves lookup sequence" do
    evaluate_expression(%(posts[0].user.name), {"posts" => [{"user" => {"name" => "Barry"}}]}).should eq("Barry")
  end

  it "resolves IndexExpression" do
    evaluate_expression_raw(%(posts[0]), {"posts" => [true]}).should be_true
  end

  # Chained access on an already-undefined base (IndexExpression,
  # MemberExpression, or a mix of both) no longer raises partway through
  # the chain - it self-propagates as Undefined all the way to the final
  # result instead, matching real Ansible's own Jinja environment
  # (`Marker.__getattr__`/`__getitem__` self-propagate: "Raises
  # AttributeError for dunder-looking accesses, self-propagates
  # otherwise" - verified directly against ansible-core's
  # `_internal/_templating/_jinja_common.py`). This is what makes the
  # extremely common `x.y.z | default(fallback)` idiom work when x/y/z
  # don't exist - `default()` only needs to see that its own left-hand
  # value is undefined, and never has to force the fallback expression's
  # OWN undefined chain into a concrete value along the way. See
  # PATCHES.md's 0.9.8 entry for the real-world bug this was found
  # fixing (krikri round 41, robertdebock.haproxy's own
  # `server.address | default(hostvars[server.name][...])` template).
  it "self-propagates as Undefined, not a raise, when the base of an IndexExpression is undefined" do
    evaluate_expression(%(posts[0].user.name)).should eq("")
  end

  it "self-propagates as Undefined, not a raise, when the base of a MemberExpression is undefined" do
    result = evaluate_expression_raw(%(posts[0].user.name), {"posts" => [] of Crinja::Value})
    result.should be_a(Crinja::Undefined)
  end

  it "self-propagates as Undefined, not a raise, through a MemberExpression/MemberExpression chain" do
    result = evaluate_expression_raw(%(posts[0].user.name), {"posts" => [true]})
    result.should be_a(Crinja::Undefined)
  end

  it "returns lookup name in Undefined" do
    undefined = evaluate_expression_raw(%(posts[0].user.name), {"posts" => [{"user" => nil}]}).as(Crinja::Undefined)
    undefined.name.should eq "posts[0].user.name"
  end
end
