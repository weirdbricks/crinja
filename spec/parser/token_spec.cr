require "../spec_helper"

describe Crinja::Parser::Token do
  describe "#reset" do
    # Real bug found round170 (2026-08-23) while verifying the explicit-
    # dash whitespace-control fix: `#reset` reset `value`/`location`/
    # `whitespace_before`/`whitespace_after` but never `trim_left`/
    # `trim_right`. The parser/lexer reuse a single mutable `Token`
    # instance across many lexemes (`@token.reset(pos)` at the top of
    # every `TemplateLexer#next_token` call) rather than allocating a
    # fresh one each time - so a token that once had `trim_right = true`
    # (an explicit `-%}` closing SOME earlier tag) stayed `true` on every
    # SUBSEQUENT token built from that same instance, even a plain `%}`
    # with no dash at all, since `check_for_end` only ever sets
    # `trim_right = true` conditionally and never explicitly clears it.
    # This silently gave the text immediately after certain nested
    # blocks (any block whose OWN opening tag had an explicit trailing
    # `-`, regardless of whether the closing/end tag had a dash at all)
    # a spurious `trim_left = true` it never earned - eating a real
    # newline real Jinja2 keeps. Minimal repro at the Template level
    # below; this is the underlying Token-level cause.
    it "clears trim_left and trim_right, not just value/location" do
      token = Crinja::Parser::Token.new(Crinja::Parser::Token::Kind::TAG_END, "-%}")
      token.trim_left = true
      token.trim_right = true

      token.reset(Crinja::Parser::StreamPosition.new)

      token.trim_left.should be_false
      token.trim_right.should be_false
    end
  end
end

describe "nested block trim-state leak (round170 gap, Token#reset)" do
  # `endif` here is a completely PLAIN `{% endif %}` - no dash anywhere
  # near it - so the text after it ("\n</div>") must render exactly as
  # written, matching real Jinja2. Before the Token#reset fix, this lost
  # its leading newline because a token reused from the IF tag's own
  # `-%}` (three tags earlier) leaked a stale trim_right=true into the
  # ENDIF tag's own trim computation.
  it "does not leak a stale dash from an earlier tag onto a later plain one" do
    string = "<div>\n    {% if true -%}\n\n\n        yay\n    {% endif %}\n</div>"
    template = Crinja::Template.new(string)
    template.render.should eq "<div>\n    yay\n    \n</div>"
  end

  it "does not leak across a doubly-nested block boundary either" do
    string = "{% if true -%}\n{% for x in [1, 2] -%}\n{{ x }}\n{% endfor %}\n{% endif %}\nEND"
    template = Crinja::Template.new(string)
    # Real Jinja2 (verified directly): the outer if's own plain `{%
    # endif %}` keeps the newline before "END" - no stale dash state
    # from the if's/for's own `-%}` (earlier tags, one nesting level
    # apart) should reach it.
    template.render.should eq "1\n2\n\n\nEND"
  end
end
