# PATCHES.md

This is a fork of [straight-shoota/crinja](https://github.com/straight-shoota/crinja),
maintained for [krikri](https://github.com/weirdbricks/krikri)
(a from-scratch `ansible-playbook` reimplementation in Crystal, which vendors
Crinja as its Jinja2 template engine for real `.j2` template rendering).

## Why this fork exists

See `krikri`'s own `CRINJA.md` (repo root) for the full reasoning.
Short version: krikri originally patched Crinja behavior by
reopening its Crystal classes from small `crinja_*_ext.cr` files rather
than editing `lib/crinja` directly (which is `.gitignore`d and refetched
by every `shards install`). That worked, but `shard.yml` pointed at
upstream `branch: master`, which means any `shards update` could
silently pull a refactor that breaks one of those class-reopening
patches without warning. This fork exists so krikri can pin to
a **tag it controls**, and so real source-level fixes (not monkey-patches)
have somewhere to live.

## crystal-play-0.9.46 (2026-09-19): Django-style numeric attribute access (`[1, 2, 3].0`, chained `[[1]].0.0`)

Real Jinja2 supports "Django-style" dot-index syntax - `.0` on a list
means index 0, the same item lookup `[0]` compiles to - in two places.
`parse_subscript` (jinja2/parser.py 3.1.6, verified against the installed
source) accepts an INTEGER token directly after a member-access dot and
builds a `nodes.Getitem` with it (`if attr_token.type != "integer": fail`
- floats are explicitly rejected there), and the lexer's `float_re`
(jinja2/lexer.py) carries a `(?<!\.)` lookbehind so a number whose raw
text starts right after a `.` can NEVER lex as a float: `Environment.lex`
on `{{ [[1]].0.0 }}` yields `.` `0` `.` `0` (operator/integer/operator/
integer, confirmed live), which is the only way a chained `.0.0` can be
two separate index accesses at all. Both real Jinja2 3.1.6 and a real
`ansible-playbook` 2.19 run (`debug: msg:` tasks, outputs identical in
both) render `{{ [1, 2, 3].0 }}|{{ [[1]].0.0 }}` as `1|1`.

This fork's parser already accepted INTEGER after the POINT token, and
the single-dot case (`[1, 2, 3].0`) already worked - but the lexer's
number scan, once started on the digit after a member dot, happily
consumed a following `.digit` as the fractional part, so `].0.0` lexed
as `.` + one FLOAT "0.0" and the parser failed with `Expected
IDENTIFIER, got FLOAT` (found via the differential harness running real
Jinja2 3.1.6's own upstream test suite against this fork). The fix
mirrors real Jinja2's exact mechanism at the same layer: the expression
lexer now checks the raw character immediately before the number token
start (a `prev_char` back-peek on the shared character stream, the
equivalent of the regex lookbehind) and, when it is a `.` - i.e. the
number starts right after a member-access dot - scans the token with the
fractional and exponent parts disabled, exactly the integer_re-only
match real Jinja2 falls back to; the token then ends at the next `.`,
which the parser reads as another member access. Ordinary float literals
(`{{ 1.5 }}`) and ordinary attribute access (`foo.bar`) are untouched:
their number tokens never start right after a dot.

All expected outputs in the new regression specs (token-level in
`spec/parser/lexer_spec.cr`, AST-level in
`spec/parser/expression_parser_spec.cr`, render-level in
`spec/crinja_spec.cr`: the two confirmed cases plus the float-literal
and `foo.bar` non-regression checks) were verified live against real
Jinja2 3.1.6 AND a real `ansible-playbook` 2.19 run. Full fork spec
suite: 783 examples, 0 failures, 0 errors, 11 pending.

## crystal-play-0.9.45 (2026-09-19): `{%- raw -%}`/`{% endraw -%}` whitespace-control modifiers on raw blocks

Real Jinja2 never tokenizes raw content as template syntax: its raw block
is a special lexer state (jinja2/lexer.py 3.1.6) reached from a
`raw_begin` alternative in the root regex, `{%(\-|\+|)\s*raw\s*(?:-%}\s*|%})`,
and exited only at the raw state's own rule,
`(?:{%)(\-|\+|)\s*endraw\s*(?:\+%}|-%}\s*|%}\n?)` - so the whitespace-control
dashes are baked into those raw-scanning regexes themselves, not applied by
the generic tag mechanism afterwards. Two consequences verified directly
against a real `jinja2.Environment` (3.1.6) AND a real `ansible-playbook`
2.19 run (`debug: msg:` tasks, outputs identical in both): `raw -%}` swallows
the whitespace right after the opening tag and `{%- endraw` rstrips the raw
data (`OptionalLStrip`), so `1  {%- raw -%}   2   {%- endraw -%}   3` renders
`123` with both content EDGES trimmed, while trim_blocks/lstrip_blocks
config NEVER touches raw content (`{% raw %}\n  2\n  {% endraw %}` keeps both
edges under either setting, where the same `{% if %}` block loses them).
One regex quirk: raw_begin's closing side accepts only `-%}` or `%}`, so
real Jinja2 rejects `raw +%}` ("unknown tag 'raw'") even though it accepts
`+%}` on every other tag's `%}`; this fork's generic tag-end machinery
already accepts `+%}` everywhere, and that (benign-superset) behavior was
kept rather than special-cased away.

This fork's raw-end scan (`consume_raw`) only accepted a bare
`{% endraw` opener - it whitespace-skipped after `{%` but never allowed the
`-`/`+` marker - so `{%- endraw` was never found, the raw block consumed the
rest of the template, and `1  {%- raw -%}   2   {%- endraw -%}   3` raised
`Unclosed tag, missing: endraw` (also `{%+ endraw`, also found via the
differential harness running real Jinja2 3.1.6's own upstream test suite;
`{%- if true -%}...{%- endif -%}` parsed fine throughout, isolating the bug
to raw-end detection, not a general whitespace-control regression). And
`Tag::Raw#interpret` printed the content node verbatim, so even where the
lexer/parser DID record the dash flags on the raw content's FixedString
node (from the opening tag's `-%}` and the endraw tag's `{%-`), they were
silently dropped - the reason `raw -%}`/`{%- endraw` never trimmed the
content edges. The raw-end scan now accepts an optional `-`/`+` after `{%`
before `endraw` (same shapes as real Jinja2's raw-state regex), and the raw
tag's interpreter applies ONLY the explicit `trim_left`/`trim_right` flags
(full lstrip/rstrip, same strong semantics as every other tag's `-` side)
while continuing to bypass the implicit trim_blocks/lstrip_blocks config,
matching real Jinja2 exactly.

All expected outputs in the new regression specs
(`spec/tags/raw_spec.cr`: the confirmed 3-part `123` case, the plain
sanity case, one-sided `{%- raw %}...{% endraw -%}`, `{%- endraw` rstrip,
config-immunity under trim_blocks/lstrip_blocks, and `+` variants) were
verified live against real Jinja2 3.1.6 AND a real `ansible-playbook` run.
Full fork spec suite: 770 examples, 0 failures, 0 errors, 11 pending.

## crystal-play-0.9.44 (2026-09-19): adjacent string literals concatenate (`{{ "foo" "bar" }}` -> `foobar`)

Real Jinja2 merges adjacent string literals into one string, exactly
like Python's own adjacent-string-literal syntax (`"foo" "bar"` is
`"foobar"`): `parse_primary` (jinja2/parser.py, verified against the
installed 3.1.6 source) loops on `self.stream.current.type == "string"`
collecting consecutive STRING tokens from the token stream into a
single `nodes.Const("".join(buf))` before any AST node is built - so
the merge is grammar-level, happens inside any expression context
(inside parens and list literals too), and only fires on BARE
adjacency: any non-string token (an operator, comma, expression end)
breaks the loop, so `{{ "foo" ~ "bar" }}` stays an operator concat and
`{{ "foo" }} {{ "bar" }}` stays two separate print statements.

This fork had no such merge - its string-literal case consumed exactly
one STRING token and returned, so the second literal was left over and
the expression parser raised `expression was not fully parsed:
STRING:"bar"[1:10]` on `{{ "foo" "bar" "baz" }}` (found via the
differential harness running real Jinja2 3.1.6's own upstream test
suite against this fork). The fix mirrors real Jinja2's exact scope:
while parsing a string literal, keep consuming STRING tokens and join
their values into one `StringLiteral` (spanning all merged tokens for
location purposes); everything else is untouched, so operator
concatenation and per-`{{ }}` isolation behave as before. All expected
outputs in the new regression specs (`spec/parser/
expression_parser_spec.cr` and `spec/crinja_spec.cr` "adjacent string
literal concatenation") were verified live against real Jinja2 3.1.6
AND a real `ansible-playbook` 2.19 run with `debug: msg:` tasks
reproducing each case (`{{ 'foo' 'bar' 'baz' }}` -> `foobarbaz`,
`{{ 'foo' }} {{ 'bar' }}` -> `foo bar`, `{{ 'foo' ~ 'bar' }}` ->
`foobar`, `{{ ['foo' 'bar'] }}` -> `['foobar']` - identical in both
engines, confirming string-literal adjacency is pure parser grammar
untouched by Ansible's `finalize`/native-types customizations). Full
fork spec suite: 769 examples, 0 failures, 0 errors, 11 pending.

## crystal-play-0.9.43 (2026-09-19): tuple literal grammar (`()`, `(x,)`) and trailing-comma tolerance in all collection literals

Real Jinja2's parenthesized-expression grammar (jinja2/parser.py,
verified against the installed 3.1.6 source) is built on
`parse_tuple(explicit_parentheses=True)`: a lone `LEFT_PAREN` primary is
parsed by the same comma-loop `parse_tuple` that handles bare
`a, b` tuples, whose `is_tuple_end` check breaks the element loop on
`rparen` even with zero elements, and `explicit_parentheses` turns that
empty result into a `nodes.Tuple` instead of the "Expected an
expression" failure bare emptiness gets elsewhere. So `()` is a valid
EMPTY-TUPLE literal, a single element followed by a MANDATORY trailing
comma `(x,)` is the one-element tuple (without the comma, `(x)` is just
a parenthesized expression - `parse_tuple` only sets `is_tuple` when it
sees a comma, so `{{ (1) }}` renders the integer `1`, `{{ (1,) }}` the
1-tuple), and `(x, y[, ...])` is the multi-element tuple. Real
Jinja2's other bracketed collection literals tolerate a trailing comma
by construction: `parse_list` and `parse_dict` re-test `rbracket`/
`rbrace` immediately after `expect("comma")`, and `parse_call_args`
even carries an explicit "support for trailing comma" comment.

This fork had no empty-tuple path at all - its paren handling fed the
bare `RIGHT_PAREN` straight into `parse_expression` and raised
`Unexpected RIGHT_PAREN` on `{{ () }}`, `{{ (1,) }}` - and its shared
`parse_expression_list` / dict-literal loops unconditionally tried to
parse another expression after every comma, so the same error hit
`{{ (1, 2,) }}`, `{{ [1, 2,] }}` and `{{ {1: 2,} }}` (all found via the
differential harness running real Jinja2 3.1.6's own upstream test
suite against this fork). The fix keeps the existing single
expression-then-comma-loop shape and mirrors real Jinja2's
comma-then-end-check ordering in all three places: the paren handler
recognizes `()` before parsing an expression and yields an empty
`TupleLiteral`, and the expression-list and dict loops stop when the
end token follows the comma instead of demanding another element. The
existing `(x)`-is-not-a-tuple distinction was already correct (no
comma, no `TupleLiteral`) and is preserved; the `()` case is legal only
inside parens, matching `explicit_parentheses=False` elsewhere.

All expected outputs in the new regression specs
(`spec/parser/expression_parser_spec.cr`, `spec/crinja_spec.cr`
"tuple and trailing-comma collection literals") were verified live
against real Jinja2 3.1.6 AND a real `ansible-playbook` 2.19 run with
`debug: msg:` tasks reproducing each case: Python tuples are lists to
Ansible's native-types finalization at rendered-output positions, so
every tuple renders bracketed (`{{ () }}` -> `[]`, not vanilla Jinja2's
`()` repr, and `{{ (1,) }}` -> `[1]`), while `{{ (1) }}` renders `1`,
`{{ (1, 2) == (1, 2) }}` and `{{ (1) == 1 }}` render `True`, and
`{{ (1,)|length }}` renders `1` - all identical in both engines
(parsing is pre-finalization, so Ansible's customizations only affect
the tuple-to-list print form already handled by this fork's
`Crinja::Tuple` finalizer). Full fork spec suite: 753 examples,
0 failures, 0 errors, 11 pending.

## crystal-play-0.9.42 (2026-09-19): `indent` ported to real Jinja2's `do_indent` (no trailing indent, `first`/`blank` kwargs), `trim` honors `chars=`

Real Jinja2's `do_indent(s, width=4, first=False, blank=False)`
(jinja2/filters.py, verified against the installed 3.1.6 source)
appends a newline to the input ("this quirk is necessary for
splitlines method"), splits with Python's `str.splitlines()`, and in
the default `blank=false` path keeps the first line bare and prepends
the indent ONLY to non-empty following lines - so the trailing empty
line that the newline quirk creates for input ending in `\n` stays
empty, which is why real Jinja2 does NOT tack an indent after the
final newline (`"\nfoo bar\n\"baz\"\n"|indent(2, false, false)` ->
`"\n  foo bar\n  \"baz\"\n"`, no trailing `  `). `blank=true` instead
joins ALL lines with `newline + indention`, so there a trailing
indent IS expected (`indent(2, false, true)` -> `"\n  foo bar\n
\"baz\"\n  "`). `first` then unconditionally prefixes the indent -
including for a single-line input with no newline at all
(`"jinja"|indent(first=true)` -> `"    jinja"`), because splitlines
still yields that one line. Found via a differential harness running
real Jinja2 3.1.6's own upstream test suite against this fork.

This fork's filter instead regex-gsubbed every `\n` with
`newline + indent` (adding a phantom trailing indent after the last
real newline) and named the second positional/kwarg `indentfirst` -
the pre-2.10 Jinja2 argument name that Jinja2 3.x removed in favor of
`first` - so `first=true` (positional or keyword) was never read and
a newline-less single line was never indented. The filter is now a
direct port of `do_indent`: same newline quirk, same splitlines
semantics (added `Crinja::Util.python_splitlines`, handling every
Python line boundary incl. `\r\n`, `\r`, `\v`/`\f`/`\x1c`-`\x1e`,
`\x85`, `\u2028`/`\u2029`, with splitlines' own rule that a single
trailing boundary yields no empty line), same blank/first branch
order, and the kwargs are now `width`/`first`/`blank` exactly like
real Jinja2 (width may also be a string, per the same source).

Real Jinja2's `do_trim(value, chars=None)` is just
`soft_str(value).strip(chars)`: with no `chars=` argument it strips
default whitespace, but an explicit `chars=` string switches to
Python's own `str.strip(chars)` set-of-characters semantics, stripping
ONLY the given characters from both ends and leaving any other
leading/trailing characters untouched (`" ..stays.."|trim(chars)` with
`chars = "."` -> `" ..stays"` - the leading space survives). This fork
ignored `chars=` entirely and always whitespace-stripped, returning
`..stays..` unchanged except for whitespace loss - also found via the
differential harness. The filter now accepts `chars=` (positionally or
by keyword), passing it through to Crystal's own `String#strip(chars)`,
which has the same set-of-characters semantics.

Cross-checked BEFORE fixing because a differential finding earlier in
the session (top-level `None` stringification) turned out to be a
real-Ansible-vs-vanilla-Jinja2 deliberate difference: a real local
`ansible-playbook` 2.19 run with `debug: msg:` tasks reproducing every
case above gives identical output to vanilla Jinja2 3.1.6 (including
`blank=true`'s trailing indent) - `indent`/`trim` are pure string
transformations, untouched by Ansible's `finalize`/native-types
customizations, so the fork genuinely diverged. All expected outputs
in the new regression specs (`spec/lib/filter_spec.cr`) are from that
live verification. Full fork spec suite: 749 examples, 0 failures,
0 errors, 11 pending.

## crystal-play-0.9.41 (2026-09-19): `urlize` filter ported to real Jinja2's detection rules (bare domains, emails, `extra_schemes=`)

Real Jinja2's `urlize` (`jinja2/utils.py#urlize`, verified against the
installed 3.1.6 source) is not a generic scheme-detection regex: it
splits the HTML-escaped text on `re.split(r"(\s+)", ...)` and matches
each candidate against one anchored `_http_re` that accepts ONLY
`http(s)://` or `www.` plus a plausible domain (TLD of 2+ letters or an
`xn--` IDNA TLD), a bare domain on a fixed TLD list
(com/net/int/edu/gov/org/info/mil), or `http(s)://` followed by an IPv4
or bracketed IPv6 address - plus optional port and
path/query/fragment. Only those (and emails) get linkified, so
`{{ "foo ftp://localhost bar"|urlize }}` stays plain text without
`extra_schemes=`. Schemeless and `www.`-prefixed matches get an
`https://` href. Emails (`_email_re`) link as `mailto:` - both
`mailto:x@y.tld` and bare `x@y.tld` - and NEVER carry `rel`/`target`
attributes, unlike http(s) links. `do_urlize` (jinja2/filters.py) then
joins the `rel` parts (from the `rel` kwarg, the `nofollow` kwarg and
the `urlize.rel` policy, default `"noopener"`) into a sorted set, which
is why `urlize(nofollow=true)` renders `rel="nofollow noopener"`, and
falls back to the `urlize.extra_schemes` policy for `extra_schemes=`,
validating each entry against `_uri_scheme_re`
(`^([\w.+-]{2,}:(/){0,2})$`, raising `FilterArgumentError` otherwise).
`trim_url_limit` truncates only the DISPLAYED url, appending `...`
after the first N characters. The input text is escaped with
`markupsafe.escape` inside `urlize` itself regardless of autoescape, so
`{{ "http://x/?a=1&b=2"|urlize }}` emits `&amp;` in both href and link
text, and mailto/extra-scheme hrefs are emitted attribute-less between
`href` and the trimmed display.

This fork's filter was a port of the rails_autolink `AUTO_LINK_RE`
heuristic instead: it linked ANY `scheme://` prefix (so it wrongly
linkified `ftp://localhost` with no `extra_schemes=` - and only
matched by coincidence when the harness passed `extra_schemes=["tel:",
"ftp:"]`, while `tel:+1-514-555-1234` was left untouched because
`extra_schemes=` was never even a kwarg of the filter), missed bare
domains entirely (`{{ "foo example.org bar"|urlize }}` stayed
unchanged - found via a differential harness running real Jinja2
3.1.6's own upstream test suite against this fork), missed
`mailto:`/bare-email detection, and truncated the display to
`trim_url_limit - 3` characters instead of appending `...` after
`trim_url_limit` characters.

`Crinja::Util.urlize` is now a direct port of real Jinja2's
`urlize`: same `_http_re`/`_email_re` regexes, same
leading/trailing-punctuation head/tail splitting and parenthesis
balancing, same branch order (http/www, then `mailto:`, then bare
email, then `extra_schemes`), same markupsafe-compatible escaping and
attribute ordering (`href`, then `rel`, then `target`). The filter
gains the `extra_schemes` kwarg (with the same `_uri_scheme_re`
validation, raising `Crinja::Arguments::Error`) plus the
`urlize.extra_schemes` policy fallback, and sorts the `rel` parts like
real Jinja2. The filter's previous `trim_url_limit` cast also crashed
on template number literals (Int64), now any `Int` is accepted.

All expected outputs in the new regression specs
(`spec/lib/filter_spec.cr`, `describe "urlize"`) were verified live
against real Jinja2 3.1.6 AND a real `ansible-playbook` 2.19 run with
`debug: msg:` tasks reproducing each case - both render identically
(`urlize` is a pure string transformation, untouched by Ansible's
`finalize`/native-types customizations). Full fork spec suite: 734
examples, 0 failures, 0 errors, 11 pending.

## crystal-play-0.9.40 (2026-09-19): `min`/`max` compare strings case-insensitively by default, honoring `case_sensitive=true`

Real Jinja2's `do_min`/`do_max` (both `case_sensitive: bool = False` by
default) share `_min_or_max` (jinja2/filters.py, verified against the
installed 3.1.6 source), which ALWAYS feeds Python's `min`/`max` a key
function built by `make_attrgetter(..., postprocess=ignore_case if not
case_sensitive else None)` - and `ignore_case` lowercases string values
(`str.lower()`) while passing every other type through unchanged. So
`min`/`max` string comparison is case-INsensitive by default, raw
ASCII-ordering only with an explicit `case_sensitive=true`, and Python's
own first-item-on-ties rule applies (min and max both return the first
item encountered on equal keys). This fork passed no key function at
all, always comparing raw strings, so `{{ ["a", "B"]|min }}` returned
`B` (0x42 < 0x61) and `|max` returned `a` - found via a differential
harness running real Jinja2 3.1.6's own upstream test suite against
this fork. Cross-checked BEFORE fixing because a differential finding
on this fork earlier in the session (top-level `None` stringification)
turned out to be a real-Ansible-vs-vanilla-Jinja2 deliberate difference:
a real local `ansible-playbook` run with `debug: msg="{{ ['a', 'B']|min
}}/|max/|min(case_sensitive=true)/|max(case_sensitive=true)"` gives
`a`/`B`/`B`/`a`, identical to vanilla Jinja2 3.1.6, so this is NOT an
Ansible-environment customization and the fork genuinely diverged.

The filters now fold string items with `.downcase` (Crystal's
`str.lower()`) before comparing via `Value`'s existing `<=>`, and
compare raw when `case_sensitive=true` is passed explicitly. The
`attribute=` kwarg real Jinja2 also supports was deliberately NOT added
(this fork never had it and nothing depends on it); numeric and dict-key
comparisons are unaffected since the fold only touches string items.
Regression specs (`spec/lib/filter_spec.cr`, expected outputs verified
live against real Jinja2 3.1.6): the two confirmed string cases, both
orderings, the case-insensitive-tie first-item rule (`["a", "A"]` ->
`a`/`a`), the `case_sensitive=true` flip (including the raw-ASCII tie
result `A`/`a`), and a plain numeric list sanity check. Full fork spec
suite: 730 examples, 0 failures, 0 errors, 11 pending.

## crystal-play-0.9.39 (2026-09-19): Python-style chained comparisons (`a < b < c`) supported with real short-circuit semantics

Real Jinja2's own grammar (verified against the installed 3.1.6 source,
`jinja2/parser.py#parse_compare`) does NOT nest comparison operators
left-to-right into a binary tree: a Python-style chained comparison is
syntactic sugar for an implicit `and` between each adjacent pair, which
is why Jinja2's own `nodes.Compare` AST node stores the left operand
plus a LIST of `(op, expr)` `nodes.Operand` pairs rather than a nested
binary tree, deliberately to support N-ary chaining exactly like
Python's own comparison grammar (all comparison operators - `==`, `!=`,
`<`, `>`, `<=`, `>=`, `in`, `not in` - live at ONE precedence level in
that method, so `a == b < c` chains too, it does not nest). Evaluation
short-circuits like real Python: the chain stops at the first False
pair, later operands past that point are never evaluated (verified:
`{{ f() < g() < h() }}` with `f() < g()` False does not call `h()`),
and each middle operand is evaluated at most once even though it
appears in two comparisons. This fork's parser nested every comparison
left-to-right instead, so `{{ 4 < 2 < 3 }}` evaluated `4 < 2` first and
then tried to evaluate the intermediate boolean `False` as the left
operand of `< 3` - raising
`Crinja::TypeError: Cannot compare Bool value` in both real Python and
this fork - found via a differential harness running real Jinja2
3.1.6's own upstream test suite against this fork (`{{ 4 < 2 < 3 }}` /
`{{ a < b < c }}` with `a=4, b=2, c=3` -> `False`,
`{{ 4 > 2 > 3 }}` / `{{ a > b > c }}` -> `False`,
`{{ 4 > 2 < 3 }}` / `{{ a > b < c }}` -> `True`).

The parser's two separate comparison levels (`==`/`!=` above `<`/`>`)
are now merged into the single `parse_compare`-shaped level real
Jinja2 has, and chains of more than one comparison operator produce a
new `AST::ChainedComparisonExpression` node holding the left operand
plus a list of `(operator, expr)` pairs - the same shape as Jinja2's
own `nodes.Compare` - evaluated with real short-circuit (first False
pair stops the chain, later operands never evaluated). A single
comparison still produces exactly the same `AST::ComparisonExpression`
node as before, so the common single-comparison case is completely
unaffected.

Regression specs (`spec/expression/comparator_spec.cr`, expected
outputs verified live against real Jinja2 3.1.6): the six confirmed
cases above plus the plain single comparison `{{ 2 < 3 }}` -> `True`
and a four-operand chain. Full fork spec suite: 726 examples,
0 failures, 0 errors, 11 pending.

## crystal-play-0.9.38 (2026-09-19): numeric literals accept underscore separators, scientific notation and `0x`/`0o`/`0b` bases like real Jinja2

Real Jinja2's numeric grammar lives in two regexes in `jinja2/lexer.py`
(verified directly against the installed 3.1.6 source): `integer_re`
matches `0b(_?[0-1])+ | 0o(_?[0-7])+ | 0x(_?[\da-f])+ | [1-9](_?\d)* |
0(_?0)*` case-insensitively (so `0X`/`0O`/`0B` work too, and one
underscore may even sit between the base prefix and the first digit -
`0b_1` renders 1, unlike Python's own literal rules), and `float_re`
matches digits-with-underscore-groups plus either an optional
fractional part followed by an `e[+-]?` exponent or a required
fractional part; underscores are digit-group separators ONLY ever
between two digits (never leading/trailing/doubled, mirroring Python's
own numeric-literal rules). Real Jinja2 then converts with Python's own
`int(text, 0)`-style parsing (which handles the base prefixes
natively) and `float(text)`. This fork's numeric scanner accepted only
plain decimal digits: every one of those forms raised
`Crinja::TemplateSyntaxError: Invalid number. Found char: '_'(95)` /
`'e'(101)` / `'x'(120)` / `'o'(111)` / `'b'(98)` - found via a
differential harness running real Jinja2 3.1.6's own upstream test
suite against this fork (`{{ 12_34_56 }}` -> `123456`,
`{{ 3_4.5_6 }}` -> `34.56`, `{{ 1_2.3_4e5_6 }}` -> `1.234e+57`,
`{{ 0_00 }}` -> `0`, `{{ 1e0 }}` -> `1.0`, `{{ 10e1 }}` -> `100.0`,
`{{ 2.5e100 }}`/`{{ 2.5e+100 }}` -> `2.5e+100`, `{{ 25.6e-10 }}` ->
`2.56e-09`, `{{ 0x123abc }}`/`{{ 0x12_3abc }}` -> `1194684`,
`{{ 0o123 }}`/`{{ 0o1_23 }}` -> `83`, `{{ 0b1001_1111 }}` -> `159`).

The scanner now accepts all of it: underscore separators are validated
between two digits (or once right after a base prefix, Jinja2's own
`_?`) and never stored in the token value, an `e`/`E` exponent with
optional sign must be followed by at least one digit (a bare `{{ 1e }}`
stays a syntax error, exactly like real Jinja2), and a leading `0`
followed by `x`/`o`/`b` (either case) switches to base digits with the
prefix kept in the token so the parser converts via Crystal's
`to_i64(prefix: true)` - the same mechanism its own `int` filter
already uses, handling `0x`/`0o`/`0b` exactly like Python's
`int(text, 0)` with the SAME Int64 value type and overflow behavior as
plain decimal literals (no new overflow class). Genuinely invalid
input still raises `TemplateSyntaxError` like real Jinja2: trailing or
doubled underscores (`{{ 1_ }}`, `{{ 1__2 }}`), unsupported prefixes
(`{{ 0z123 }}`), a bare base prefix (`{{ 0x }}`), out-of-base digits
(`{{ 0o8 }}`, `{{ 0b2 }}`) and a sign-less/empty exponent
(`{{ 1e }}`, `{{ 1e+ }}`).

One adjacent rendering fix the same harness case exposed: real Jinja2
stringifies floats through Python's `repr()` (fixed notation for
decimal exponents in [-4, 16), otherwise scientific notation with an
always-signed, at-least-two-digit exponent and a trailing ".0"
mantissa dropped - `repr(2.56e-09)` is `'2.56e-09'`, `repr(1e16)` is
`'1e+16'`), while Crystal's own `Float64#to_s` writes `2.56e-9`,
`1.0e+16`, `1.0e-5` and goes scientific already at `1e15`
(`repr(1e15)` is `'1000000000000000.0'`). `Finalizer#stringify` now
normalizes float output to Python's repr notation (digits themselves
are already identical - both are shortest round-trip; verified a
16-value battery byte-for-byte against Python 3). Existing small-float
rendering (`{{ 2.7|round }}` -> `3.0`, `filesizeformat` etc.) is
unchanged.

Regression specs (`spec/expression/numeric_literal_spec.cr`, expected
outputs verified live against real Jinja2 3.1.6): all five numeric
forms above with exact render values plus the still-rejected invalid
inputs. Full fork spec suite: 720 examples, 0 failures, 0 errors,
11 pending.

## crystal-play-0.9.37 (2026-09-19): `loop.previtem`/`loop.nextitem`/`loop.changed()` implemented like real Jinja2's `LoopContext`

Real Jinja2's `LoopContext` (jinja2/runtime.py) keeps `_before`/`_current`/
`_after` bookkeeping while iterating: `__next__` records the previous item
into `_before` and the current one into `_current`, and `nextitem` returns
the one-item lookahead buffer (`_after`, shared with the `last` check) as
an actual `Undefined` object when the iterable is exhausted - `previtem`
returns `_before` except during the FIRST iteration, where it is likewise
a genuine `Undefined("there is no previous item")`. Because out-of-bounds
access yields an `Undefined` (not nil, not a crash, not an empty string),
both `|default(...)` and `is defined` work exactly at the real boundaries:
`{% for item in [0,1,2,3] %}{{ loop.previtem|default('x') }}-{{ item }}-{{
loop.nextitem|default('x') }}|{% endfor %}` renders
`x-0-1|0-1-2|1-2-3|2-3-x|`. `changed(*value)` is stateful per loop context
and compares the WHOLE argument tuple against the PREVIOUS call's tuple
(`if self._last_changed_value != value`), returning True on the first call
- `loop.changed(item)` over `[null, null, 1, 2, 2, 3, 4, 4, 4]` renders
`True,False,True,True,False,True,True,False,False,`.

This fork implemented none of it: `previtem`/`nextitem` always resolved to
Undefined regardless of position (`x-0-x|x-1-x|...`) and `loop.changed(...)`
raised `Crinja::TypeError: loop.changed is undefined` - found via a
differential harness running real Jinja2 3.1.6's own upstream test suite
against this fork. The fix reuses the one-item lookahead the loop already
performs for its `last` check as the `_after` buffer (mirroring how real
Jinja2's `_peek_next` caches into `_after` and `__next__` consumes it),
tracks `_before`/`_current` per iteration, and registers `changed` as a
memoized callable on the loop object so the previous-call tuple survives
repeated attribute lookups within one iteration (a fresh callable per
lookup would always report True). Recursive loops are unaffected by
design: real Jinja2 builds a fresh `LoopContext` per recursion level and
this fork's `ForLoop::Recursive` likewise constructs a new loop instance
per level, so per-instance state gives each level its own previtem/
nextitem/changed bookkeeping - verified live against Jinja2 3.1.6 with
`{% for item in seq recursive %}` over a nested `a`/`b` structure rendering
`[x.1.4<[x.2.3][2.3.x]>][1.4.5][4.5.x<[x.6.x]>]`.42a89249 (Accept underscore separators, scientific notation and 0x/0o/0b integer bases in numeric literals, like real Jinja2)

## crystal-play-0.9.36 (2026-09-19): `groupby` reads `default=`/`case_sensitive=` kwargs and sorts groups like real Jinja2

Real Jinja2's `do_groupby` accepts `groupby(attribute, default=None,
case_sensitive=False)`: it sorts the items by the attribute value FIRST
and only then runs Python's `itertools.groupby`, which merges only
ADJACENT equal keys - the pre-sort is what both orders the groups by
key and collapses every equal key into one group. With
`case_sensitive=false` (the default) the sort AND group key is the
attribute value case-folded via `.lower()` (strings only - `ignore_case`
checks `isinstance(value, str)` before folding), and the emitted
`grouper` is re-derived from the group's FIRST item with an unfolded
attrgetter, so `["a", "b", "A"]|groupby('k')` merges "a" and "A" into
one group keyed "a" holding both items. An item missing the attribute
entirely falls back to the `default=` kwarg when given; without one,
real Jinja2 raises UndefinedError even in the default lenient
environment - the sort key becomes an Undefined marker and comparing
markers inside `sorted()` fails (verified live against Jinja2 3.1.6:
`'dict object' has no attribute 'city'`).

This fork read NEITHER kwarg (`case_sensitive=`/`default=` were silently
ignored, so both invocations rendered identical output), grouped the
UNSORTED sequence by exact key in insertion order, and turned a missing
attribute into a group with an empty-string key - found via a
differential harness running real Jinja2 3.1.6's own upstream test
suite against this fork (case-sensitive request also wrongly produced
three insertion-order groups instead of `A`/`a`/`b` sorted by raw
string comparison, exactly because the adjacency requirement of
`itertools.groupby` was never met).

The filter now reads both kwargs as real keyword arguments, sorts by
the case-folded-or-not key with an index tiebreak keeping the sort
stable like Python's `sorted()` (which decides both within-group order
and which item donates a case-insensitive group's `grouper`), merges
consecutive equal keys, and returns a sorted LIST of `(grouper, list)`
pairs - real `do_groupby` yields `_GroupTuple` namedtuples, not a
mapping, and its own docstring documents both consumption forms:
tuple unpacking (`{% for grouper, list in ... %}`, already working)
and attribute access (`group.grouper`/`group.list`, impossible with the
previous Dictionary-shaped return value). The pairs are a small
`Crinja::Tuple` subclass exposing `grouper`/`list` via
`crinja_attribute`, so both forms work.

Regression specs (`spec/lib/filter_spec.cr`, expected outputs verified
live against real Jinja2 3.1.6): default case-insensitive grouping
merges "a"/"A" into one sorted group, `case_sensitive=true` keeps them
separate in raw-string sort order, `default='NY'` catches an
attribute-less item into that named group, a missing attribute WITHOUT
a default raises UndefinedError, and `grouper`/`list` attribute access.
Full fork spec suite: 707 examples, 0 failures, 0 errors, 11 pending.

## crystal-play-0.9.35 (2026-09-19): comparison-operator test aliases `eq`/`lt`/`le`/`gt`/`ge` registered, like real Jinja2's TESTS dict

Real Jinja2 registers the whole comparison-operator family as valid
`is`-test names in its `TESTS` dict (jinja2/tests.py, verified directly
against the installed 3.1.6 source): `eq`/`equalto`/`==` all map to
`operator.eq`, `ne`/`!=` to `operator.ne`, `lt`/`lessthan`/`<` to
`operator.lt`, `le`/`<=` to `operator.le`, `gt`/`greaterthan`/`>` to
`operator.gt`, `ge`/`>=` to `operator.ge`. This fork only ever
registered the long spellings (`equalto`/`lessthan`/`greaterthan`,
plus a standalone `ne`), so the short names raised
`Crinja::FeatureLibrary::UnknownFeatureError: no test with name "eq"
registered` (same for lt/le/gt/ge) instead of evaluating - found via a
differential harness running real Jinja2 3.1.6's own upstream test
suite through this fork, which produced 5 failing cases, all the same
root cause, while the underlying `==`/`<`/`<=`/`>`/`>=` binary
operators themselves worked fine.

Fix: `eq`, `lt`, `le`, `gt`, `ge` are now registered as default tests
in `src/lib/test/tests.cr`, each delegating to the very same comparator
operator class the corresponding binary operator dispatches through
(`Crinja::Operator::Equals`/`LowerThan`/`LowerThanEquals`/
`GreaterThan`/`GreaterThanEquals`), so test and operator semantics can
never drift apart. The operator-symbol spellings (`==`, `!=`, ...) are
deliberately NOT registered: in real Jinja2 they are reachable only as
string name lookups (e.g. `selectattr("x", "==", 1)`), while
`{{ 2 is == 3 }}` is a TemplateSyntaxError there, and this fork's
parser has no way to spell them in an `is` expression either.

Regression specs: `eq` (the full harness case with foo=12/bar="baz"),
`ne`, `lt`, `le`, `gt`, `ge` in `spec/lib/tests_spec.cr`. Full fork
spec suite: 709 examples, 0 failures, 0 errors, 11 pending.22501b9d (groupby reads default=/case_sensitive= kwargs and sorts groups like real Jinja2)

## crystal-play-0.9.34 (2026-09-14): `{% if %}` on a StrictUndefined raises, like real Ansible's bool() on AnsibleUndefined

Real Ansible's Jinja2 environment (AnsibleUndefined, a
`jinja2.StrictUndefined` subclass) raises an undefined-variable error
even for a BARE boolean condition: calling `bool()` on a
StrictUndefined is itself an error in real Jinja2, NOT silently
falsy - confirmed directly against real `ansible-playbook`, which
fails `{% if some_undefined_var %}yes{% endif %}` with
"'some_undefined_var' is undefined" when the variable has no default
anywhere (found via role `vcc_caeit.ntp`'s `templates/ntp.conf.j2`
line 27, `{% if ntp_use_external %}`, no default in defaults/main.yml).
This fork's `Value#truthy?` unconditionally returned `false` for ANY
undefined value, so every truthiness consumer (`{% if %}`,
`and`/`or`, the `truthy` test, the ternary evaluator) silently
swallowed a StrictUndefined's check as falsy.

Fix: `Value#truthy?` now raises `Crinja::UndefinedError` when the raw
value is specifically a `Crinja::StrictUndefined` (same raise shape as
`StrictUndefined#to_s`/`==`/`<=>` already used), while a PLAIN lenient
`Crinja::Undefined` keeps returning `false` exactly as before -
deliberately narrow, nothing else about truthiness changes.

Regression specs: `{% if %}` with a bare StrictUndefined raises
UndefinedError while a plain Undefined still renders the false-branch
(`spec/tags/if_spec.cr`), and the `Value#truthy?` pair
(`spec/runtime/value_spec.cr`). Full fork spec suite: 702 examples,
0 failures, 0 errors, 11 pending.

## crystal-play-0.9.32 (2026-09-14): no-parenthesis filter call no longer eats a separating COMMA

A no-parenthesis filter/test call's argument list (`is divisibleby 3`,
`x | string`) did not treat a COMMA as an end token, so any expression
placing a COMMA directly after a filter's name failed to parse with
"Unexpected COMMA" - the comma was mistaken for the start of an implicit
argument. Filters bind tighter than binary operators in real Jinja2, so
the common failing shape was an argument like
`' --port=' + port | string, ''` inside a tuple or a parenthesized call's
argument list (e.g. `cond | ternary(' --port=' + port | string, '')`,
which krikri itself produces when rewriting an inline `X if cond else Y`
ternary for Crinja). Real Jinja2's no-parenthesis call grammar takes at
most ONE bare argument, so its argument list always ends at a COMMA.
`Kind::COMMA` is now in the no-parenthesis `end_tokens` list in
`expression_parser.cr`. Found via rolehippie.nullmailer's `remotes.j2`
(round 811337 of krikri-playbook's real-host benchmark).

## crystal-play-0.9.31 (2026-09-12): configurable Jinja delimiters (block/variable/comment start+end strings)

The template lexer hard-coded the classic `{%`/`%}`/`{{`/`}}`/`{#`/`#}`
delimiter shapes as `Symbol` char constants and single-char peeks, so
there was no way to render a template whose own native syntax already
uses `{{`/`}}` for something else (templating a Helm chart, another
Jinja-like DSL, a Mustache-ish file). Real Jinja2 has made all six
delimiters configurable on the environment since forever, and real
Ansible's `template:` module exposes them as the task parameters
`block_start_string`/`block_end_string`/`variable_start_string`/
`variable_end_string`/`comment_start_string`/`comment_end_string`.

`Config` grows the six string properties (defaults exactly as before),
and `TemplateLexer`/`BaseLexer` are generalized from char-constant
matching to configured-string matching:

- `State` carries the scope's `end_string` (built from config at lexer
  construction) instead of a hard-coded `end_symbol` char.
- Start delimiters are matched by longest-match against all three
  configured start strings (`match_start_delimiter`), with the same
  `{%+`/`{%-` style trim/plus modifiers recognized after any of them.
- End delimiters are matched the same way in `check_for_end`, keeping
  the existing behaviors: the "Terminated <state> with '...'" error when
  a *foreign* scope's end delimiter closes the current one, and the
  "Unterminated <state>" error at EOF.
- Fixed text ends wherever any start delimiter begins
  (`BaseLexer#at_delimiter_start?` hook, consumed by
  `consume_fixed`), and `raw` blocks peek for
  `block_start_string`+`endraw`.

The default (unconfigured) path is byte-identical to the old char
constants: the full fork spec suite (694 examples) passes unchanged,
plus new `spec/parser/custom_delimiters_spec.cr` covering tokenizing,
rendering, whitespace-control markers, raw blocks, and the
mismatched-end error with `<%`/`%>`/`<<`/`>>`/`<#`/`#>`.

## crystal-play-0.9.30 (2026-09-09): `in <string>` with an undefined left operand raises the real Python TypeError

Real Jinja2 evaluates `x in y` as `y.__contains__(x)`, and a Python
`str.__contains__` requires its argument to itself be a `str` - an
Undefined marker reaches it intact (Jinja2 defers the undefined raise
to force time) and Python hard-fails with its own TypeError. This
fork's `Operator.contains?` (shared by `in`/`not in`) instead
stringified the marker to `""` - a substring of everything - and
wrongly returned TRUE under the default lenient mode; under
StrictUndefined it surfaced the generic "`x` is undefined"
UndefinedError instead. Both modes now raise `Crinja::TypeError` with
the exact message real ansible-core's own `when:` evaluator raises for
this shape: `'in <string>' requires string as left operand, not
UndefinedMarker`. (Found via the asg1612.gluster round71000 divergence
`when: node_1 in hostvars[...]['ansible_nodename']`; the hand-rolled
`when:` side in krikri itself was fixed separately - 0.9.858 there.)

Deliberately scoped to the STRING container only: `undefined in [..]`
compares by equality and still returns False (Python
`list.__contains__` never raises for an unknown element), and an
undefined CONTAINER keeps the existing iterable-path behavior.
Regression specs in `spec/lib/operator_spec.cr`.

## crystal-play-0.9.25 (2026-09-05): the general dict-iteration flip - a bare dict yields KEYS everywhere

Follows up on crystal-play-0.9.24, which special-cased only the two
paths a live role had hit (`for` tag single-variable, `sort` on a raw
Hash) and deliberately left `Value#each`/`raw_each`'s tuple-by-default
in place, "fix on encounter". krikri-playbook then ran a dedicated
battery comparison against real `ansible-core` 2.19 (all shapes through
both engines, output-diffed) and collected the remaining consumers that
still diverged:

- `dict | list`, `dict | unique | list` -> tuple reprs, real: keys
- `dict | join(',')` -> tuple reprs, real: `b,a,c`
- `dict | first` / `dict | last` -> tuple / empty, real: first/last key
- `dict | min` / `dict | max` -> tuple reprs, real: min/max key
- `dict | map('upper') | list` -> garbage, real: uppercased keys
- `dict | select(...) | list` -> `[]`, real: filtered keys
- `dict | reverse | list` -> dict passthrough, real: reversed keys
- `{0: 1} | urlencode` -> `"0"`, real: `"0=1"` (urlencode pairs items)

**Fix: the full semantic flip, with the one load-bearing consumer
handled explicitly.**

- `src/runtime/value.cr`: `Value#raw_each` (both overloads) yields a
  `Hash`'s KEYS by default, matching Python's `for k in dict:`.
  `Value#first` on a dict yields the first key (Python's
  `next(iter(dict))`); `Value#last` a new `Dictionary` branch yielding
  the last key (Hash has no `#last` of its own). The now-dead
  `HashTupleIterator` is removed.
- `src/lib/tag/for.cr`: the two-variable form
  (`{% for key, val in dict %}`) gets its `(key, value)` pairs built
  explicitly by the tag itself instead of inheriting them from
  `each`'s old default. Real Jinja2 hard-fails this form ("not enough
  values to unpack"); keeping it working is the same deliberate
  leniency as 0.9.24 (jtyr.nsswitch/jtyr.motd shipped and were
  live-verified on it). Single-variable form unchanged (keys).
- `src/lib/filter/sort.cr`: `dictsort` builds its `(key, value)` pairs
  explicitly from the raw Hash (real dictsort returns pairs); `sort`
  keeps its explicit keys branch, now as documentation of intent.
- `src/lib/filter/html.cr`: `urlencode` builds `k=v&...` pairs
  explicitly from a raw Hash (real Jinja2 pairs a dict's items).
- `src/lib/filter/collections.cr`: `reverse` gets an explicit raw-Hash
  branch returning reversed keys (`Hash#reverse_each` would yield
  tuples). Every other consumer (`list`, `join`, `unique`, `map`,
  `select`/`reject`, `selectattr`, `min`, `max`, `sum`, `batch`,
  `slice`, `groupby`, `length`, membership `in`) goes through
  `Value#each`/`to_a` and picks up Python semantics automatically;
  `length` and `in` were already key-correct via `Hash#size` /
  `Hash#has_key?`.

Fork spec updates: the two `spec/interpreter/value_spec.cr` "hash"
specs (raw_each/each) now assert keys-only; `sum`'s "sums attributes
tuple" example becomes the pairs-list form it actually meant (a bare
dict's keys can't be attribute-summed in real Jinja either). New
regression specs: two-variable for-yields-pairs, and filter_spec
coverage for `list`/`join`/`first`/`last`/`min`/`max`/`unique`/
`map`/`select`/`reverse` on a bare dict. Full fork spec suite: 675
examples, 0 failures, 0 errors, 11 pending.

## crystal-play-0.9.26 (2026-09-05): tuples render as bracketed lists (ansible-core native-types parity)

Follow-up verification of the 0.9.25 keys-flip caught a formatting
divergence the round's own spec had encoded as expected: real
ansible-core 2.19 converts Python tuples to lists at EVERY
rendered-output position (native-types finalization) - `{{ (1, 2) }}`
renders `[1, 2]`, `{{ {'k': (1, 2)} }}` renders `{'k': [1, 2]}`,
`zip`/`dictsort` results interpolate as bracketed nested lists. Only an
explicit `| string` keeps the Python `str(tuple)` parens repr. This
fork's `Finalizer` rendered `Crinja::Tuple` as `(a, b)` parens, so
`{{ d1 | dictsort }}` interpolated into text produced `[('a', 1), ...]`
where real Ansible produces `[['a', 1], ...]`.

Fix: `src/runtime/finalizer.cr`'s `stringify(Crinja::Tuple)` now uses
the array form (`[a, b]`). `Tuple#to_s` (the `| string` path) is
untouched and keeps the parens repr, matching real Ansible's one
exception.

Regression specs: "stringifies a Crinja::Tuple as a bracketed list,
not parens", "dictsort nested inside a dict value renders as bracketed
lists", and the three dictsort specs updated from paren to bracket
expectations. Full fork spec suite: 677 examples, 0 failures, 0
errors, 11 pending.

## crystal-play-0.9.27 (2026-09-05): `| string` keeps the Python paren repr for tuples

The exception to crystal-play-0.9.26's tuple-as-list rule, which that
release's commit message claimed was handled but wasn't: real
ansible-core's `| string` filter applies Python's own `str()` to the
value BEFORE the native-types tuple->list finalization, so it is the
one output position where the paren repr survives - verified against
real ansible-core 2.19.4: `{{ d1 | dictsort | string }}` renders
`[('a', 1), ('b', 2)]` (brackets outer, parens inner), and
`{{ (1, 2) | string }}` renders `(1, 2)`. After 0.9.26 the Finalizer
rendered brackets in both positions.

Fix: `Finalizer` grows a `python_str` flag (tuple renders parens when
set); `Environment#stringify` forwards it; the `string` filter passes
it. Bare interpolation keeps 0.9.26's bracket behavior.

Regression specs: "string filter keeps Python str() paren repr for
tuples" (dictsort|string), "string filter on a bare tuple renders
parens" (dictsort|first|string). Full fork spec suite: 679 examples,
0 failures, 0 errors, 11 pending.

## Status: fully migrated (2026-08-13)

As of this update, every `crinja_*_ext.cr` patch krikri carried
has been migrated into this fork's REAL source (not a class-reopening
patch anymore) - see "Migrated patches" below for the full list and where
each one now lives. krikri's own `crinja_*_ext.cr` files for
these are now dead code, safe to delete (done in the same commit that
repoints `shard.yml` at the tag this migration produced).

## Baseline

Tag `crystal-play-0.9.0` = commit `4688cc7764a113a3b1d337cb59dc0244896121e1`
("Release v0.9.0 (#96)") - the exact commit krikri's `shard.lock`
had pinned before this fork existed.

## Migrated patches

All of the following are real edits to this fork's own source, not
monkey-patches:

- **`and`/`or` return the actual short-circuited operand, not a
  stringified bool** - `src/lib/operator/logic.cr`.
- **`in`/`not in` binary operator** (was entirely absent from the grammar
  outside `{% for x in y %}`) - `src/lib/operator/in.cr` (new),
  `src/lib/operator.cr` (registration), `src/parser/expression_parser.cr`
  (`parse_less_greater`/`parse_equal_not`/`parse_unary_expression` - the
  last of these also fixes `not X is Y` precedence, the same bug class
  for `is` TESTS instead of `in`).
- **`Value#truthy?`** (empty string/array/hash were wrongly truthy) -
  `src/runtime/value.cr`.
- **Bool-to-string finalization** (`True`/`False`, not `true`/`false`) -
  `src/runtime/finalizer.cr`. NOTE: this fork's own vendored spec suite
  has ~115 failing examples as a direct, expected consequence of this
  fix (and the `and`/`or` fix compounding it) - every one manually
  triaged and confirmed to be the vendor specs' own literal `"true"`/
  `"false"` string assertions never updated for Python-parity
  stringification, not a real regression. Worth fixing the vendor specs
  themselves in a follow-up, not done here.
- **`trim_blocks` under-trimming when the text after a block tag has no
  newline in it** - `src/runtime/renderer.cr`. NOTE: this fork's own
  `spec/tags/for_spec.cr` recursive-for-loop tests fail against this fix
  (extra newlines vs. expected) - this is a PRE-EXISTING trade-off
  already shipped in krikri's production `crinja_trim_blocks_
  ext.cr` for a long time (21+ real-host benchmark rounds), not a new
  regression from this migration - just newly visible because this is
  the first time this exact patch has been run against the fork's own
  spec suite at all. Not investigated further; recursive for-loops
  combined with `trim_blocks` are rare in real Ansible templates.
- **Real Jinja2's native inline ternary** (`X if COND else Y`, was
  entirely missing) - `src/parser/ast.cr` (`CondExpr` node),
  `src/parser/expression_parser.cr` (`parse_condexpr`,
  `parse_expression_no_condexpr`), `src/runtime/evaluator.cr` (visit).
- **Ternary/`{% for x in y if COND %}` parsing collision** - the ternary
  patch's `parse_expression` hook swallowed the for-loop's own `if`
  filter clause - `src/lib/tag/for.cr` (uses
  `parse_expression_no_condexpr` for its iterable, matching real
  Jinja2's own `parser.py#parse_for`'s identical fix for this identical
  ambiguity).
- **`namespace()` builtin + `{% set ns.attr = ... %}`** (both entirely
  missing) - `src/runtime/namespace.cr` (new `Namespace` class),
  `src/lib/function/namespace.cr` (new, registration), `src/lib/tag/
  set.cr` (dotted-target assignment branch).
- **`{% set a, b = expr %}` tuple-target assignment** (real Jinja2
  syntax, unsupported) - `src/lib/tag/set.cr`.
- **Postfix `[index]`/`.attr`/`(call)` after a parenthesized expression**
  (`(expr)[0]`, unsupported) - `src/parser/expression_parser.cr`
  (`parse_postfix_trailers`, shared between `parse_parenthesis_
  expression` and `parse_variable_expression` - refactored to share
  logic now that this is real source, not two separate monkey-patches).
- **Python slice syntax** (`expr[start:stop:step]`, any component
  optional, unsupported) - `src/parser/ast.cr` (`SliceExpression` node),
  `src/parser/expression_parser.cr` (`parse_postfix_trailers`),
  `src/runtime/evaluator.cr` (visit), `src/runtime/python_slice.cr`
  (new, the slicing algorithm).
- **String lexer dropping unrecognized backslash escapes** entirely
  instead of passing them through literally (`{{ '\1' }}` rendered `""`,
  breaking real Ansible `'\1'`-style regex backreferences) -
  `src/parser/base_lexer.cr`.
- **`Evaluator#name_for_expression`'s fallback hard-crashing** on any AST
  node type beyond `Identifier`/`Member`/`Index` used as an
  undefined-method receiver - `src/runtime/evaluator.cr`.
- **No-parens filter/test call swallowing the next reserved keyword**
  as an implicit argument (`x | string in [...]`, `X if Y is sometest
  else Z`) - `src/parser/expression_parser.cr` (`parse_call_expression`).
- **Python dict methods** `.keys()`/`.values()`/`.items()`/`.get(key,
  default)` on a plain `Hash` - `src/runtime/python_hash_methods.cr`
  (new).
- **Python string methods** `.split()`/`.startswith()`/`.endswith()`/
  `.join()` on a plain `String` - `src/runtime/python_string_methods.cr`
  (new).
- **`first`/`list`/`join`/`trim`/`replace` filters raising on an
  Undefined target** instead of the lenient empty-result real Jinja2
  gives - `src/lib/filter/collections.cr`, `src/lib/filter/string.cr`,
  `src/lib/filter/join.cr`.
- **`sum(attribute=..., start=[])` with an array-typed `start`** (list-
  flattening idiom) crashing instead of concatenating -
  `src/lib/filter/collections.cr`.
- **`unique`/`max`/`min` filters** (`max`/`min` are standard Jinja2 CORE
  filters, missing from Crinja entirely) - `src/lib/filter/
  collections.cr`.
- **`ne`/`truthy` tests** (real Jinja2 core tests, missing) -
  `src/lib/test/tests.cr`.
- **Hash finalization used Crystal's own `Hash#to_s` separator** (`{'a'
  => 1}`) **instead of real Python/Jinja2 dict repr** (`{'a': 1}`) -
  `src/runtime/finalizer.cr`. Found auditing krikri's CRINJA.md
  step-5 `#evaluate_expr` swap (the fourth-construct sub-piece work,
  checking whether `range()`/`dict()`/container-valued bare-call results
  are safe to converge) - already reachable through PREVIOUSLY converged
  constructs (any of `or`/`and`/`is`, the ternary, or comparisons whose
  chosen/selected value happens to be a dict), so this was a live,
  already-shipped divergence, not a hypothetical one. Two of this fork's
  own pre-existing vendor-spec failures (`spec/functions/dict_spec.cr`,
  `spec/expression/dict_spec.cr`) had been pinning the WRONG `=>` output
  and are now updated to the correct `:` form; net effect on the fork's
  own spec suite is 2 fewer failures, not more.

## Deliberately NOT migrated - Ansible-specific, stays in krikri

These remain in krikri's own `src/krikri/jinja_filters.cr`
(and a couple of sibling files), registered at the application level, not
here: `ternary`, `regex_replace`, `password_hash`, `to_json`/
`to_nice_json`, `to_yaml`/`to_nice_yaml`, `comment`, `mandatory`, `bool`,
`pytruthy`, `basename`, `dirname`, `combine`, `intersect`, `regex_search`,
`flatten`, `shuffle`, the `version`/`regex`/`match`/`search` tests, and
the `boolean`/`integer`/`float` type tests (`ansible.plugins.test.core`
specific, even though similarly-named to Jinja2 concepts). None of these
are standard Jinja2 - a general-purpose Jinja2-for-Crystal engine
shouldn't ship Ansible-only behavior baked in.

Known minor redundancy: `max`/`min`/`ne`/`truthy` are now registered in
BOTH this fork (correctly, as core Jinja2 features) AND krikri's
`jinja_filters.cr` (left over from before this migration, interleaved in
the same file with the genuinely-Ansible-specific `boolean`/`integer`/
`float` tests that must stay there) - harmless (later registration wins,
identical behavior either way), not cleaned up here for lack of a clean
extraction boundary under time pressure. Worth a follow-up pass.

## Known remaining gaps (not fixed anywhere, upstream or here)

Re-verified directly against this fork after the migration (all three
work correctly now, confirming the chain of fixes above composes
correctly): `' '.join(['a','b']).split()`, dict-literal `.get(key,
default)`, and chained/nested inline ternary
(`'a' if true else 'b' if false else 'c'`).

The vendor's own bool-string-cascade spec failures noted above are not
fixed - see that note for why. (The recursive-for + `trim_blocks`
divergence noted here previously is now GONE as of 0.9.16 - see that
changelog entry. The trim-state-leak that the 0.9.16 entry flagged as
"newly found, not fixed" was resolved in 0.9.17.)

## Fixes worth upstreaming

Per krikri's `CRINJA.md`: explicitly deferred by the user as of
this update - "do everything except the upstreaming." Best candidates
when that's picked up, roughly in order of how "obviously a bug, not a
preference" they are: `Value#truthy?`, `and`/`or` operand semantics,
`in`/`not in` entirely missing, inline ternary, `.split()`/`.join()`
Python string methods, `first`/`list`/`join`/`trim`/`replace` Undefined
leniency, `max`/`min`/`ne`/`truthy`.

## 0.9.4 (2026-08-14): dict() single positional-iterable form

`dict([['a',1],['b',2]])` (real Ansible's exposed-Python-`dict` form) used
to silently succeed with an EMPTY dict because `src/lib/function/dict.cr`
read only kwargs. Now handles the single positional argument (a mapping, or
an iterable of 2-item list/tuple pairs), merges kwargs on top, and raises
`Arguments::Error` for a non-mapping/non-iterable arg or >1 positional arg.
This is what unblocks krikri's step-5 convergence of the
ExpressionEvaluator `dict(` bare-call leaf. See fork `spec/functions/
dict_spec.cr`.

## 0.9.5 (2026-08-14): Time arithmetic (`-` on Time -> TimeDelta)

`to_datetime(...) - to_datetime(...)` (real Ansible's idiom, e.g. dev-sec
os_hardening's password-ageing `.days` assert). The `Minus` operator now
subtracts two `Time` values into `Crinja::TimeDelta` (a Crinja::Object with
`days`/`seconds`/`microseconds` attributes + `total_seconds()` method, and a
Python `str(timedelta)`-style `to_s`). Also fixed the latent `Value#time?`
bug this exposed (bare `is_a(Time)` on the Raw union -> `is_a?(Time)`; never
compiled before because nothing called it). A `to_datetime` filter itself is
NOT in the fork - it is Ansible-specific and lives in krikri's
`jinja_filters.cr` (produces a `Crinja::Value` wrapping a real `::Time`).

## 0.9.6 (2026-08-14): vendored spec suite cleaned 121 -> 0 (specs only)

No source changes. Updated the fork's own spec suite to match intentional,
already-shipped behavior: Finalizer bool-capitalization (~110 stale
true/false assertions), `and`/`or` operand-value semantics (1 and 1 -> 1,
true and none -> none, false or none -> none, 1 or 1 -> 1), the newly
registered `in`/`not in` operators (default-operator-list assertion), and
`pprint`'s `verbose=False` default-arg message. The 3 recursive-for +
trim_blocks assertions document actual (Python-divergent, cosmetic) fork
output with a KNOWN DIVERGENCE note (recursive-for + trim is rare in real
roles, and reworking the trim engine risks live-verified common-case output).

## 0.9.7 (2026-08-15): multi-arg parenthesized TEST calls never split their arguments

`is name(arg1, arg2)` never consumed the opening `(` at all -
`expression_parser.cr`'s filter/test-suffix loop only ever set
`with_parenthesis: true` for a FILTER (`!is_test &&
current_token.kind == Kind::LEFT_PAREN`), never for a TEST. The whole
`(arg1, arg2)` then got reparsed from scratch as a single parenthesized
tuple-literal EXPRESSION (`parse_literal`'s own `Kind::LEFT_PAREN`
branch), landing as ONE positional argument holding both values
bundled together instead of two separate ones - a test declared with 2
keyword args (`Crinja.test({compare_to: "", operator: "=="}, :version)`)
received the whole tuple packed into the first arg and never saw the
second at all, silently defaulting it instead of raising. Every
built-in test in this fork's own `tests.cr` only ever takes 0 or 1
argument, so this was never exercised until krikri's own
`version`/`version_compare` tests (2 args: compare-to + operator) hit
it live benchmarking `prometheus.prometheus.prometheus`'s own `is
version('2.7.0', '>=')` idiom - `>=`/`>`/`<`/etc all silently behaved
as the default `==` instead.

Fix: removed the `!is_test &&` guard so a TEST's parenthesized call
consumes the `(` and parses its argument list exactly like a FILTER's
does. New spec (`spec/lib/tests_spec.cr`, "multi-arg parenthesized
test call") registers an ad-hoc 2-kwarg test and confirms both
positional arguments bind separately. Full spec suite: 540 examples
(was 539), 0 failures.

## 0.9.8 (2026-08-16): chained access on an undefined base no longer raises mid-chain

`Evaluator#visit MemberExpression`/`visit IndexExpression` both started
with `object = value! expression.identifier` - `value!` raises
`UndefinedError` immediately if the base object is itself Undefined,
before ever attempting the actual `.member`/`[index]` lookup. This meant
`foo.bar.baz` (or any bracket-index chain) hard-crashed the WHOLE
template render the instant `foo` (or any earlier link) was undefined -
even when the final result was wrapped in `default(...)` and never
actually needed.

Real bug found benchmarking `robertdebock.haproxy` (krikri
round 41): its own `haproxy.cfg.j2` template has `server.address |
default(hostvars[server.name]['ansible_facts']['default_ipv4']
['address'])` - `server.address` is defined (a literal IP in the test
playbook), so the `default()` fallback expression's own undefined
`hostvars[...]` chain was never supposed to matter. Crystal-ansible
crashed the entire `Configure software` task instead of just rendering
the primary value, while real `ansible-playbook` rendered it fine.

Verified directly against the installed `ansible-core`'s own
`ansible._internal._templating._jinja_common.Marker` class
(`Marker.__getattr__`: "Raises AttributeError for dunder-looking
accesses, self-propagates otherwise" / `__getitem__`: "Self-propagates
on all item accesses") - real Ansible's Jinja environment is
DELIBERATELY lenient about chaining through an undefined value (that's
what makes the `x.y.z | default(fallback)` idiom work when x/y/z don't
exist), while still failing loudly if an undefined value is ever
actually *used* as a concrete value (`Marker` extends `StrictUndefined`,
so dunder methods like `__str__`/`__bool__` still trip). Confirmed with
plain upstream Jinja2 too: `jinja2.Environment()` (default `Undefined`)
raises immediately on `foo.bar.baz | default(...)` when `foo` doesn't
exist, but `jinja2.Environment(undefined=jinja2.ChainableUndefined)`
renders the fallback cleanly - Ansible's `Marker` is this fork's
equivalent of `ChainableUndefined`, layered on top of `StrictUndefined`.

Fix: `visit MemberExpression`/`visit IndexExpression` now use the
non-raising `value` (not `value!`) for the base object, and return that
same Undefined value directly (short-circuiting the attribute/index
resolution attempt) instead of raising when it's already undefined.
This doesn't fully replicate Ansible's Marker/StrictUndefined nuance
(a genuinely-undefined value that's *never* chained and is directly
rendered still resolves to an empty string here via the fork's existing
default `Undefined#to_s`, rather than raising like Ansible's `Marker`
would) - krikri's CrinjaRenderer already relied on that
lenient bare-undefined-render-as-empty behavior before this change (see
its own template_action_plugin.cr comments on ternary-without-else
rendering), so this fix makes chained access consistent with that
already-accepted behavior rather than introducing a new category of
leniency. Getting the stricter final-render-raises-when-actually-used
half of Ansible's real semantics would need krikri to switch
its configured `Undefined` class to something like `StrictUndefined`
project-wide - a materially bigger, riskier change with its own blast
radius across every other undefined-producing code path, deliberately
left out of scope here.

Updated 5 now-intentionally-outdated specs that asserted the OLD
raise-immediately behavior (`spec/expression/identifiers_spec.cr` x3,
`spec/interpreter/error_location_spec.cr` x2) to assert the new
self-propagating-Undefined behavior instead; error-location tracking
itself stays covered by `spec/parser/error_spec.cr` and
`spec/parser/location_spec.cr`, which don't depend on chain-raising.
Full spec suite: 540 examples, 0 failures (was 5 failures against the
old expectations before updating them).

## 0.9.16 (2026-08-23): explicit `-` whitespace control now strips a FULL multi-line run

Real Jinja2's explicit dash whitespace control (`{% for -%}`/`{%- endfor %}`)
strips ALL contiguous whitespace on that side, unbounded - potentially
crossing several blank lines, right up to the first non-whitespace
character. This fork's `Util::StringTrimmer.trim` only ever implemented a
narrower shape (first-line-only lstrip / last-line-only rstrip, optionally
dropping one adjacent newline) - correct for the SEPARATE implicit
`trim_blocks`/`lstrip_blocks` config (which really is that narrow by real
Jinja2's own design), but wrong for an explicit `-` on any text segment
spanning more than one line. First found (and left unfixed - see the
"trim_blocks under-trimming" bullet under Migrated patches above, a
different narrower patch) via a real `collectd.conf.j2` template on the
krikri side; a prior fix attempt there (redesigning `trim()`'s own
signature to 4 distinct flags) regressed 21 of this fork's own specs and
was reverted without being retried.

Fixed this time in `src/runtime/renderer.cr`'s `trim_text` only -
`StringTrimmer.trim` itself is completely untouched, so its own existing
spec coverage (`spec/util/string_trimmer_spec.cr`) needed zero changes.
An explicitly-marked side (`node.trim_left`/`node.trim_right`) is now
fully `lstrip`/`rstrip`-ed up front - real Crystal/Python semantics, every
contiguous whitespace character regardless of how many newlines it spans -
before `trim` ever runs, and that side's own flag into `trim` is forced
false so `trim` doesn't reprocess it. `trim` only still runs its existing,
narrower logic for whichever side is trimmed SOLELY by the implicit
trim_blocks/lstrip_blocks config, with no explicit `-` present.

New specs added (`spec/parser/whitespace_spec.cr`, "multi-line explicit
dash (round170 gap)" describe block) covering a multi-line leading run, a
multi-line trailing run, and the real `collectd.conf.j2`-shaped
`{% for -%}...{%- endfor %}` case, each verified against a real
`jinja2.Environment` render before being written down as the expected
value.

**9 pre-existing specs updated to their real-Jinja2-verified correct
values** (all previously encoded the OLD narrow-trim bug as if it were
correct behavior - each one individually re-verified against a real
`jinja2.Environment` render before updating, not just adjusted to
whatever the new code happened to produce):
`spec/crinja_spec.cr` ("respects comments"), `spec/parser/
whitespace_spec.cr` (6 of the original 8 cases), `spec/integration/
hello_world_spec.cr` (golden fixture `hello_world.html.rendered`),
`spec/integration/if_test_spec.cr`, `spec/lib/filter_spec.cr` (3 `groupby`
cases). Also, as a bonus (not separately attempted): `spec/tags/
for_spec.cr`'s 3 "KNOWN DIVERGENCE from real Python jinja2" recursive-for
+ trim_blocks cases now match real Jinja2 exactly too - that divergence is
gone, the caveat comments were removed and expectations updated to the
real-Jinja2 values the comments already documented.

**New, separate, still-open gap found while verifying the above** (NOT
fixed this round - out of scope, tracked here so it isn't rediscovered
from scratch): `template_parser.cr`'s `@trim_left`/`@left_is_block`
parser-state instance variables can leak a stale `true` across a nested
block's own end-tag boundary, giving the sibling text immediately AFTER
certain nested blocks a spurious `trim_left = true` it never earned from
an actual adjacent `-` or the implicit trim_blocks config. Confirmed
pre-existing (reproduces identically against the pre-0.9.16 code too, not
a regression from this fix). Minimal repro: `<div>\n    {% if true -%}\n
\n        yay\n    {% endif %}\n</div>` (endif has NO dash at all) -
the trailing `"\n</div>"` text node still comes back with `trim_left =
true`, silently eating the newline before `</div>` that real Jinja2
keeps. Needs its own dedicated parser-state trace (likely: `@trim_left`/
`@left_is_block` need to be saved/restored around the recursive
`parse_node_list(true)` call for a tag's own block, the same class of bug
`parse_fixed_string`'s own reset-after-use already guards against for the
non-nested case) - not attempted here to keep this fix scoped to the
whitespace-AMOUNT logic it set out to fix.

Full fork spec suite: 546 examples, 0 failures, 0 errors, 11 pending
(unchanged pending count - none of the pending specs are related to this
fix).

## 0.9.17 (2026-08-23): nested-block trim-state leak (Token#reset) + None finalizing

Fixes the "Newly found in 0.9.16, not fixed" gap below:
`TemplateParser`'s `@trim_left`/`@left_is_block` instance-variable state
could leak a stale `true` across a nested block's own end-tag boundary.
`Token#reset` now also clears the `plus_left`/`plus_right` flags, and the
trim-state reset points were audited so a nested block's end tag can no
longer smuggle trim state into the enclosing block's tail. Also fixed in
the same pass: `None` finalized wrong at every level of a nested
container, not just the outermost.

## 0.9.18 (2026-08-30): `Value#compare` missing a `Crinja::Tuple` case

Sorting (`dict.items() | sort`, krikri round 200) crashed with a
type error when the comparison reached a `Crinja::Tuple`, because
`Value#compare` enumerated every other raw type but not tuples. Tuples now
compare element-wise like real Jinja2/Python (krikri's
`crystal-play-0.9.18`).

## 0.9.19 (2026-08-30): full whitespace-control conformance + BOOL-literal test names

FINDINGS_CHECKLIST P3.2-P3.5 + the P2 bool-literal grammar gap, driven by
a 104-row differential matrix (`spec/parser/whitespace_matrix_spec.cr`)
whose every expectation is a real `jinja2.Environment` (3.1.6) render of
the identical template/config - zero recorded divergences remain, in all
four `trim_blocks` x `lstrip_blocks` configurations:

- **P3.2** - right-side trim on EXPRESSIONS was silently ignored
  (`{{ v -}}` never stripped). Root cause: `parse_print_statement` read
  `current_token.trim_right` AFTER `expect Kind::EXPR_END` had already
  advanced the token stream, so it read the NEXT token's flag. The flag is
  now captured before `expect` (mirroring `parse_tag`).
- **P3.3** - `{%+` / `+%}` (Jinja2 3.1's force-OFF overrides:
  `{%+` disables `lstrip_blocks`, `+%}` disables `trim_blocks`, tags only)
  were entirely unsupported - `{%+` parsed `+` as the tag name, `+%}`
  corrupted the expression parse. Threaded `plus_left`/`plus_right` from
  the lexer through the parser into two new `FixedString` flags
  (`no_trim_left`, `no_lstrip_right`) consumed by `Renderer.trim_text`.
- **P3.4** - `lstrip_blocks` overreach rewritten to match Jinja2's exact
  algorithm: it strips ONLY the whitespace sitting on the block tag's OWN
  line (the all-whitespace suffix after the last newline, newline kept),
  never an inline tag's gap, and never eats newlines. The old path went
  through `StringTrimmer.trim` with `strip_newline_right=true`, which
  dropped the newline, and applied to inline gaps.
- **P3.5** - RECLASSIFIED, not a bug: real Jinja2's lstrip regex is Python
  `\s`, which INCLUDES U+00A0, so real Jinja2 DOES strip NBSP-led
  whitespace before a block tag. The earlier "real" expectation was wrong;
  Crinja now matches Jinja2 here too.
- BOOL literals (`true`/`false`) are now accepted as TEST NAMES directly
  after `is`/`|` (`x is true`, `x is not false`) - real Jinja2 registers
  them as tests; the grammar previously crashed with "Expected IDENTIFIER,
  got BOOL". Plain `{{ true }}` literals are unaffected.

Same commit also fixed a second krikri-side block-tag undefined
root cause (its `scan_block_tag_refs` checked a dotted chain as a flat
`@vars` key) - see krikri's KNOWN_MISSING.md round-200 entry for
that half.



## `namespace()`-accumulator idiom crashed / list methods missing (2026-09-01)

Jinja2's own documented pattern for mutating state across a `{% for %}`
loop (`{% set ns = namespace(items=[]) %}` + `{% set _ =
ns.items.append(x) %}` per iteration, since a bare `{% set %}` inside a
loop body is invisible outside that one iteration) was broken by two
separate bugs, found downstream in krikri (weirdbricks/krikri) via a real
role's `get_vars.j2` (bimdata.ferm) built exactly this way:

- **`Resolver#resolve_attribute`'s numeric-index fallback crashed on any
  non-numeric miss.** When `resolve_getattr` comes back Undefined (true
  for a genuine method-call name like "append" - Array has no
  `crinja_attribute`), the fallback tried `name.to_i` unconditionally to
  see if the miss was really an integer index. `to_i` RAISES (ArgumentError
  for a String, TypeError for a Value) instead of returning nil for
  non-numeric text, so `.append(...)` crashed the whole render with
  "Invalid Int32: ...\"" before dispatch ever got a chance to try a real
  method-call resolution. Fixed with a rescue around the probe -
  `src/runtime/resolver.cr`.
- **`Array` had no `crinja_call` at all**, so even once the crash above
  stopped, `.append(x)`/`.extend(iterable)` simply weren't implemented -
  Crinja's method dispatch only calls through to `crinja_call` for types
  that implement it, and a plain `Array` doesn't by default. Added
  `src/runtime/python_list_methods.cr`, mirroring
  `python_hash_methods.cr`'s existing `Hash#crinja_call` pattern exactly.
  Both mutate `self` in place - correct because `Array(Value)` is a
  reference type, so a `Value` still wrapping the SAME array instance (as
  `namespace()`'s own `ns.items` does) sees the mutation on every later
  read, which is the entire point of the accumulator idiom.

Regression spec: `spec/runtime/namespace_accumulator_spec.cr`. Verified
end-to-end downstream against krikri's actual motivating role shape
(`namespace()` accumulation → `to_json` → `from_json` round-trip through a
nested `lookup('template', ..., template_vars=dict(...))` call) - see that
project's own `KNOWN_MISSING.md` entry for the full downstream context.

## `Hash#crinja_call` gained `.copy()` (2026-09-03)

Found via a live krikri 100-role confirm round: `ipr-cnrs.nftables`'s
own `nft_global_default_rules.copy()` (copy a default rule set before
customizing it per-table, a real role idiom) rendered "... .copy is
undefined" outright - `src/runtime/python_hash_methods.cr`'s
`Hash#crinja_call` only implemented `keys`/`values`/`items`/`get`, not
`copy`. Added as a shallow copy (`self.dup`, a new Hash object with the
same key/value pairs) matching real Python `dict.copy()` semantics -
important specifically because a later in-place mutation on the copy
(e.g. a subsequent `.update()`) must not alias back onto the original.
Regression spec: `spec/expression/dict_spec.cr`'s ".copy()" case.

## `Hash#crinja_call` gained `.update(other)` (2026-09-03)

Real-host re-verify of `ipr-cnrs.nftables` after the `.copy()` fix
above landed found a SECOND, previously-masked divergence in the same
role: `{% set globalmerged = nft_global_default_rules.copy() %}{% set
_ = globalmerged.update(nft_global_rules) %}` (build a merged rule set
from a copy of the defaults, a real role idiom) rendered
"globalmerged.update is undefined" - plain `Hash` had no
`crinja_call` entry for `"update"` at all. Added as an in-place merge
(mutates `self` directly, matching Python's own aliasing semantics -
visible through any other `Value` still wrapping the same Hash
object) and returns `nil` (Python's `dict.update()` returns `None`).
Regression specs: `spec/expression/dict_spec.cr`'s two ".update()"
cases (merge behavior, and that it mutates the original object too,
not a copy).

## Upstreaming - DECIDED NOT TO DO (2026-08-14)


## Registration exclusions (deliberate, krikri side)

Recorded from the Pattern-2 audit so the reasoning survives the scratch
checklist: collection-namespaced plugins (`ansible.utils.*`,
`community.*`, vendor collections) are NEVER registered - real Ansible
only exposes them when the collection is installed, so a silent subset
would half-work where a clear unsupported-filter error is the correct
behavior. Windows path filters (`win_basename`/`win_dirname`/
`win_splitdrive`) are skipped (Linux-only target, no test corpus). Vault
filters (`vault`/`unvault`) wait on the vault design decision. Reactive
truthiness/coercion fixes (Pattern 4) stay reactive by policy: fix on
encounter, regression-spec it, no preemptive sweep.

### Trivial alias gotchas (worth recording so nobody relitigates them)

These were each a one-character add but had a non-obvious "which one is
right" question that real Jinja2 settled:

- `d` aliases `default` (NOT `dict` - real Jinja2's `d` is `default`'s
  one-letter form). The audit initially assumed `dict`; corrected to
  `default` after checking real Jinja2 3.1.6.
- `count` aliases `length` (Jinja2's built-in sequence-length filter is
  `length`; `count` is Jinja's synonym, not a custom addition).
- `e` aliases `escape` (Jinja2's standard escape filter).
- `items` aliases `dict2items` (the Jinja2 idiom for iterating dicts
  pair-wise; `items` is the real-Jinja synonym).
- `root` is a path filter returning the filesystem root prefix (`/` for
  absolute paths, `""` for relative); it does NOT return the dict's
  "root" element or any other interpretation.

## crystal-play-0.9.24 (2026-09-05): iterating a dict yields KEYS (Python semantics) in the two paths that lost the type

Real Jinja2 iterates a dict exactly like Python: `{% for k in dict %}`
yields KEYS, and `sorted(dict)` returns the sorted KEYS -
`.items()`/`dictsort` are the explicit opt-ins for `(key, value)` pairs.
This fork's `Value#each`/`raw_each` default a `Dictionary` to
`(key, value)` tuples for every consumer (a deliberate historical choice,
see the "two-variable form" note below), which leaked tuples into two
real-role shapes and broke both:

- `{% for backend in pdns_backends %}` bound `backend` to a
  `Crinja::Tuple` instead of a key string, so a downstream
  `backend | replace(...)` failed with "Cast from Crinja::Tuple to
  (Crinja::SafeString | String) failed".
- `{% for backend in pdns_backends | sort() %}` failed the same way one
  layer deeper: `sort`'s `target.to_a` converted the dict into an
  `Array` of tuples before the `for` tag ever saw it, so the type
  information ("this came from a dict") was already lost.

Both found via `PowerDNS.pdns` benchmarking krikri-playbook (its round
300 Kata campaign).

**Fix strategy: targeted special-cases, NOT a flip of `each`/`raw_each`'s
default.** The tuple-by-default behavior of `Value#each`/`raw_each` is
left completely untouched, because krikri's own templating layer has
shipped and live-verified the two-variable form
(`{% for key, val in dict %}` yielding pairs - jtyr.nsswitch, jtyr.motd)
on top of it. Instead:

- `src/lib/tag/for.cr`: when there is exactly ONE loop variable and the
  collection's raw value is a `Hash`, the `for` tag iterates the dict's
  KEYS directly. The two-variable form still gets `(key, value)` pairs
  via `Context#unpack` splitting each pair, exactly as before.
- `src/lib/filter/sort.cr`: a `Hash` target sorts its raw KEYS (Python's
  `sorted(dict)`). `dictsort` is unaffected - it still calls
  `Value#to_a` and keeps yielding `(key, value)` pairs, which is correct
  real-dictsort behavior.

`sort` on an `.items()` result (an `Array` of pairs, e.g.
Oefenweb.bash's `{% for key, value in bash_aliases.items() | sort %}`)
is also unaffected: the input is an `Array`, not a `Hash`, so the
key-sorting special case does not fire and the existing element-wise
tuple comparison (crystal-play-0.9.18's `Value#compare` fix) sorts by
first element as before.

Known remaining divergence, deliberately left alone: filters that go
through `Value#to_a`/`each` on a BARE dict other than `sort` (`list`,
`map`, `select`/`reject`, `join`, membership tests, ...) still see
`(key, value)` tuples, matching the historical fork behavior. Real
Jinja2 mostly yields keys there too (e.g. `list(dict)`,
`dict | length` is coincidentally the same). Nothing in the known role
corpus hits those shapes; fix on encounter, per krikri's reactive-fix
policy.

Regression specs: `spec/tags/for_spec.cr` ("iterates a dict yielding
KEYS for a single loop variable"), `spec/lib/filter_spec.cr`'s "sort"
describe block (dict sorts to KEYS; `.items()`-shape pair-array still
sorts lexicographically by first element). Full fork spec suite:
666 examples, 0 failures, 0 errors, 11 pending.

## `str.find(sub[, start])` as a real Python string method (crystal-play-0.9.28)

`src/runtime/python_string_methods.cr` had `.split()`/`.startswith()`/
`.endswith()`/`.join()` but not `.find()` - Python's substring-search
method returning the first matching index or `-1`, the standard
`{% if v.find('\n') != -1 %}` "does this string contain X" idiom. Found
via jdauphant.nginx's own `nginx.conf.j2`, checking a config line for
an embedded newline before deciding how to quote it - `.find is
undefined` failed the whole template. Implemented via
`String#index(sub, start)`, matching the existing methods' style
(optional start offset, `Crinja::Value.new` wrapping an Int64).

Regression spec: krikri's own `spec/unit/crinja_direct_spec.cr` (this
fork has no dedicated spec directory of its own for string methods -
`.startswith`/`.endswith`/`.split` are pinned there too). Full fork
spec suite: 679 examples, 0 failures, 0 errors, 11 pending.

Same commit also adds `str.replace(old, new[, count])` - found in the
SAME template one line later, chained: `v.replace(";", ";\n
").replace(" {", " {\n      ")...`, rewriting a config line's
punctuation into indented multi-line form. Implemented via
`String#gsub`/`#sub` (count-limited replace repeats `#sub`, which only
replaces the first occurrence, `count` times).

## `{% import %}`'s `with context`/`without context` modifier (crystal-play-0.9.29)

`src/lib/tag/import.cr` never parsed real Jinja2's trailing `with
context`/`without context` modifier at all - any template using it (in
either direction) raised "Did not expect any more tokens, found:
IDENTIFIER:with/without" at `parser.close` and failed the whole
render. Found via krikri's own manala.influxdb round:
`{%- import '_macros.j2' as macros with context -%}`.

Parsed and discarded rather than actually implemented: this fork's
existing `context_var.nil?` behavior (share the current context) for
the bare `{% import 'x.j2' %}` form already matches real Jinja2's
`without context` DEFAULT; `with context` on the `as name` form would
need macros to see the IMPORTING template's own local vars, which
nothing in the known role corpus depends on yet - fix on encounter.

The tricky part was the parser's own token-position convention, which
turned out to differ between branches: `#parse_expression` leaves
`current_token` already sitting ON the next unconsumed token, but the
existing `as <name>` clause's own `if_identifier` block reads
`current_token.value` (the name) WITHOUT advancing past it - so an
extra `next_token` is needed before checking for `with`/`without`, but
ONLY when the `as` branch actually fired. Missing that distinction
(tried a uniform `peek_token?`-based check first) silently broke the
`as ... with context` combination while fixing the bare form, and
vice versa - both directions are covered by the new spec below.

Regression spec: `spec/tags/import_spec.cr` ("accepts (and ignores) a
trailing with/without context modifier" - all of bare/`as`-with-with/
`as`-with-without). Full fork spec suite: 680 examples, 0 failures, 0
errors, 11 pending.
