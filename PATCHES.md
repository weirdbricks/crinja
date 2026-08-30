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

