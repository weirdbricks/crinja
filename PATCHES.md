# PATCHES.md

This is a fork of [straight-shoota/crinja](https://github.com/straight-shoota/crinja),
maintained for [crystal-ansible](https://github.com/weirdbricks/crystal-ansible)
(a from-scratch `ansible-playbook` reimplementation in Crystal, which vendors
Crinja as its Jinja2 template engine for real `.j2` template rendering).

## Why this fork exists

See `crystal-ansible`'s own `CRINJA.md` (repo root, not committed as of this
writing - a working-notes/strategy doc, read it first if you're picking up
Crinja-related work) for the full reasoning. Short version: crystal-ansible
patches Crinja behavior by reopening its Crystal classes from small
`crinja_*_ext.cr` files rather than editing `lib/crinja` directly (which is
`.gitignore`d and refetched by every `shards install`). That worked, but
`shard.yml` pointed at `branch: master` upstream, which means any
`shards update` could silently pull a refactor that breaks one of those
class-reopening patches without warning. This fork exists so
crystal-ansible can pin to a **tag or commit it controls**, and so lexer-
level fixes that monkey-patching genuinely can't reach (see below) have
somewhere to actually live.

Upstream is not abandoned but is in maintenance-only mode (roughly one
substantive commit a year, mostly Renovate CI bumps) - the rebase burden of
maintaining this fork is expected to stay low. Re-check upstream activity
periodically; if it picks back up, prefer upstreaming clean fixes over
carrying them here (see "Fixes worth upstreaming" below).

## Baseline

Tag `crystal-play-0.9.0` = commit `4688cc7764a113a3b1d337cb59dc0244896121e1`
("Release v0.9.0 (#96)") - the exact commit crystal-ansible's `shard.lock`
already had pinned before this fork existed. Forking introduces **zero**
behavior change on its own; `shard.yml` in crystal-ansible now points here
instead of upstream, pinned to that same commit, purely to control the
update path going forward.

## Patches carried in `crystal-ansible`'s own `crinja_*_ext.cr` files (NOT yet migrated here)

Per crystal-ansible's `CRINJA.md`: "Do not big-bang port the six
`crinja_*_ext.cr` patches - migrate each into the real source file the next
time you need to touch it." As of this fork's creation, none have been
migrated - crystal-ansible's monkey-patch files remain the authoritative
source for all of the following. This section is a manifest so a future
migration knows what exists and where to find it (paths relative to the
`crystal-ansible` repo):

- `src/crystal_play/crinja_trim_blocks_ext.cr` - reopens `Crinja::Renderer`,
  full replacement of `self.trim_text`.
- `src/crystal_play/crinja_truthy_ext.cr` - reopens `Crinja::Value#truthy?`
  (empty string/array/hash were wrongly truthy).
- `src/crystal_play/crinja_bool_ext.cr` - bool-to-string finalization
  (`True`/`False` not `true`/`false`).
- `src/crystal_play/crinja_hash_ext.cr` - `Hash#crinja_call` for
  `.keys()`/`.values()`/`.items()` Python dict methods.
- `src/crystal_play/crinja_string_ext.cr` - misc string method additions.
- `src/crystal_play/crinja_ternary_expr_ext.cr` - adds Jinja2's inline
  ternary (`X if COND else Y`) as a new AST node + parser rule + evaluator
  visit. Real, valid Jinja2 syntax that was entirely absent from the
  grammar. **Good upstream PR candidate** (see below) - a from-scratch
  grammar addition, not an Ansible-specific behavior.
- `src/crystal_play/crinja_logic_ext.cr` - `and`/`or` returned a
  stringified bool instead of the actual short-circuited operand
  (`'' or 'fallback'` rendered `"True"`, not `"fallback"`). Genuine
  Python/Jinja2-semantics bug, **good upstream PR candidate**.
- `src/crystal_play/crinja_in_operator_ext.cr` - the `in`/`not in` binary
  operator was entirely absent from the grammar outside `{% for x in y %}`.
  Adds `Operator::In`/`Operator::NotIn` plus three parser-level changes
  (new infix rule, removes a pre-existing bug where bare `not` was wrongly
  treated as its own binary comparator, fixes `not X in Y` precedence).
  **Good upstream PR candidate** - this is core Jinja2 grammar, not
  Ansible-specific, and the missing-operator bug plus the bare-`not`
  comparator bug are both real correctness issues independent of Ansible.
- `src/crystal_play/crinja_undefined_filter_ext.cr` - `first`/`list`/
  `join`/`trim`/`replace` raised on an Undefined target instead of the
  lenient empty-result real Jinja2 gives (`soft_str()`-mediated leniency);
  also adds the `unique` filter, unregistered entirely upstream. Both the
  leniency fix and `unique` are **good upstream PR candidates** - neither
  is Ansible-specific.
- `src/crystal_play/crinja_namespace_ext.cr` - `namespace()` builtin was
  entirely unregistered, and `{% set ns.attr = ... %}` dotted-target
  assignment (real Jinja2's one exception to `{% set %}`'s bare-name-only
  rule) wasn't parseable at all. Adds a `Crinja::Namespace` class
  (`include Crinja::Object`, mutable Hash-backed attributes) + a
  `Crinja.function(:namespace)` registration, and a full replacement of
  `Tag::Set#interpret` adding a third target-shape branch alongside the
  existing block-set and keyword-list forms. **Good upstream PR
  candidate** - core Jinja2 language feature, not Ansible-specific, and
  the single largest missing-feature gap this fork's differential harness
  found (it's what ended crystal-ansible's round 21 benchmark).

Filters that ARE Ansible-specific and intentionally live only in
crystal-ansible's `src/crystal_play/jinja_filters.cr`, never migrate here:
`ternary`, `regex_replace`, `password_hash`, `to_json`/`to_nice_json`,
`to_yaml`/`to_nice_yaml`, `comment`, the `version`/`regex` tests, etc.

## Known remaining gaps (not yet fixed anywhere, upstream or here)

From crystal-ansible's `CRINJA.md`, found via its differential test
harness (`scripts/crinja_corpus/` in that repo) comparing raw Crinja
against real Python jinja2 on ~3700 real-world Ansible-authored Jinja
expressions:

- `namespace()` builtin not registered at all, and even once it exists,
  `{% set ns.attr = ... %}` dotted-target assignment is a second, separate
  missing feature (real Jinja2's `{% set %}` only supports a bare name
  target otherwise).
- Nested/chained inline ternary (`a if b else c if d else e`) fails to
  parse - `crinja_ternary_expr_ext.cr`'s `parse_condexpr` handles one
  level, not the right-associative chain.
- Dict literal `.get(key, default)` method call unsupported.
- Chained Python-style string methods (`' '.join(x).split()`) fail.
- An unparenthesized filter call immediately followed by `in` swallows
  `in` as a bare filter argument instead of stopping (`x | string in
  ['a','b']` fails) - `parse_call_expression`'s no-parens `end_tokens` set
  doesn't include `Kind::IDENTIFIER`.
- Trim marker (`-`) on an expression tag (`{{ expr -}}`), not just a block
  tag - genuinely a lexer-level bug (likely in
  `src/parser/template_lexer.cr`'s expression-mode tokenizing, a different
  code path from the block-tag-mode `check_for_end`, which is correct).
  Currently worked around in crystal-ansible via text-level preprocessing
  before Crinja ever sees the template (not a real fix - see that repo's
  `CrinjaRenderer#normalize_expression_trim_markers`).
- `-%}`/`{%-` explicit whitespace-control markers under-trim by one blank
  line in some cases - likely the same lexer-level root cause as the item
  above. Deliberately left unfixed as purely cosmetic in crystal-ansible
  (a stray blank line an INI parser ignores).

Both trim-marker items are exactly the kind of fix this fork exists for -
neither is reachable via class-reopening from outside `lib/crinja`.

## Fixes worth upstreaming

Per crystal-ansible's `CRINJA.md` Decision 2/3: upstream activity is real
(outside-contributor PRs do get merged), so anything here that's a clean,
non-Ansible-specific correctness fix should go back as a real PR to
`straight-shoota/crinja`, regardless of what else happens with this fork.
Best candidates, roughly in order of how "obviously a bug, not a
preference" they are:

1. `Value#truthy?` (empty string/array/hash should be falsy - direct
   Python `bool()` semantics mismatch).
2. `and`/`or` returning the actual short-circuited operand, not a
   stringified bool.
3. The `in`/`not in` binary operator being entirely absent.
4. Inline ternary (`X if COND else Y`) - standard Jinja2 syntax, not an
   extension.
5. `.split()` with no arguments (Python's whitespace-run split).
6. `first`/`list`/`join`/`trim`/`replace` leniency on Undefined, and the
   `unique` filter.

None of these have been submitted upstream yet as of this fork's creation.
