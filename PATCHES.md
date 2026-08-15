# PATCHES.md

This is a fork of [straight-shoota/crinja](https://github.com/straight-shoota/crinja),
maintained for [crystal-ansible](https://github.com/weirdbricks/crystal-ansible)
(a from-scratch `ansible-playbook` reimplementation in Crystal, which vendors
Crinja as its Jinja2 template engine for real `.j2` template rendering).

## Why this fork exists

See `crystal-ansible`'s own `CRINJA.md` (repo root) for the full reasoning.
Short version: crystal-ansible originally patched Crinja behavior by
reopening its Crystal classes from small `crinja_*_ext.cr` files rather
than editing `lib/crinja` directly (which is `.gitignore`d and refetched
by every `shards install`). That worked, but `shard.yml` pointed at
upstream `branch: master`, which means any `shards update` could
silently pull a refactor that breaks one of those class-reopening
patches without warning. This fork exists so crystal-ansible can pin to
a **tag it controls**, and so real source-level fixes (not monkey-patches)
have somewhere to live.

## Status: fully migrated (2026-08-13)

As of this update, every `crinja_*_ext.cr` patch crystal-ansible carried
has been migrated into this fork's REAL source (not a class-reopening
patch anymore) - see "Migrated patches" below for the full list and where
each one now lives. crystal-ansible's own `crinja_*_ext.cr` files for
these are now dead code, safe to delete (done in the same commit that
repoints `shard.yml` at the tag this migration produced).

## Baseline

Tag `crystal-play-0.9.0` = commit `4688cc7764a113a3b1d337cb59dc0244896121e1`
("Release v0.9.0 (#96)") - the exact commit crystal-ansible's `shard.lock`
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
  already shipped in crystal-ansible's production `crinja_trim_blocks_
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
  `src/runtime/finalizer.cr`. Found auditing crystal-ansible's CRINJA.md
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

## Deliberately NOT migrated - Ansible-specific, stays in crystal-ansible

These remain in crystal-ansible's own `src/crystal_play/jinja_filters.cr`
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
BOTH this fork (correctly, as core Jinja2 features) AND crystal-ansible's
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

The vendor's own spec suite failures noted above (bool-string cascade,
recursive-for trim_blocks) are not fixed - see those notes for why.

## Fixes worth upstreaming

Per crystal-ansible's `CRINJA.md`: explicitly deferred by the user as of
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
This is what unblocks crystal-ansible's step-5 convergence of the
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
NOT in the fork - it is Ansible-specific and lives in crystal-ansible's
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
argument, so this was never exercised until crystal-ansible's own
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

## Upstreaming - DECIDED NOT TO DO (2026-08-14)

The "Fixes worth upstreaming" list below is DEAD: none of these will be
submitted as PRs upstream. They remain permanently here in the fork (all
migrated into real source as of 0.9.3). Do not re-open.
