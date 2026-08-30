require "../spec_helper"

# P3.1 (FINDINGS_CHECKLIST.md): whitespace conformance matrix spec.
#
# Table-driven over:
#   * tag delimiters:        {% / {%- / {%+  x closing %} / -%} / +%}
#   * expression delimiters: {{ / {{- x closing }} / -}}
#     (real Jinja2 has NO {{+ / +}} form - not part of the matrix)
#   * block-vs-inline shape
#   * trim_blocks on/off x lstrip_blocks on/off
#   * NBSP (U+00A0) handling
#
# EVERY expected value below is the output of a real jinja2 3.1.6 render
# (jinja2.Environment(trim_blocks=..., lstrip_blocks=...)) for the identical
# template and configuration, generated mechanically (not hand-written) and
# verified byte-for-byte against Crinja's output by a differential harness.
#
# This file was REGENERATED after FINDINGS_CHECKLIST P3.2-P3.4 landed:
#   P3.2 right-side `-}}` on expressions now trims (was ignored).
#   P3.3 `{%+` / `+%}` forms now parse and implement Jinja2's force-off
#       overrides of lstrip_blocks / trim_blocks.
#   P3.4 lstrip_blocks no longer overreaches (no newline-eating, no inline
#       stripping) - it strips only the block tag's OWN line, keeping the
#       newline, matching Jinja2's exact algorithm.
#   P3.5 was a MISCLASSIFICATION: real Jinja2 DOES strip NBSP-led whitespace
#       before a block tag (its \s includes U+00A0), and Crinja now matches.
# There are therefore NO remaining recorded divergences: every row belongs in
# the conformance matrix.

private TEMPLATES = {
  "expr_ldash_block"        => "A\n    {{- v -}}\nB",
  "expr_ldash_inline"       => "A {{- v -}} B",
  "expr_ldash_only_block"   => "A\n    {{- v }}\nB",
  "expr_ldash_only_inline"  => "A {{- v }} B",
  "expr_plain_block"        => "A\n    {{ v }}\nB",
  "expr_plain_inline"       => "A {{ v }} B",
  "expr_rdash_only_block"   => "A\n    {{ v -}}\nB",
  "expr_rdash_only_inline"  => "A {{ v -}} B",
  "nbsp_around_dash_block"  => "A\n\u{00A0}   {%- if true -%}\n\u{00A0}   V\n\u{00A0}   {%- endif -%}\nB",
  "nbsp_before_expr_inline" => "A\n\u{00A0}   {{ v }}\nB",
  "nbsp_before_tag_block"   => "A\n\u{00A0}   {% if true %}\n\u{00A0}   V\n\u{00A0}   {% endif %}\nB",
  "nbsp_inside_expr"        => "A {{ \u{00A0} v \u{00A0} }} B",
  "tag_ldash_block"         => "A\n    {%- if true -%}\n    V\n    {%- endif -%}\nB",
  "tag_ldash_inline"        => "A {%- if true -%}V{%- endif -%} B",
  "tag_ldash_only_block"    => "A\n    {%- if true %}\n    V\n    {%- endif %}\nB",
  "tag_ldash_only_inline"   => "A {%- if true %}V{%- endif %} B",
  "tag_lplus_block"         => "A\n    {%+ if true %}\n    V\n    {%+ endif %}\nB",
  "tag_lplus_inline"        => "A {%+ if true %}V{%+ endif %} B",
  "tag_plain_block"         => "A\n    {% if true %}\n    V\n    {% endif %}\nB",
  "tag_plain_inline"        => "A {% if true %}V{% endif %} B",
  "tag_plus_block"          => "A\n    {%+ if true +%}\n    V\n    {%+ endif +%}\nB",
  "tag_plus_inline"         => "A {%+ if true +%}V{%+ endif +%} B",
  "tag_rdash_only_block"    => "A\n    {% if true -%}\n    V\n    {% endif -%}\nB",
  "tag_rdash_only_inline"   => "A {% if true -%}V{% endif -%} B",
  "tag_rplus_block"         => "A\n    {% if true +%}\n    V\n    {% endif +%}\nB",
  "tag_rplus_inline"        => "A {% if true +%}V{% endif +%} B",
}

private MATRIX = {

  {trim_blocks: false, lstrip_blocks: false} => {
    "expr_ldash_block"        => "AVB",
    "expr_ldash_inline"       => "AVB",
    "expr_ldash_only_block"   => "AV\nB",
    "expr_ldash_only_inline"  => "AV B",
    "expr_plain_block"        => "A\n    V\nB",
    "expr_plain_inline"       => "A V B",
    "expr_rdash_only_block"   => "A\n    VB",
    "expr_rdash_only_inline"  => "A VB",
    "nbsp_around_dash_block"  => "AVB",
    "nbsp_before_expr_inline" => "A\n\u{00A0}   V\nB",
    "nbsp_before_tag_block"   => "A\n\u{00A0}   \n\u{00A0}   V\n\u{00A0}   \nB",
    "nbsp_inside_expr"        => "A V B",
    "tag_ldash_block"         => "AVB",
    "tag_ldash_inline"        => "AVB",
    "tag_ldash_only_block"    => "A\n    V\nB",
    "tag_ldash_only_inline"   => "AV B",
    "tag_lplus_block"         => "A\n    \n    V\n    \nB",
    "tag_lplus_inline"        => "A V B",
    "tag_plain_block"         => "A\n    \n    V\n    \nB",
    "tag_plain_inline"        => "A V B",
    "tag_plus_block"          => "A\n    \n    V\n    \nB",
    "tag_plus_inline"         => "A V B",
    "tag_rdash_only_block"    => "A\n    V\n    B",
    "tag_rdash_only_inline"   => "A VB",
    "tag_rplus_block"         => "A\n    \n    V\n    \nB",
    "tag_rplus_inline"        => "A V B",
  },
  {trim_blocks: false, lstrip_blocks: true} => {
    "expr_ldash_block"        => "AVB",
    "expr_ldash_inline"       => "AVB",
    "expr_ldash_only_block"   => "AV\nB",
    "expr_ldash_only_inline"  => "AV B",
    "expr_plain_block"        => "A\n    V\nB",
    "expr_plain_inline"       => "A V B",
    "expr_rdash_only_block"   => "A\n    VB",
    "expr_rdash_only_inline"  => "A VB",
    "nbsp_around_dash_block"  => "AVB",
    "nbsp_before_expr_inline" => "A\n\u{00A0}   V\nB",
    "nbsp_before_tag_block"   => "A\n\n\u{00A0}   V\n\nB",
    "nbsp_inside_expr"        => "A V B",
    "tag_ldash_block"         => "AVB",
    "tag_ldash_inline"        => "AVB",
    "tag_ldash_only_block"    => "A\n    V\nB",
    "tag_ldash_only_inline"   => "AV B",
    "tag_lplus_block"         => "A\n    \n    V\n    \nB",
    "tag_lplus_inline"        => "A V B",
    "tag_plain_block"         => "A\n\n    V\n\nB",
    "tag_plain_inline"        => "A V B",
    "tag_plus_block"          => "A\n    \n    V\n    \nB",
    "tag_plus_inline"         => "A V B",
    "tag_rdash_only_block"    => "A\nV\nB",
    "tag_rdash_only_inline"   => "A VB",
    "tag_rplus_block"         => "A\n\n    V\n\nB",
    "tag_rplus_inline"        => "A V B",
  },
  {trim_blocks: true, lstrip_blocks: false} => {
    "expr_ldash_block"        => "AVB",
    "expr_ldash_inline"       => "AVB",
    "expr_ldash_only_block"   => "AV\nB",
    "expr_ldash_only_inline"  => "AV B",
    "expr_plain_block"        => "A\n    V\nB",
    "expr_plain_inline"       => "A V B",
    "expr_rdash_only_block"   => "A\n    VB",
    "expr_rdash_only_inline"  => "A VB",
    "nbsp_around_dash_block"  => "AVB",
    "nbsp_before_expr_inline" => "A\n\u{00A0}   V\nB",
    "nbsp_before_tag_block"   => "A\n\u{00A0}   \u{00A0}   V\n\u{00A0}   B",
    "nbsp_inside_expr"        => "A V B",
    "tag_ldash_block"         => "AVB",
    "tag_ldash_inline"        => "AVB",
    "tag_ldash_only_block"    => "A    VB",
    "tag_ldash_only_inline"   => "AV B",
    "tag_lplus_block"         => "A\n        V\n    B",
    "tag_lplus_inline"        => "A V B",
    "tag_plain_block"         => "A\n        V\n    B",
    "tag_plain_inline"        => "A V B",
    "tag_plus_block"          => "A\n    \n    V\n    \nB",
    "tag_plus_inline"         => "A V B",
    "tag_rdash_only_block"    => "A\n    V\n    B",
    "tag_rdash_only_inline"   => "A VB",
    "tag_rplus_block"         => "A\n    \n    V\n    \nB",
    "tag_rplus_inline"        => "A V B",
  },
  {trim_blocks: true, lstrip_blocks: true} => {
    "expr_ldash_block"        => "AVB",
    "expr_ldash_inline"       => "AVB",
    "expr_ldash_only_block"   => "AV\nB",
    "expr_ldash_only_inline"  => "AV B",
    "expr_plain_block"        => "A\n    V\nB",
    "expr_plain_inline"       => "A V B",
    "expr_rdash_only_block"   => "A\n    VB",
    "expr_rdash_only_inline"  => "A VB",
    "nbsp_around_dash_block"  => "AVB",
    "nbsp_before_expr_inline" => "A\n\u{00A0}   V\nB",
    "nbsp_before_tag_block"   => "A\n\u{00A0}   V\nB",
    "nbsp_inside_expr"        => "A V B",
    "tag_ldash_block"         => "AVB",
    "tag_ldash_inline"        => "AVB",
    "tag_ldash_only_block"    => "A    VB",
    "tag_ldash_only_inline"   => "AV B",
    "tag_lplus_block"         => "A\n        V\n    B",
    "tag_lplus_inline"        => "A V B",
    "tag_plain_block"         => "A\n    V\nB",
    "tag_plain_inline"        => "A V B",
    "tag_plus_block"          => "A\n    \n    V\n    \nB",
    "tag_plus_inline"         => "A V B",
    "tag_rdash_only_block"    => "A\nV\nB",
    "tag_rdash_only_inline"   => "A VB",
    "tag_rplus_block"         => "A\n\n    V\n\nB",
    "tag_rplus_inline"        => "A V B",
  },
}

private def matrix_render(key, trim_blocks, lstrip_blocks)
  render(TEMPLATES[key], {"v" => "V"}, trim_blocks: trim_blocks, lstrip_blocks: lstrip_blocks)
end

describe "whitespace conformance matrix (P3.1)" do
  MATRIX.each do |conf, cases|
    trim_blocks = conf[:trim_blocks]
    lstrip_blocks = conf[:lstrip_blocks]
    context "trim_blocks: #{trim_blocks}, lstrip_blocks: #{lstrip_blocks}" do
      cases.each do |name, expected|
        it name do
          matrix_render(name, trim_blocks, lstrip_blocks).should eq expected
        end
      end
    end
  end
end
