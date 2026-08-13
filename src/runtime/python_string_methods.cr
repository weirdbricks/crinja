# Real Python string methods as plain method calls -
# `.split(sep=None)`, `.startswith(prefix)`, `.endswith(suffix)`,
# `.join(iterable)` (the receiver is the SEPARATOR - reverse argument
# order from Jinja2's own `| join(sep)` FILTER). Crinja's method
# dispatch only calls through to `crinja_call` for types that implement
# it; a plain `String` doesn't by default.
class String
  def crinja_call(method : String) : Crinja::Callable::Proc?
    case method
    when "split"
      ->(arguments : Crinja::Arguments) do
        sep = arguments.varargs[0]?.try(&.raw.try(&.to_s))
        parts = sep.nil? || sep.empty? ? self.split : self.split(sep)
        Crinja::Value.new(parts.map { |part| Crinja::Value.new(part) })
      end
    when "startswith"
      ->(arguments : Crinja::Arguments) do
        prefix = arguments.varargs[0]?.try(&.raw.try(&.to_s)) || ""
        Crinja::Value.new(self.starts_with?(prefix))
      end
    when "endswith"
      ->(arguments : Crinja::Arguments) do
        suffix = arguments.varargs[0]?.try(&.raw.try(&.to_s)) || ""
        Crinja::Value.new(self.ends_with?(suffix))
      end
    when "join"
      ->(arguments : Crinja::Arguments) do
        iterable = arguments.varargs[0]? || Crinja::Value.new([] of Crinja::Value)
        Crinja::Value.new(iterable.each.map(&.to_s).to_a.join(self))
      end
    else
      nil
    end
  end
end
