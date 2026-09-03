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
    when "update"
      # Python dict.update(other) - merges other's key/value pairs into
      # self IN PLACE (self is the same Hash object the caller already
      # holds a reference to, so this mutation is visible through any
      # other Value still wrapping it - matching real Python's own
      # aliasing semantics) and returns None. Found via ipr-cnrs.
      # nftables: `{% set globalmerged = nft_global_default_rules.copy()
      # %}{% set _ = globalmerged.update(nft_global_rules) %}` (build a
      # merged rule set from a copy of the defaults, a real role idiom),
      # which rendered "globalmerged.update is undefined" outright since
      # plain Hash had no crinja_call entry for it.
      ->(arguments : Crinja::Arguments) do
        other = arguments.varargs[0]? || Crinja::Value.new(nil)
        if (other_hash = other.raw).is_a?(Hash)
          other_hash.each do |k, v|
            key = k.is_a?(Crinja::Value) ? k.as(Crinja::Value) : Crinja::Value.new(k)
            val = v.is_a?(Crinja::Value) ? v.as(Crinja::Value) : Crinja::Value.new(v)
            self[key.as(K)] = val.as(V)
          end
        end
        Crinja::Value.new(nil)
      end
    when "copy"
      # Python dict.copy() - a shallow copy (new Hash object, same
      # key/value pairs) so a later in-place mutation on the copy (e.g.
      # a subsequent `.update()`) doesn't alias back onto the original.
      # Found via ipr-cnrs.nftables: `nft_global_default_rules.copy()`
      # (a real role idiom - copy a default rule set before customizing
      # it per-table) rendered "... .copy is undefined" outright, since
      # plain Hash had no crinja_call entry for it at all.
      ->(_arguments : Crinja::Arguments) { Crinja::Value.new(self.dup) }
    else
      nil
    end
  end
end
