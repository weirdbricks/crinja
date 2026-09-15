require "../spec_helper.cr"
# tests based on https://github.com/pallets/jinja/blob/master/tests/test_core_tags.py

describe Crinja::Tag::If do
  it "simple" do
    render(%({% if true %}...{% endif %})).should eq "..."
  end

  it "elif" do
    render(%({% if false %}FFF{% elif true
            %}...{% else %}XXX{% endif %})).should eq "..."
  end

  it "else" do
    render(%({% if false %}XXX{% else %}...{% endif %})).should eq "..."
  end

  it "empty" do
    render(%([{% if true %}{% else %}{% endif %}])).should eq "[]"
  end

  it "complete" do
    render(%({% if a %}A{% elif b %}B{% elif c == d %}C{% else %}D{% endif %}), {"a" => 0, "b" => false, "c" => 42, "d" => 42.0}).should eq "C"
  end

  it "no_scope" do
    render(%({% if a %}{% set foo = 1 %}{% endif %}{{ foo }}), {"a" => true}).should eq "1"
    render(%({% if true %}{% set foo = 1 %}{% endif %}{{ foo }})).should eq "1"
  end

  it "fails additional args" do
    expect_raises(Crinja::TemplateSyntaxError, "Did not expect any more tokens") do
      render(%({% if 'Templates' ends with 's' %}"Templates" ends with "s"{% endif %}))
    end
  end

  it "raises for a bare StrictUndefined variable" do
    # Real Jinja2/Ansible: bool() on a StrictUndefined raises - real
    # ansible-playbook fails `{% if some_undefined_var %}` with
    # "'some_undefined_var' is undefined" (found via
    # vcc_caeit.ntp's templates/ntp.conf.j2 `{% if ntp_use_external %}`).
    expect_raises(Crinja::UndefinedError, "some_undefined_var is undefined") do
      render(%({% if some_undefined_var %}yes{% else %}no{% endif %}),
        {"some_undefined_var" => Crinja::Value.new(Crinja::StrictUndefined.new("some_undefined_var"))})
    end
  end

  it "renders false-branch for a bare lenient Undefined variable" do
    # The plain Undefined stays falsy, as always - only StrictUndefined
    # got strict.
    render(%({% if some_undefined_var %}yes{% else %}no{% endif %}),
      {"some_undefined_var" => Crinja::Value.new(Crinja::Undefined.new("some_undefined_var"))}).should eq "no"
  end
end
