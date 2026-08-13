# Real Jinja2's `namespace()` builtin creates a mutable-attribute object
# that, unlike a plain `{% set %}` variable, is NOT re-scoped fresh on
# each `{% for %}` iteration - the standard way to accumulate/mutate
# state across a loop in Jinja2, since a bare `{% set %}` inside a
# `{% for %}` body is invisible outside that one iteration.
class Crinja::Namespace
  include Crinja::Object

  def initialize(@data = Hash(String, Crinja::Value).new)
  end

  def []=(key : String, value : Crinja::Value)
    @data[key] = value
  end

  def crinja_attribute(attr : Crinja::Value) : Crinja::Value
    key = attr.to_s
    @data.fetch(key) { Crinja::Value.new(Crinja::Undefined.new(key)) }
  end
end
