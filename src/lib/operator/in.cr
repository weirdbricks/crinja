class Crinja::Operator
  # Containment check shared by `In`/`NotIn` - checks Hash key membership,
  # String substring, and falls back to element-equality search over any
  # other iterable (real Jinja2's own `in` behaves the same way: dict ->
  # key check, string -> substring check, anything else -> iteration).
  def self.contains?(container : Crinja::Value, item : Crinja::Value) : Bool
    case raw = container.raw
    when Hash
      raw.has_key?(item)
    when String
      needle = item.raw.is_a?(String) ? item.raw.as(String) : item.to_s
      raw.includes?(needle)
    else
      container.each.any? { |value| value == item }
    end
  end

  class In < Operator
    include Binary
    name "in"

    def value(env : Crinja, op1 : Value, op2 : Value)
      Value.new Operator.contains?(op2, op1)
    end
  end

  class NotIn < Operator
    include Binary
    name "not in"

    def value(env : Crinja, op1 : Value, op2 : Value)
      Value.new !Operator.contains?(op2, op1)
    end
  end
end
