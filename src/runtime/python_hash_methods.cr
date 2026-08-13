# Real Python dict methods as plain method calls - `.keys()`/`.values()`/
# `.items()`/`.get(key, default)`. Crinja's method dispatch (`Resolver#
# resolve_getattr`/`resolve_method`) only calls through to `crinja_call`
# for types that implement it; a plain `Hash` doesn't by default.
class Hash(K, V)
  def crinja_call(method : String) : Crinja::Callable::Proc?
    case method
    when "keys"
      ->(_arguments : Crinja::Arguments) { Crinja::Value.new(self.keys.map { |key| Crinja::Value.new(key) }) }
    when "values"
      ->(_arguments : Crinja::Arguments) { Crinja::Value.new(self.values.map { |value| Crinja::Value.new(value) }) }
    when "items"
      ->(_arguments : Crinja::Arguments) do
        Crinja::Value.new(self.map { |key, value| Crinja::Value.new([Crinja::Value.new(key), Crinja::Value.new(value)]) })
      end
    when "get"
      # Works for both a Hash-valued template variable (String keys) and
      # a `{...}` dict LITERAL parsed inside a template (a
      # `Crinja::Dictionary` = `Hash(Value, Value)`) - the `is_a?` branch
      # below handles both without assuming K's concrete type.
      ->(arguments : Crinja::Arguments) do
        lookup = arguments.varargs[0]? || Crinja::Value.new(nil)
        default = arguments.varargs[1]? || Crinja::Value.new(nil)
        found = self.find do |k, _v|
          key_value = k.is_a?(Crinja::Value) ? k.as(Crinja::Value) : Crinja::Value.new(k)
          key_value == lookup
        end
        if found
          v = found[1]
          v.is_a?(Crinja::Value) ? v.as(Crinja::Value) : Crinja::Value.new(v)
        else
          default
        end
      end
    else
      nil
    end
  end
end
