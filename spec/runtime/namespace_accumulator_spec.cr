require "../spec_helper"

# Jinja2's documented namespace()-accumulator idiom - mutating a list
# across `{% for %}` iterations via `{% set _ = ns.items.append(x) %}`,
# since a bare `{% set %}` inside a `{% for %}` body is invisible outside
# that one iteration. Found broken end-to-end downstream in krikri
# (weirdbricks/krikri), root-caused to two bugs here:
#
# 1. Resolver#resolve_attribute's fallback numeric-index probe called the
#    raising `name.to_i` for ANY failed attribute lookup, including a
#    genuine method-call name like "append" - crashing the whole render
#    with "Invalid Int32: ..." before dispatch ever reached a real
#    method-call resolution.
# 2. Array had no `crinja_call` at all, so even once #1 stopped crashing,
#    `.append(x)` (and `.extend(x)`) simply weren't implemented - real
#    Python list methods, mirrored here the same way python_hash_methods.cr
#    already does for Hash#keys/#values/#items/#get.
describe "namespace()-accumulated list, mutated via .append()/.extend()" do
  it "mutates the SAME underlying array across for-loop iterations, visible after the loop ends" do
    result = render(<<-JINJA)
      {%- set ns = namespace(items=[]) -%}
      {%- for x in [1, 2, 3] -%}
        {%- set _ = ns.items.append(x) -%}
      {%- endfor -%}
      {{ ns.items }}
      JINJA

    result.should eq("[1, 2, 3]")
  end

  it "supports .extend(iterable) merging another list in" do
    result = render(<<-JINJA)
      {%- set ns = namespace(items=[1]) -%}
      {%- set _ = ns.items.extend([2, 3]) -%}
      {{ ns.items }}
      JINJA

    result.should eq("[1, 2, 3]")
  end

  it "does not crash when a non-numeric, non-method attribute is accessed on an indexable value" do
    # Regression guard for the resolver fix's own failure mode: any
    # genuinely-missing attribute name on an Array (not just "append")
    # must resolve to Undefined, not raise, once the numeric-index
    # fallback's own `to_i` rejects it.
    result = render(<<-JINJA)
      {{ [1, 2, 3].nonexistent_attribute is undefined }}
      JINJA

    result.should eq("True")
  end

  it "still resolves a genuine numeric index through the same fallback path" do
    result = render(<<-JINJA)
      {{ [10, 20, 30]["1"] }}
      JINJA

    result.should eq("20")
  end
end
