class Crinja::Operator
  class Tilde < Operator
    include Binary
    name "~"

    def value(env : Crinja, op1, op2)
      # `Value#to_s` bypasses `Finalizer` (raw Crystal `to_s`, so a Bool
      # renders lowercase "true"/"false" instead of real Python/Jinja2's
      # "True"/"False", and an Array/Hash renders its raw Crystal
      # `Value<...>` wrapper inspect text instead of a real stringified
      # list/dict) - `Finalizer.stringify` is the same conversion `{{ }}`
      # output itself goes through, so `~` now matches what plain
      # concatenation-via-output would produce for each operand.
      Finalizer.stringify(op1.raw) + Finalizer.stringify(op2.raw)
    end
  end
end
