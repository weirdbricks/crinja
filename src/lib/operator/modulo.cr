class Crinja::Operator
  class Modulo < Operator
    include Binary
    name "%"

    def value(env : Crinja, op1, op2)
      if op1.arith_number? && op2.arith_number?
        divisor = op2.as_arith_number.to_i
        if divisor == 0
          raise Crinja::Error.new("integer modulo by zero")
        end
        op1.as_arith_number.to_i % divisor
      else
        raise Arguments::Error.new(self, "Both operators need to be numeric")
      end
    end
  end
end
