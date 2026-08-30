# Crinja Findings

A pattern analysis of crystal-ansible's git history with respect to this
vendored fork, done 2026-08-30 by grepping `git log` in the crystal-ansible
repo for Crinja-related commits. Purpose: identify recurring bug classes
worth a preemptive fix or feature audit, rather than continuing to catch
one call site per benchmark round.

## Headline number

**123 of ~1042 commits (≈12%) in crystal-ansible's history touch Crinja
directly.** That is a high rate for a vendored dependency, and the
commits cluster into a small number of repeating themes rather than being
evenly spread across many unrelated one-off bugs.

## Pattern 1: Recursive re-templating (biggest by far, ~54 commits project-wide)

A variable whose own stored value is itself unrendered Jinja (`{{ }}` or
`{% %}`) does not get re-rendered before use. This is not really a
"missing feature" - it's a systemic gap where every new code path that
resolves a variable needs its own re-render check, and they keep getting
missed one call site at a time. It spans BOTH the hand-rolled evaluator
in crystal-ansible proper and Crinja's own vars context.

Independently fixed occurrences (each found live, months apart, in a
different call site):
- Bare-lookup fallback in the hand-rolled `ExpressionEvaluator`
- Dotted-access base value in `VariableLookup#resolve_nested`
- `default(...)` filter argument
- Loop (`with_items`/`loop:`) sources - both a plain re-render gap AND
  (crystal-ansible round 200) a ternary-selecting-a-list source that
  only ever saw Crinja's Python-repr display text instead of the real
  structured value
- Block-tag values re-rendered through Crinja specifically (`{% if %}`
  stored as a variable's own value) - 0.9.190, 0.9.239
- Nested-undefined chains (0.9.599: `follow the chain, not just the
  reference`)
- Round 199: a `vars:`-level mixed literal+template string
  (`"{{ x }}/y"`) fed into a chained `.lstrip()` method call
- Round 200: `resolve_simple` (bare, undotted variable lookup) still
  lacks this fix - found via `andrewrothstein.traefik`'s
  `traefik_install_ver` (`{% if %}...{% endif %}` stored as a plain var,
  reached as a sub-expression inside `include_tasks: 'v{{ x }}.yml'`).
  A fix was attempted and reverted: adding the re-render to
  `resolve_simple` and to `expression_evaluator.cr`'s bare-variable
  Crinja fallback broke three existing strict-undefined specs
  (`nested_undefined_chain_spec.cr`, `variable_substitutor_blocktag_
  undefined_spec.cr`, `var_substitutor_caching_spec.cr`) - the
  strict/undefined interaction needs to be worked out carefully, not
  copied from the analogous dotted-access branch. Documented in
  crystal-ansible's `KNOWN_MISSING.md`, not yet fixed.

**Recommendation:** worth a structural fix rather than more whack-a-mole.
A single centralized "always re-render on read, everywhere a raw value
leaves `@vars`" layer - with the strict/undefined semantics designed in
from the start rather than retrofitted - would likely retire this bug
class permanently. The `resolve_simple` gap above is the best next
target: it's the single most common lookup path (any bare `{{ var }}`
reference) and the one call site everyone assumes already has this fix
because sibling call sites do.

## Pattern 2: Missing Jinja2/Python-isms Crinja never implemented (~20 commits)

Crinja is a strict Jinja2 engine; real Ansible's Jinja environment runs
on actual Python and inherits Python syntax/stdlib idioms Crinja had no
reason to support on its own. Every round that hits a role using one of
these finds it cold. Examples already found and fixed:

- `lookup()` global function and its sub-types (env, file, pipe,
  template, password, vars, first_found, url, config)
- `dict.items()` / `.keys()` / `.values()`
- Tuple-unpacking for-loops: `{% for (k, v) in dict.items() %}` /
  `{% for key, value in ... %}` (Crinja had neither the paren-tuple
  loop-var form nor `dict.items()` - 0.9.119)
- Python string methods: `.split()`, `.lstrip()`/`.rstrip()`/`.strip()`,
  `.join()`
- Ternary expression: `X if C else Y`
- Arithmetic operators: `*`, `/`, `//`, and the `~` string-concat operator
- `dict2items` / `items2dict` / `intersect` / `difference` /
  `to_nice_yaml` / `mandatory` filters
- Dynamic dict-literal keys: `{{ {expr: val} }}`
- `is version(...)` / `is regex(...)` tests (Ansible's own, not standard
  Jinja2)
- FQCN-qualified filter/test names
- "successful"/"failure"/"change"/"skip" result-test aliases
- Tuple comparison for sorting (`dict.items() | sort`) - crystal-ansible
  round 200, fixed here as `crystal-play-0.9.18`

**Recommendation:** this one is enumerable and therefore genuinely
preemptable, unlike Pattern 1. Worth a deliberate audit: diff the set of
builtin Jinja filters/tests/globals real `ansible-core`'s Jinja
environment exposes (its own `ansible.template.vars`/`ansible.plugins.
filter`/`ansible.plugins.test` registrations, not just base Jinja2)
against what Crinja currently registers, and pre-implement the gaps
rather than waiting for the next role to trip over one. A good
side-channel source for "which ones actually get used in the wild": the
KNOWN_MISSING.md native-typing passive frequency scan crystal-ansible
already runs against its downloaded role corpus.

## Pattern 3: Whitespace/trim control (~6 commits)

`{%-`/`-%}` explicit dash control, `trim_blocks`, `lstrip_blocks`, and
NBSP handling have each had at least one real bug, spread across the
project's whole history (0.9.126, 0.9.264, round 85, 0.9.507, and the
fork-level fix at `crystal-play-0.9.16`). Smaller volume than patterns 1
and 2, but recurring enough that it's clearly a fragile area of the
lexer rather than a set of unrelated one-offs. Worth a dedicated
whitespace-control conformance test pass (a table of every
combination of `{%`/`{%-`/`{%+`, block-vs-inline, and
`trim_blocks`/`lstrip_blocks` on/off) rather than continuing to fix one
combination at a time.

## Pattern 4: Truthiness / type-coercion edge cases (steady trickle)

Empty list/dict/string truthiness, boolean stringification
(`"True"`/`"False"` Python-repr vs lowercase), Python-repr-vs-JSON
round-tripping when a container value crosses the Crinja/JSON::Any
boundary, and (crystal-ansible round 200) `Crinja::Tuple` comparison for
sorting. One new corner found every so often rather than a cluster -
lower priority than 1-3, reactive fixing is probably fine here.

## Pattern 5: One-time architectural convergence (~15 commits, already done)

`CRINJA.md` documents a deliberate project (crystal-ansible 0.9.310
through 0.9.342-ish) to converge the hand-rolled `ConditionalEvaluator`/
`ExpressionEvaluator` onto Crinja's real recursive-descent parser
construct-by-construct, finding real bugs at each step (infinite
recursion, stack overflow, filter-chain dispatch). This is complete, not
an open pattern - included here only for completeness of the historical
picture.

## Bottom line

If choosing where to spend preemptive effort: **Pattern 1** (recursive
re-templating) for a structural fix, and **Pattern 2** (missing
Python-isms) for a feature-completeness audit. Patterns 3 and 4 are
real but low-volume enough that catching them reactively, one benchmark
round at a time, is a reasonable trade-off.
