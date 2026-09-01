# Real Python list mutating methods as plain method calls - `.append(x)`/
# `.extend(iterable)`. Crinja's method dispatch (`Resolver#resolve_getattr`/
# `resolve_method`) only calls through to `crinja_call` for types that
# implement it; a plain `Array` doesn't by default. Mirrors
# `python_hash_methods.cr`'s own `Hash#crinja_call` pattern.
#
# `Array(Value)` is a reference type in Crystal (a class, not a struct) -
# mutating `self` in place is visible through every other `Crinja::Value`
# still wrapping the SAME array instance, which is exactly what makes
# Jinja2's documented `namespace()`-accumulator idiom work:
#   {% set ns = namespace(items=[]) %}
#   {% for x in some_list %}{% set _ = ns.items.append(x) %}{% endfor %}
#   {{ ns.items }}
# `ns.items` returns a `Value` wrapping the one Array stored in the
# `Namespace`'s own data hash - appending to it through that wrapper
# mutates the array `ns.items` will resolve to on every later read, since
# a `{% set %}` inside a `{% for %}` body would otherwise be invisible
# outside that one iteration (the very problem `namespace()` exists to
# solve - see `runtime/namespace.cr`'s own comment).
class Array(T)
  def crinja_call(method : String) : Crinja::Callable::Proc?
    case method
    when "append"
      ->(arguments : Crinja::Arguments) do
        value = arguments.varargs[0]? || Crinja::Value.new(nil)
        self << value.as(T)
        Crinja::Value.new(nil)
      end
    when "extend"
      ->(arguments : Crinja::Arguments) do
        other = arguments.varargs[0]? || Crinja::Value.new([] of Crinja::Value)
        other.each { |item| self << item.as(T) }
        Crinja::Value.new(nil)
      end
    else
      nil
    end
  end
end
