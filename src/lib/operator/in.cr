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
      if item.raw.is_a?(Undefined)
        # Real Jinja2 evaluates `x in y` as `y.__contains__(x)`, and a
        # Python str.__contains__ requires its argument to itself be a
        # str - an Undefined marker reaches it intact (Jinja2 defers the
        # undefined raise to force time) and Python hard-fails with its
        # own TypeError. Crinja used to stringify the marker to "" (a
        # substring of everything) and wrongly return true in the
        # default lenient mode, and to surface the generic "X is
        # undefined" UndefinedError under StrictUndefined. Both now
        # raise the TypeError shape real Python raises. Deliberately
        # scoped to the STRING container only: `undefined in [..]`
        # compares by equality and returns False in real Python, and an
        # undefined container follows the iterable path below unchanged.
        raise Crinja::TypeError.new(
          "'in <string>' requires string as left operand, not UndefinedMarker"
        )
      end
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
