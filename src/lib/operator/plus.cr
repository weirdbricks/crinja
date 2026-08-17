class Crinja::Operator
  class Plus < Operator
    include Binary
    include Unary
    name "+"

    def value(env : Crinja, op1 : Value, op2 : Value)
      if op1.number? && op2.number?
        op1.as_number + op2.as_number
      elsif op1.raw.is_a?(Time) && op2.raw.is_a?(Crinja::TimeDelta)
        # Real Ansible's `to_datetime(...) + timedelta`-shaped idiom
        # (Python's `datetime + timedelta`) - the `TimeDelta` operand
        # only exists as the result of `-` between two Time values so
        # far (real Ansible/Jinja2 exposes no bare `timedelta()`
        # constructor), but a role can still hold onto one via a `set_
        # fact:`/loop var and add it back to a `to_datetime(...)` later.
        op1.as_time + Time::Span.new(seconds: op2.raw.as(Crinja::TimeDelta).seconds)
      elsif op1.raw.is_a?(Crinja::TimeDelta) && op2.raw.is_a?(Time)
        op2.as_time + Time::Span.new(seconds: op1.raw.as(Crinja::TimeDelta).seconds)
      elsif op1.raw.is_a?(Crinja::TimeDelta) && op2.raw.is_a?(Crinja::TimeDelta)
        Crinja::TimeDelta.new(op1.raw.as(Crinja::TimeDelta).seconds + op2.raw.as(Crinja::TimeDelta).seconds)
      elsif op1.raw.is_a?(Array)
        adding = op2.raw
        if adding.is_a?(Array)
          op1.as_a + adding
        else
          op1.as_a << Value.new adding
        end
      else
        # Same `Finalizer.stringify` fix as `~` (`src/lib/operator/
        # tilde.cr`) - `Value#to_s` bypasses `Finalizer`, mis-rendering
        # Bool/Array/Hash operands.
        Finalizer.stringify(op1.raw) + Finalizer.stringify(op2.raw)
      end
    end

    def value(env, op)
      if op.number?
        op.as_number
      else
        raise Arguments::Error.new(self, "Operators needs to be numeric")
      end
    end
  end
end
