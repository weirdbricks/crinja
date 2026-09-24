class Crinja::Operator
  class Modulo < Operator
    include Binary
    name "%"

    def value(env : Crinja, op1, op2)
      # Python (and therefore Jinja2, whose operators the sandbox
      # delegates to) overloads `%` by the LEFT operand's type: a str
      # left-hand-side is old-style string formatting (`'%d' % n`,
      # `'%s-%s' % (a, b)`, `'%(k)s' % mapping`), a numeric one is
      # modulo. Crinja only modelled the numeric case, so `'%d' % port`
      # - the idiom rolehippie.coredns uses in its `service.j2`
      # (`' -dns.port=%d' % (coredns_listen_port)`) - raised "Both
      # operators need to be numeric".
      if op1.raw.is_a?(String)
        Crinja::PercentFormat.format(op1.raw.as(String), op2)
      elsif op1.arith_number? && op2.arith_number?
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

# Python's printf-style `%`-formatting (`fmt % args`), for the subset real
# Jinja2/Ansible templates reach: the standard conversions (d/i/u, o, x/X,
# e/E, f/F, g/G, c, r, a, s), the `#0-+ ` flags, numeric field width and
# `.precision`, `%%`, and both the positional `'%s' % (a, b)` and
# mapping-key `'%(name)s' % {...}` forms. Numeric conversions are built up
# into a Crystal `sprintf` spec (Crystal's formatter is C-compatible) once
# the operand is coerced to the exact Int64/Float64 Python would accept;
# `%s`/`%r`/`%c` and the field-width/zero-pad rules are applied by hand so
# a Bool operand renders Python-style (`True`) via the fork's `Finalizer`
# instead of Crystal's `true`.
module Crinja::PercentFormat
  private class FormatError < Crinja::Error
  end

  # One parsed conversion.
  private struct Spec
    property key : String? = nil
    property flags = ""    # subset of "#0-+ "
    property width : Int32? = nil
    property precision : Int32? = nil
    property conv = '\0'

    def alt?;        flags.includes?('#'); end
    def zero?;       flags.includes?('0'); end
    def left?;       flags.includes?('-'); end
    def plus?;       flags.includes?('+'); end
    def space?;      flags.includes?(' ') && !plus?; end
  end

  def self.format(fmt : String, args : Value) : String
    specs = scan_specs(fmt)

    named = specs.any? { |s| !s.key.nil? }
    seq = [] of Value
    dict = nil.as(Hash(String, Value)?)

    if named
      dict = as_mapping(args)
    else
      seq = as_sequence(args, specs.size)
      if specs.size != seq.size
        raise FormatError.new(specs.size > seq.size ? "not enough arguments for format string" : "not all arguments converted during string formatting")
      end
    end

    io = IO::Memory.new
    si = 0
    i = 0
    len = fmt.size
    while i < len
      unless fmt[i] == '%'
        io << fmt[i]
        i += 1
        next
      end
      if i + 1 < len && fmt[i + 1] == '%'
        io << '%'
        i += 2
        next
      end
      spec = specs[si]
      value =
        if spec.key
          unless (m = dict); raise FormatError.new("format requires a mapping"); end
          m[spec.key.not_nil!]? || raise(FormatError.new("format requires a mapping"))
        else
          seq[si]
        end
      render(io, spec, value)
      si += 1
      i = spec_end(fmt, i)
    end
    io.to_s
  end

  # --- scanning / index bookkeeping ------------------------------------

  # The index one past the conversion that starts at the '%' at `start`.
  private def self.spec_end(fmt : String, start : Int) : Int
    i = start + 1
    len = fmt.size
    if i < len && fmt[i] == '('
      close = fmt.index(')', i)
      i = close + 1 if close
    end
    while i < len && "#0-+ ".includes?(fmt[i])
      i += 1
    end
    while i < len && fmt[i].number?
      i += 1
    end
    if i < len && fmt[i] == '.'
      i += 1
      while i < len && fmt[i].number?
        i += 1
      end
    end
    i += 1 if i < len && "hlL".includes?(fmt[i])
    i + 1 # past the conversion char
  end

  private def self.scan_specs(fmt : String) : Array(Spec)
    specs = [] of Spec
    i = 0
    len = fmt.size
    while i < len
      if fmt[i] != '%'
        i += 1
        next
      end
      if i + 1 < len && fmt[i + 1] == '%'
        i += 2
        next
      end
      spec = Spec.new
      i += 1
      if i < len && fmt[i] == '('
        close = fmt.index(')', i) || raise(FormatError.new("missing ')' in format"))
        spec.key = fmt[i + 1, close - i - 1]
        i = close + 1
      end
      fstart = i
      while i < len && "#0-+ ".includes?(fmt[i])
        i += 1
      end
      spec.flags = fmt[fstart, i - fstart]
      wstart = i
      while i < len && fmt[i].number?
        i += 1
      end
      spec.width = fmt[wstart, i - wstart].to_i32 if i > wstart
      if i < len && fmt[i] == '.'
        i += 1
        pstart = i
        while i < len && fmt[i].number?
          i += 1
        end
        spec.precision = fmt[pstart, i - pstart].to_i32 if i > pstart
      end
      i += 1 if i < len && "hlL".includes?(fmt[i])
      raise FormatError.new("incomplete format") if i >= len
      spec.conv = fmt[i]
      i += 1
      specs << spec
    end
    specs
  end

  # --- argument shaping -------------------------------------------------

  private def self.as_sequence(args : Value, spec_count : Int32) : Array(Value)
    arr = args.raw.as?(Array(Value))
    if arr
      arr
    elsif spec_count == 1
      [args] of Value
    else
      # A non-sequence operand for a multi-conversion format is a single
      # argument Python would reject; surface it as an arity error.
      [] of Value
    end
  end

  private def self.as_mapping(args : Value) : Hash(String, Value)
    dict = Hash(String, Value).new
    case raw = args.raw
    when Hash
      raw.each { |k, v| dict[k.to_s] = v.is_a?(Value) ? v : Value.new(v) }
    when Dictionary
      raw.each { |k, v| dict[k.to_s] = v.is_a?(Value) ? v : Value.new(v) }
    else
      raise FormatError.new("format requires a mapping")
    end
    dict
  end

  # --- rendering --------------------------------------------------------

  private def self.render(io : IO, spec : Spec, value : Value)
    text =
      case spec.conv
      when 's' then string_of(value, spec)
      when 'r', 'a' then py_repr(value.raw)
      when 'c' then char_of(value)
      when 'd', 'i', 'u' then int_of(value, 10, spec)
      when 'x', 'X' then int_of(value, 16, spec)
      when 'o' then int_of(value, 8, spec)
      when 'e', 'E', 'f', 'F', 'g', 'G' then float_of(value, spec)
      else raise FormatError.new("unsupported format character '#{spec.conv}'")
      end
    pad(io, text, spec)
  end

  # Builds a Crystal `sprintf` spec (C-compatible) after coercing the
  # operand to the exact type Python requires, so `'%05d'` / `'%8.3f'` /
  # `%x` render identically without re-implementing the width/padding math.
  private def self.int_of(value : Value, base : Int32, spec : Spec) : String
    n = py_int(value)
    neg = n < 0
    abs = n.abs
    digits = abs.to_s(base)
    digits = digits.upcase if spec.conv == 'X'
    prefix = if spec.alt? && base != 10 && abs != 0
               base == 16 ? (spec.conv == 'X' ? "0X" : "0x") : "0"
             else
               ""
             end
    sign = neg ? "-" : (spec.plus? ? "+" : (spec.space? ? " " : ""))
    # Zero-pad inserts between sign and (0x + digits); sprintf on the
    # assembled body keeps the sign/prefix left of the fill.
    body = sign + prefix + digits
    # Let sprintf apply width when zero-padding (it understands %0<width>);
    # otherwise return the sign/prefix/body and let the shared pad() right-
    # or left-align it.
    body
  end

  private def self.float_of(value : Value, spec : Spec) : String
    f = py_float(value)
    conv = spec.conv
    p = spec.precision
    body =
      case conv
      when 'f', 'F' then sprintf("%.#{p || 6}f", f)
      when 'e', 'E' then sprintf("%.#{p || 6}e", f)
      when 'g', 'G' then (p.nil? ? sprintf("%g", f) : sprintf("%.#{p}g", f))
      else               f.to_s
      end
    body = body.upcase if conv == 'E' || conv == 'G'
    if f >= 0 && spec.plus? && !body.starts_with?("+") && !body.starts_with?("-")
      body = "+" + body
    elsif f >= 0 && spec.space? && !body.starts_with?("+") && !body.starts_with?("-")
      body = " " + body
    end
    body
  end

  private def self.string_of(value : Value, spec : Spec) : String
    s = Finalizer.stringify(value.raw, python_str: true)
    if (p = spec.precision) && p < s.size
      s[0, p]
    else
      s
    end
  end

  private def self.char_of(value : Value) : String
    case raw = value.raw
    when Int64, Int32 then raw.to_i32.chr.to_s
    when String       then raw
    else raise FormatError.new("%c format: an integer or char is required")
    end
  end

  private def self.py_int(value : Value) : Int64
    case raw = value.raw
    when Int64   then raw
    when Int32   then raw.to_i64
    when Float64 then raw.to_i64
    when Bool    then raw ? 1_i64 : 0_i64
    else raise FormatError.new("%d format: a real number is required, not #{type_name(raw)}")
    end
  end

  private def self.py_float(value : Value) : Float64
    case raw = value.raw
    when Float64 then raw
    when Int64   then raw.to_f
    when Int32   then raw.to_f
    when Bool    then raw ? 1.0 : 0.0
    else raise FormatError.new("%f format: a real number is required, not #{type_name(raw)}")
    end
  end

  private def self.type_name(raw) : String
    case raw
    when String                 then "str"
    when Array                  then "list"
    when Hash, Dictionary       then "dict"
    when Bool                   then "bool"
    when Nil                    then "NoneType"
    when Crinja::Undefined      then "Undefined"
    else                             "object"
    end
  end

  private def self.py_repr(raw) : String
    case raw
    when String  then "'" + raw.gsub("\\", "\\\\").gsub("'", "\\'") + "'"
    when Bool    then raw ? "True" : "False"
    when Int64   then raw.to_s
    when Int32   then raw.to_s
    when Float64 then raw.to_s
    when Nil     then "None"
    when Array(Value) then "[" + raw.map { |v| py_repr(v.raw) }.join(", ") + "]"
    when Array        then "[" + raw.map { |v| py_repr(v.is_a?(Value) ? v.raw : v) }.join(", ") + "]"
    when Hash, Dictionary
      items = [] of String
      raw.each { |k, v| items << "'#{k}': #{py_repr(v.is_a?(Value) ? v.raw : v)}" }
      "{" + items.join(", ") + "}"
    else Finalizer.stringify(raw, python_str: true)
    end
  end

  # Field width / alignment for the non-sprintf branches (`%s`, `%r`, `%c`,
  # and the sign/prefix-composed ints/floats). `%d` zero-fill on a plain
  # signed number is the only case needing the sign-before-zeros special
  # case, which `pad` handles via the `body` it's given.
  private def self.pad(io : IO, body : String, spec : Spec)
    width = spec.width
    return io << body if width.nil? || body.size >= width
    fill = width - body.size
    if spec.zero? && !spec.left?
      lead = ""
      rest = body
      if (c = body[0]?) && (c == '-' || c == '+' || c == ' ')
        lead = c.to_s
        rest = body[1..]
      end
      # `0x`/`0` base prefix stays with the digits, after the zeros.
      if lead.empty? && (body.starts_with?("0x") || body.starts_with?("0X")) && body[2..]?.try(&.chars.all? { |ch| ch.hex? })
        io << body[0, 2] << "0" * fill << body[2..]
      else
        io << lead << "0" * fill << rest
      end
    elsif spec.left?
      io << body << " " * fill
    else
      io << " " * fill << body
    end
  end
end
