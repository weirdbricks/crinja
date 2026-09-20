# Return whether the object is callable.
Crinja.test(:callable) { target.callable? }

# Returns `true` if the variable is defined.
# See the `default()` filter for a simple way to set undefined variables.
Crinja.test(:defined) { !target.undefined? }

# Returns `true` if the variable is undefined.
Crinja.test(:undefined) { target.undefined? }

# Returns `true` if the variable is nil.
Crinja.test(:none) { target.raw.nil? }

# Returns `true` if the variable is nil.
Crinja.test(:nil) { target.raw.nil? }

# Returns `true` if the object is a mapping (dict etc.).
Crinja.test(:mapping) { target.mapping? }

# Check if a variable is divisible by a number.
Crinja.test({num: Crinja::UNDEFINED}, :divisibleby) { target.to_i % arguments["num"].to_i == 0 }

# Check if an object has the same value as another object:
# ```
# {% if foo.expression is equalto 42 %}
#     the foo attribute evaluates to the constant 42
# {% endif %}
# ```
# This appears to be a useless test as it does exactly the same as the == operator, but it can be useful when used together with the selectattr function:
# ```
# {{ users | selectattr("email", "equalto", "foo@bar.invalid") }}
# ```
Crinja.test({other: Crinja::UNDEFINED}, :equalto) { target == arguments["other"] }

# Checks if an object points to the same memory address than another object:
Crinja.test({other: Crinja::UNDEFINED}, :sameas) { target.sameas? arguments["other"] }

# Returns `true` if the variable is lowercased.
Crinja.test(:lower) { target.to_s.chars.all?(&.lowercase?) }

# Returns `true` if the variable is upcased.
Crinja.test(:upper) { target.to_s.chars.all?(&.uppercase?) }

# Returns `true` if the variable is a string.
Crinja.test(:string) { target.string? }

# Returns `true` if the variable is a string.
Crinja.test(:escaped) { target.raw.is_a?(Crinja::SafeString) }

# Returns `true` if the variable is a number.
Crinja.test(:number) { target.number? }

# Returns `true` if the variable is a sequence. Sequences are variables that are iterable.
Crinja.test(:sequence) { target.sequence? }

# Returns `true` if the variable is iterable.
Crinja.test(:iterable) { target.iterable? }

# This tests an integer if it is even.
Crinja.test(:even) { target.to_i.even? }

# This test an integer if it is odd.
Crinja.test(:odd) { target.to_i.odd? }

# Checks if value is less than other.
Crinja.test({other: 0}, :lessthan) { target.to_i.<(arguments["other"].to_i) }

# Checks if value is greater than other.
Crinja.test({other: 0}, :greaterthan) { target.to_i.>(arguments["other"].to_i) }

# Real Jinja2's `TESTS` dict (jinja2/tests.py, verified against the
# installed 3.1.6 source) registers the whole comparison-operator family
# as `is`-test names - `eq`/`equalto`/`==` -> operator.eq, `ne`/`!=` ->
# operator.ne, `lt`/`lessthan`/`<` -> operator.lt, `le`/`<=` ->
# operator.le, `gt`/`greaterthan`/`>` -> operator.gt, `ge`/`>=` ->
# operator.ge - so `{{ 2 is eq 2 }}`, `{{ 2 is le 2 }}` etc. are plain
# core-Jinja2, not exotic syntax. This fork only ever registered the
# long spellings (`equalto`/`lessthan`/`greaterthan`), so the short
# names raised
# `Crinja::FeatureLibrary::UnknownFeatureError: no test with name "eq"
# registered` instead of evaluating. Found via a differential harness
# running real Jinja2 3.1.6's own upstream test suite through this fork:
# 5 failing cases, all the same root cause (missing short-name
# registrations while the underlying `==`/`<`/`<=`/`>`/`>=` operators
# worked fine). The registrations below deliberately delegate to the
# very same comparator operator classes the binary operators dispatch
# through, so the tests and the operators can never drift apart.
Crinja.test({other: Crinja::UNDEFINED}, :eq) {
  Crinja::Operator::Equals.new.value(env, target, arguments["other"])
}
Crinja.test({other: 0}, :lt) {
  Crinja::Operator::LowerThan.new.value(env, target, arguments["other"])
}
Crinja.test({other: 0}, :le) {
  Crinja::Operator::LowerThanEquals.new.value(env, target, arguments["other"])
}
Crinja.test({other: 0}, :gt) {
  Crinja::Operator::GreaterThan.new.value(env, target, arguments["other"])
}
Crinja.test({other: 0}, :ge) {
  Crinja::Operator::GreaterThanEquals.new.value(env, target, arguments["other"])
}

# Real Jinja2 3.1.6's `TESTS` dict (jinja2/tests.py) ALSO registers the
# operator spellings themselves as bare test names - `"==": operator.eq`,
# `"!=": operator.ne`, `"<": operator.lt`, `"<=": operator.le`,
# `">": operator.gt`, `">=": operator.ge` - so a string lookup like
# `selectattr("state", "==", "present")` is plain core-Jinja2. This fork
# only registered the word spellings, so the operator spellings raised
# `UnknownFeatureError: no test with name "==" registered` instead.
# Resolved through the existing alias mechanism, pointing at the exact
# same callables the word spellings resolve to. As in real Jinja2, this
# only affects STRING lookups: `{{ 2 is == 3 }}` stays a parse error
# there (the `is` operator consumes a test NAME, not an operator), so
# there is no parser interaction to worry about.
Crinja::Test::Library.alias "==", "eq"
Crinja::Test::Library.alias "!=", "ne"
Crinja::Test::Library.alias "<", "lt"
Crinja::Test::Library.alias "<=", "le"
Crinja::Test::Library.alias ">", "gt"
Crinja::Test::Library.alias ">=", "ge"

# Check if value is in seq.
Crinja.test({seq: Array(Crinja::Value).new}, :in) {
  seq = arguments["seq"]
  raw = seq.raw
  case raw
  when Hash
    raw.has_key? target.raw
  when Enumerable
    raw.includes? target.raw
  else
    if seq.string?
      seq.to_s.includes?(target.to_s)
    else
      raise seq.inspect
    end
  end
}

# `ne` - real Jinja2 core test (not equal), the missing sibling of
# `equalto`/`eq`.
Crinja.test({other: Crinja::UNDEFINED}, :ne) { target != arguments["other"] }

# `truthy` - real Jinja2 2.11+ core test (Python `bool(value)`).
Crinja.test(:truthy) { target.truthy? }
