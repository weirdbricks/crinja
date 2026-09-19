require "../spec_helper"

# All expected outputs verified live against real Python Jinja2 3.1.6 -
# these numeric literal forms are real Jinja2's own lexer grammar
# (`integer_re`/`float_re` in jinja2/lexer.py) that this fork's numeric
# scanner used to reject outright (`Invalid number. Found char: ...`),
# found via a differential harness running real Jinja2's own upstream
# test suite against this fork.
describe "numeric literals" do
  it "accepts underscore digit-group separators, like real Jinja2" do
    # `{{ 12_34_56 }}` -> 123456 etc.; real Jinja2 renders `{{ 0_00 }}`
    # as 0 (its `0(_?0)*` decimal-zero alternative, NOT an error)
    render(%({{ 12_34_56 }})).should eq "123456"
    render(%({{ 3_4.5_6 }})).should eq "34.56"
    render(%({{ 1_2.3_4e5_6 }})).should eq "1.234e+57"
    render(%({{ 0_00 }})).should eq "0"
  end

  it "accepts scientific notation, like real Jinja2's float_re" do
    # `e`/`E` with an optional `+`/`-` sign - an exponent alone (no
    # fractional part) already makes the literal a float in real
    # Jinja2, so `{{ 1e0 }}` renders 1.0, not 1
    render(%({{ 1e0 }})).should eq "1.0"
    render(%({{ 10e1 }})).should eq "100.0"
    render(%({{ 2.5e100 }})).should eq "2.5e+100"
    render(%({{ 2.5e+100 }})).should eq "2.5e+100"
    render(%({{ 25.6e-10 }})).should eq "2.56e-09"
    render(%({{ 1E2 }})).should eq "100.0"
    render(%({{ 1e-2 }})).should eq "0.01"
  end

  it "accepts hex literals, like real Jinja2" do
    # real Jinja2 converts via Python's own int(text, 0)-style parsing,
    # so `{{ 0x123abc }}` is the decimal 1194684; case-insensitive
    render(%({{ 0x123abc }})).should eq "1194684"
    render(%({{ 0x12_3abc }})).should eq "1194684"
    render(%({{ 0X1F }})).should eq "31"
  end

  it "accepts octal literals, like real Jinja2" do
    render(%({{ 0o123 }})).should eq "83"
    render(%({{ 0o1_23 }})).should eq "83"
    render(%({{ 0O17 }})).should eq "15"
  end

  it "accepts binary literals, like real Jinja2" do
    render(%({{ 0b1001_1111 }})).should eq "159"
    render(%({{ 0B101 }})).should eq "5"
    # Jinja2's own regex (`0b(_?[0-1])+`) allows ONE underscore between
    # the prefix and the first digit, unlike Python's own literals
    render(%({{ 0b_1 }})).should eq "1"
  end

  it "still rejects genuinely invalid numeric input" do
    # real Jinja2 fails all of these with TemplateSyntaxError
    # (verified: `expected token 'end of print statement'`) - the
    # scanner must not become overly permissive: an underscore is only
    # a separator BETWEEN digits (never trailing/doubled), and only
    # 0x/0o/0b are supported prefixes
    expect_raises(Crinja::TemplateSyntaxError) do
      render(%({{ 1_ }}))
    end
    expect_raises(Crinja::TemplateSyntaxError) do
      render(%({{ 1__2 }}))
    end
    expect_raises(Crinja::TemplateSyntaxError) do
      render(%({{ 0z123 }}))
    end
    expect_raises(Crinja::TemplateSyntaxError) do
      render(%({{ 0x }}))
    end
    expect_raises(Crinja::TemplateSyntaxError) do
      render(%({{ 0o8 }}))
    end
    expect_raises(Crinja::TemplateSyntaxError) do
      render(%({{ 0b2 }}))
    end
    expect_raises(Crinja::TemplateSyntaxError) do
      render(%({{ 1e }}))
    end
    expect_raises(Crinja::TemplateSyntaxError) do
      render(%({{ 1e+ }}))
    end
  end
end
