class Crinja::Operator
  class And < Operator
    include Logic
    name "and"

    # Real Jinja2/Python's `and`/`or` are short-circuit VALUE operators:
    # `x and y` evaluates to `x` if `x` is falsy, else to `y` - whichever
    # operand actually decided the outcome, not a boolean. Collapsing to
    # `Value.new(bool)` discards the real operand entirely (`'' or
    # 'fallback'` would render the literal text "True" instead of
    # "fallback"), breaking the single most common Ansible/Jinja2
    # defaulting idiom.
    def value(env : Crinja, op1 : Value, &op2 : -> Value) : Value
      op1.truthy? ? op2.call : op1
    end
  end

  class Or < Operator
    include Logic
    name "or"

    def value(env : Crinja, op1 : Value, &op2 : -> Value) : Value
      op1.truthy? ? op1 : op2.call
    end
  end

  class Not < Operator
    include Unary
    name "not"

    def value(env : Crinja, op : Value) : Value
      Value.new !op.truthy?
    end
  end
end
