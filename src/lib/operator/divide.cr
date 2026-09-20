class Crinja::Operator
  class Divide < Operator
    include Binary
    name "/"

    def value(env : Crinja, op1, op2)
      if op1.arith_number? && op2.arith_number?
        op1.as_arith_number.to_f / op2.as_arith_number.to_f
      else
        raise Arguments::Error.new(self, "Both operators need to be numeric")
      end
    end
  end
end
