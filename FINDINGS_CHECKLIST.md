# Findings Fix Checklist

Living tracker for everything actionable in `CRINJA_FINDINGS.md`
(inventory made 2026-08-30). Mark items `[x]` only when the fix AND its
specs land. One PR-style commit batch per item; never batch unrelated
items. See PATTERN2_AUDIT.md for the Pattern 2 methodology.

## Spec requirements (applies to every item)

- Multiple specs per item, not one: happy path + type/edge cases +
  argument variants + (where applicable) a regression case tied to the
  real role usage that motivated it.
- Cross-path parity: anything expressible in a template must be tested
  through BOTH the hand-rolled evaluator path AND a pure-Crinja render
  (`Crinja.new.render`), since this project's history is divergence
  between the two engines.
- Strict-undefined interaction: any fix touching variable resolution
  must run the three reverted-attack specs (`nested_undefined_chain_spec.cr`,
  `variable_substitutor_blocktag_undefined_spec.cr`,
  `var_substitutor_caching_spec.cr`) unchanged.

## Pattern 1 — recursive re-templating (crystal-ansible)

- [x] P1.1 `resolve_simple` re-render gap (`traefik_install_ver` class).
  FIXED 2026-08-30 — but the ROOT CAUSE turned out to be something else
  entirely, which is why the prescribed approach ("design strict/undefined
  semantics for a `resolve_simple` re-render") would have been wrong
  (and why the first attempt, at that layer, broke the three reverted-
  attack specs). Two actual causes, both fixed:
  1. `variable_substitutor.cr#scan_block_tag_refs` matched a
     dotted/bracketed chain (`SCAN_STRICT_BLOCK_TAG_REF`) and checked it
     as a FLAT `@vars` key (`has_key?("traefik_ver.major")`), which never
     exists — so every `{% if %}` condition using ordinary attribute
     access on a defined dict/list was "undefined" under strict.
     `CrinjaRenderer.convert_var` asks exactly that probe
     (`unresolvable_template?`) before handing Crinja a value → the whole
     variable became `Crinja::Undefined` → a bare
     `{{ traefik_install_ver }}` rendered the literal sentinel and
     `include_tasks: 'v{{ ... }}.yml'` became `vundefined.yml`. Fixed by
     resolving the chain by its ROOT (matches ansible-core 2.19.4: a
     defined root + missing attribute is a different error class there).
  2. `crinja_renderer.cr#rerender_string_value` only re-rendered values
     containing `{{`; a pure `{% %}`-block value reached Crinja's context
     raw. Invisible for a bare `{{ v }}` (the outer re-pass loop saves
     that shape) but fatal as a FILTER-CHAIN HEAD (`{{ v | upper }}`
     uppercased the tag keywords, so no later pass could parse them) and
     as a `default()` argument. Fixed: the re-render now fires for
     `{%`/`{#` too.
  `resolve_simple` itself stays deliberately RAW — it is the strict
  chain-walker's lookup primitive (`raise_if_strict_undefined` walks the
  chain through it and must still raise on the innermost missing name),
  which is exactly the interaction the original design note worried
  about. The three reverted-attack specs pass unchanged.
  Specs: `spec/unit/blocktag_dotted_attr_strict_spec.cr` (12).
- [x] P1.2 Structural cleanup / guard. Superseded in form, delivered in
  substance: the audit found that the "centralized re-render layer" was
  the wrong abstraction for this bug class — the per-call-site
  `rerender_if_templated` calls are load-bearing and `resolve_simple`
  must stay raw (see P1.1). What P1.2 prescribed as the deliverable — a
  guard that makes a resolution path returning raw `{{ }}`/`{% %}` text
  fail loudly — landed as
  `spec/unit/blocktag_value_resolution_parity_spec.cr`: a parity table
  driving a BLOCK-TAG-valued variable through every known resolution
  path (bare / dotted / indexed / filter-chain head / default() arg /
  ternary branch / inside-a-larger-literal-string / include_tasks
  filename shape under strict), plus a strict-negative asserting a
  genuinely-missing root still raises. The audit itself found and fixed
  one more real call-site gap (`rerender_string_value`'s `{{`-only
  guard, P1.1 cause #2). Specs: 9.

## Pattern 2 — missing Jinja/Ansible surface (implement in crystal-ansible
`src/crystal_play/jinja_filters.cr` unless noted)

### Tests (alias/thin-wrapper batch)
- [x] P2.1 `issubset` / `issuperset` (aliases of registered
  `subset`/`superset`)
- [x] P2.2 `is_dir` / `is_file` / `is_link` / `is_mount` (aliases of
  `directory`/`file`/`link`/`mount`)
- [x] P2.3 `is_same_file` (alias of `same_file`), `is_abs`
- [x] P2.4 `true` / `false` / `falsy` tests (Crinja has `truthy` only)
- [x] P2.5 `uri` / `url` URL-shape tests
- [x] P2.6 `abs`-as-test, `isnan` / `nan`
- [x] P2.7 `filter` / `test` meta-tests (low priority, last of batch)

### Filters
- [x] P2.8 `zip` / `zip_longest`
- [x] P2.9 `subelements`
- [x] P2.10 `strftime` (must match Python strftime directives actually
  used in roles; document supported directive subset)
- [x] P2.11 `to_datetime`
- [x] P2.12 `combinations` / `permutations`
- [x] P2.13 trivial aliases: `count` (=length), `d` (=dict), `e`
  (=escape), `items` (dict2items-style), `root`
  (NOTE: `d` aliases `default`, not `dict` — real Jinja2 semantics;
  see the registration-site comment in crystal-ansible jinja_filters.cr)
- [x] P2.14 `rekey_on_member`
- [x] P2.15 VERIFY-then-fix: `flatten(levels=...)`, `urlsplit`,
  `log`, `pow`, `regex_search`, `regex_findall` exist in
  filter_engine.cr — confirm their registrations reach Crinja's env
  (pure-Crinja render test); if not, register/forward like the others.
  VERIFIED 2026-08-30: all six already reach Crinja's env; no fix
  needed. Permanent canary specs in crystal-ansible
  spec/unit/filter_batch2_spec.cr.

### Deliberate exclusions (do not implement; document in code comment)
- [ ] P2.X1 collection-namespaced plugins (`ansible.utils.*`,
  `community.*`, vendor) — env-dependent, must stay a clear
  unsupported-filter error (KNOWN_MISSING.md ~540)
- [ ] P2.X2 Windows path filters (`win_basename`, `win_dirname`,
  `win_splitdrive`) — Linux-only target, no test corpus
- [ ] P2.X3 vault filters (`vault`/`unvault`) — blocked on the vault
  design decision

### Cross-cutting
- [ ] P2.16 Parity spec file: one spec that renders every newly
  registered filter/test through BOTH engines and asserts identical
  output (or documents a justified difference), so future divergence is
  a failing test, not a benchmark round.

## Pattern 3 — whitespace/trim control

- [x] P3.1 Whitespace conformance matrix spec.
  DONE 2026-08-30 as `spec/parser/whitespace_matrix_spec.cr` (104 rows =
  26 delimiter-forms × 4 trim_blocks/lstrip_blocks configs). Every expected
  value was generated from a real `jinja2.Environment` render (3.1.6), none
  hand-guessed. Regenerated again after fixes P3.2–P3.4 below: there are NO
  remaining recorded divergences — every row is now a conformance row matching
  Crinja's output byte-for-byte. Full suite: 655 examples, 0 failures.

- [x] P3.2 Right-side `-%}`/`-}}` trim on EXPRESSIONS was ignored.
  Root cause: `template_parser.cr#parse_print_statement` read
  `current_token.trim_right` AFTER `expect Kind::EXPR_END`, which had already
  advanced the stream past the closing token — so it read the NEXT token's flag
  (always false). Fixed by capturing `current_token.trim_right` BEFORE `expect`
  (mirrors what `parse_tag` already did). `{{ v -}}` now strips trailing
  whitespace exactly like `{% ... -%}`.

- [x] P3.3 `{%+` / `+%}` (Jinja2 3.1 `+` forms) implemented. These force-OFF
  the config-side implicit trim for one tag: `{%+` disables lstrip_blocks,
  `+%}` disables trim_blocks. Changes:
  - `symbol.cr`: added `PLUS = '+'`.
  - `token.cr`: added `plus_left` / `plus_right` flags (reset in `reset`).
  - `template_lexer.cr`: `next_token_root` recognizes `{%+` (tags only, not
    `{{`/`{#`); `check_for_end` recognizes `+%}` (tags only, not `+}}`) and
    sets `plus_right`.
  - `template_parser.cr`: `parse_tag` threads `no_lstrip_right` (to the
    previous fixed sibling) and `@no_trim_left` (to the next fixed).
  - `ast.cr` / `renderer.cr`: `FixedString` gained `no_trim_left` /
    `no_lstrip_right`; `trim_text` consults them.

- [x] P3.4 `lstrip_blocks` overreach fixed. Rewrote `renderer.cr#trim_text` to
  match Jinja2's exact algorithm instead of going through `StringTrimmer.trim`
  with `strip_newline_right=true` (which dropped newlines) and applying to
  inline gaps. Now: (a) implicit trim_blocks removes exactly ONE newline after
  a block tag, (b) implicit lstrip_blocks strips ONLY the block tag's OWN line
  (whitespace suffix after the last newline), keeping the newline, and only
  when that suffix is entirely whitespace and a newline is present — so inline
  tags are never lstripped. `char#whitespace?` includes NBSP, matching Python's
  `\s`. No longer eats newlines; does not touch inline tags.

- [x] P3.5 NBSP — RECLASSIFIED, not a bug. Real Jinja2's lstrip regex is
  `\s+` (Python), which INCLUDES U+00A0, so real Jinja2 DOES strip NBSP-led
  whitespace before a block tag. The original "real" expectation in this
  checklist was wrong (verified against jinja2 3.1.6: `nbsp_indent` renders
  `"A\n\n\xa0 V\n\nB"`). After the P3.4 trim_text rewrite, Crinja strips NBSP
  identically to Jinja2. Kept in the checklist for the record.

## Pattern 4 — truthiness/coercion (reactive)

- [ ] P4.0 No preemptive work. When one bites, fix it AND add it to
  this checklist as a completed reactive fix with a back-reference to
  the benchmark round. (Keeps the pattern observable without spending
  preemptive effort.)

## Pattern 5 — architectural convergence: DONE, nothing to do.
