require "../spec_helper.cr"

private def test_loader_import
  Crinja::Loader::HashLoader.new({
    "macros.html" => <<-'TPL',
      {% macro testmacro() %}foo{%endmacro%}
      TPL
  })
end

describe Crinja::Tag::Import do
  it "imports macro" do
    render("{% import 'macros.html' %}{{ testmacro() }}", loader: test_loader_import).should eq "foo"
  end
  it "fails for unknown macro" do
    expect_raises(Crinja::TemplateNotFoundError) do
      render("{% import 'invalid.html' %}{{ testmacro() }}", loader: test_loader_import)
    end
  end
  it "imports aliased macro" do
    render("{% import 'macros.html' as macros %}{{ macros.testmacro() }}", loader: test_loader_import).should eq "foo"
  end
  it "imports aliased macro only in namespace" do
    render("{% import 'macros.html' as macros %}{{ testmacro is not callable }}", loader: test_loader_import).should eq "True"
  end

  # Real bug found via krikri's own manala.influxdb round: `{%- import
  # '_macros.j2' as macros with context -%}` raised "Did not expect any
  # more tokens, found: IDENTIFIER:with" - the `with context`/`without
  # context` modifier (crystal-play-0.9.29) was never parsed at all.
  it "accepts (and ignores) a trailing with/without context modifier" do
    render("{% import 'macros.html' as macros with context %}{{ macros.testmacro() }}", loader: test_loader_import).should eq "foo"
    render("{% import 'macros.html' as macros without context %}{{ macros.testmacro() }}", loader: test_loader_import).should eq "foo"
    render("{% import 'macros.html' with context %}{{ testmacro() }}", loader: test_loader_import).should eq "foo"
  end
end
