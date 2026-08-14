require "../spec_helper"

describe Crinja::Finalizer do
  it "stringifies a Hash using real Python/Jinja2 dict repr (colon, not Crystal's =>)" do
    Crinja::Finalizer.stringify({"a" => 1, "b" => 2}).should eq(%({'a': 1, 'b': 2}))
  end

  it "stringifies a nested Hash/Array the same way" do
    Crinja::Finalizer.stringify({"a" => [1, 2], "b" => {"c" => 3}}).should eq(%({'a': [1, 2], 'b': {'c': 3}}))
  end
end
