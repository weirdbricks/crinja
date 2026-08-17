class Crinja::Operator
  class Multiply < Operator
    include Binary
    name "*"

    def value(env : Crinja, op1, op2)
      if op1.number? && op2.number?
        op1.as_number * op2.as_number
      elsif op1.raw.is_a?(String) && op2.raw.is_a?(Float64 | Int32)
        op1.raw.as(String) * op2.to_i
      elsif op1.raw.is_a?(Crinja::TimeDelta) && op2.number?
        # Python's `timedelta * n` scales the span - real Ansible has no
        # bare `timedelta()` constructor exposed to Jinja2, but a role
        # can scale one already produced by `to_datetime(...) -
        # to_datetime(...)`.
        Crinja::TimeDelta.new((op1.raw.as(Crinja::TimeDelta).seconds * op2.as_number.to_f64).to_i64)
      elsif op1.number? && op2.raw.is_a?(Crinja::TimeDelta)
        Crinja::TimeDelta.new((op2.raw.as(Crinja::TimeDelta).seconds * op1.as_number.to_f64).to_i64)
      else
        raise Arguments::Error.new(self, "Both operators need to be numeric")
      end
    end
  end
end
