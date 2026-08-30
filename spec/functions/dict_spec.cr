require "../spec_helper.cr"

describe "function dict" do
  it "creates a dict from kwargs" do
    evaluate_expression(%(dict(foo="bar"))).should eq(%({'foo': 'bar'}))
  end

  it "creates an empty dict with no arguments" do
    evaluate_expression(%(dict())).should eq(%({}))
  end

  it "creates a dict from an iterable of [key, value] pairs" do
    evaluate_expression(%(dict([['a', 1], ['b', 2]]))).should eq(%({'a': 1, 'b': 2}))
  end

  it "creates a dict from a list of 2-tuples" do
    evaluate_expression(%(dict([('a', 1), ('b', 2)]))).should eq(%({'a': 1, 'b': 2}))
  end

  it "merges kwargs on top of a positional iterable" do
    evaluate_expression(%(dict([['a', 1]], b=2))).should eq(%({'a': 1, 'b': 2}))
  end

  it "copies a mapping argument" do
    evaluate_expression(%(dict({'a': 1, 'b': 2}))).should eq(%({'a': 1, 'b': 2}))
  end

  it "raises for a positional arg that is neither a mapping nor an iterable of pairs" do
    expect_raises(Crinja::Arguments::Error) do
      evaluate_expression(%(dict('not a mapping')))
    end
  end

  it "raises for more than one positional argument" do
    expect_raises(Crinja::Arguments::Error) do
      evaluate_expression(%(dict([['a', 1]], [['b', 2]])))
    end
  end
end
