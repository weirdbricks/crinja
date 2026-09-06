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
    when "replace"
      # Python's str.replace(old, new[, count]) - replaces every
      # occurrence of old with new (or only the first `count` when
      # given). Found in the same template as .find() above
      # (jdauphant.nginx's nginx.conf.j2): `v.replace(";", ";\n
      # ").replace(" {", " {\n      ")...`, a chained rewrite of a
      # config line's punctuation into indented multi-line form.
      ->(arguments : Crinja::Arguments) do
        old = arguments.varargs[0]?.try(&.raw.try(&.to_s)) || ""
        new = arguments.varargs[1]?.try(&.raw.try(&.to_s)) || ""
        count = arguments.varargs[2]?.try(&.raw.try(&.to_s).try(&.to_i?))
        result = if count
                   s = self
                   count.times { s = s.sub(old, new) }
                   s
                 else
                   self.gsub(old, new)
                 end
        Crinja::Value.new(result)
      end
    when "find"
      # Python's str.find(sub[, start]) - the index of the first
      # occurrence of sub at or after start, or -1 if not found. Real
      # Ansible template idiom for "does this string contain a
      # substring" (`{% if v.find('\n') != -1 %}`) - found via
      # jdauphant.nginx's own nginx.conf.j2, checking a config line for
      # an embedded newline before deciding how to quote it.
      ->(arguments : Crinja::Arguments) do
        sub = arguments.varargs[0]?.try(&.raw.try(&.to_s)) || ""
        start = arguments.varargs[1]?.try(&.raw.try(&.to_s).try(&.to_i?)) || 0
        idx = self.index(sub, start)
        Crinja::Value.new((idx || -1).to_i64)
      end
    else
      nil
    end
  end
end
