# Pattern 2 Audit: Jinja/Ansible filter & test coverage gap

Done 2026-08-30. Companion to `CRINJA_FINDINGS.md` (Pattern 2).

## Method

1. Dumped Crinja's registered default library at runtime
   (`crystal run scripts/inventory.cr` in this repo):
   **50 filters, 24 tests, 7 functions**.
2. Dumped ansible-core's builtin registrations on this machine
   (ansible 2.19.4: `ansible-doc -t filter -l` / `-t test -l`):
   **259 filters, 111 tests** (many are collection-namespaced plugins
   like `ansible.utils.*` / `community.general.*` — out of scope for the
   core engine; real Ansible only has them when the collection is
   installed, and crystal-ansible deliberately fails on collection
   filters per KNOWN_MISSING.md).
3. **Critical correction to the naive diff**: crystal-ansible's
   `src/crystal_play/jinja_filters.cr` (~1900 lines) registers a large
   set of Ansible filters/tests *directly into Crinja's global default
   library* (`Crinja.filter(:ternary) ...`, `Crinja.test(:version) ...`).
   So the real gap list is ansible-core minus (Crinja defaults ∪
   crystal-ansible registrations), not minus Crinja alone. A diff
   against Crinja alone shows ~70 missing core filters; the true number
   after the union is **11 core filters and 18 core tests**.

## Actual gap: core filters

Filters in ansible.builtin that neither Crinja nor
`crystal_play/jinja_filters.cr` registers:

| filter | real-world usage | risk |
|---|---|---|
| `zip` | moderate (parallel lists) | medium |
| `zip_longest` | low | low |
| `subelements` | moderate (looping over nested structures) | medium |
| `strftime` | low-moderate | low |
| `to_datetime` | low | low |
| `combinations` / `permutations` | low | low |
| `flatten` with `levels` arg | **already covered** — crystal-ansible has `flatten`; verify `levels` kwarg support | check |
| `count` | alias of `length` in Jinja; low | trivial |
| `d` / `e` | Jinja aliases for `dict`/`escape`; trivial | trivial |
| `items` | alias-ish for `dict2items`-style use; low | trivial |
| `root` | path filter (`~/x` expansion base); low | trivial |
| `urlsplit` | crystal-ansible has it in filter_engine but check whether it reaches Crinja's env | check |
| `win_basename` / `win_dirname` / `win_splitdrive` | Windows-only; skip | skip |
| `rekey_on_member` | low | low |
| `shuffle` / `pow` / `product` / `log` | log/pow exist in filter_engine; verify registration reaches Crinja env | check |
| `unvault` / `vault` | vault-only; crystal-ansible has vault support — verify | check |
| `regex_search` / `regex_findall` | registered in jinja_filters.cr — they appear in *both* lists in some diffs; re-verify at implement time | check |

## Actual gap: core tests

| test | notes | risk |
|---|---|---|
| `issubset` / `issuperset` | crystal-ansible registers `subset`/`superset`; the `is*` spellings are missing | **medium — `is subset(x)` vs `is subset` already bitten once** |
| `is_dir` / `is_file` / `is_link` / `is_mount` | `directory`/`file`/`link`/`mount` registered; `is_*` spellings missing | **medium — FQCN-adjacent alias class** |
| `is_same_file` | `same_file` registered; `is_*` spelling missing | low |
| `is_abs` | absolute-path test | low |
| `isnan` / `nan` | float NaN test | low |
| `true` / `false` / `falsy` | Crinja has `truthy`; `truthy` covers most, but `x is true`/`x is false` spellings missing | **medium — boolean-identity tests are common in roles** |
| `abs` | abs-as-test (rare spelling) | trivial |
| `uri` / `url` | URL-shaped-string test; moderate usage in roles that validate vars | medium |
| `filter` / `test` | meta-tests (`x is filter('json')`); rare | low |

## Python-isms re-check (non-filter items from Pattern 2)

Verified present in Crinja src, no action:
- `~` concat operator (`src/lib/operator/tilde.cr`)
- arithmetic `*` `/` `//` (`multiply.cr`, `divide.cr`, `int_divide.cr`)
- paren-tuple parsing / tuple-unpack loops (`src/parser/expression_parser.cr:418`, `src/runtime/tuple.cr`)
- ternary, dict `.items()`/`.keys()`/`.values()`, Python string methods
  (`src/runtime/python_string_methods.cr`, `python_slice.cr`, `python_hash_methods.cr`)
- Tuple comparison for sorting (fixed as crystal-play-0.9.18)

## Recommendation / order of attack

1. **First (highest value, ~1 day): the `is*` test spelling pass.**
   `issubset`, `issuperset`, `is_dir`, `is_file`, `is_link`, `is_mount`,
   `is_same_file`, `is_abs` — all are one-line aliases of
   already-implemented tests. Register them in
   `crystal_play/jinja_filters.cr` next to their base implementations.
   Same class of fix as the `eq`/`equalto` alias fix already there
   (line ~1333).
2. **Second: `true`/`false`/`falsy` tests** — three two-liners, close
   out the boolean-identity class.
3. **Third: `uri`/`url` test** and the **`zip`/`zip_longest`/
   `subelements` filters** — the only remaining items with plausible
   real-role frequency.
4. **Skip entirely**: collection-namespaced plugins (`ansible.utils.*`,
   `community.*`, cloud/vendor collections — KNOWN_MISSING.md already
   treats these as unsupported-by-design), Windows path filters,
   vault filters pending the vault check.

Where to implement: in crystal-ansible's `jinja_filters.cr`
(registrations land in Crinja's global library and are then visible to
both the hand-rolled evaluator path and pure-Crinja template renders,
e.g. the `template:` module and Pattern-1 re-render paths). Do **not**
add them inside this fork — that would fork ansible-specific semantics
into a generic Jinja engine and diverge this vendored copy further.

Verification: after implementing, re-run
`crystal run scripts/inventory.cr` from a process that also requires
crystal-ansible (or grep the combined registration list) and diff
against `/tmp/ansible_filters.txt` + `/tmp/ansible_tests.txt` again;
the core (un-namespaced) gap should shrink to the deliberate skips.
