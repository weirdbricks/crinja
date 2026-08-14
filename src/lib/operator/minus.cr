class Crinja::Operator
  class Minus < Operator
    include Binary
    include Unary
    name "-"

    def value(env, op1, op2)
      if op1.number? && op2.number?
        op1.as_number - op2.as_number
      elsif op1.time? && op2.time?
        # Real Ansible's `to_datetime(...) - to_datetime(...)`: two Time
        # values subtract to a timedelta whose `.days`/`.seconds`/
        # `.total_seconds()` a role can then read (dev-sec os_hardening's
        # password-ageing day-count assert).
        Crinja::TimeDelta.new((op1.as_time - op2.as_time).total_seconds.to_i64)
      else
        raise Arguments::Error.new(self, "Both operators need to be numeric")
      end
    end

    def value(env, op)
      if op.number?
        op.as_number * -1
      else
        raise Arguments::Error.new(self, "Operators needs to be numeric")
      end
    end
  end
end
