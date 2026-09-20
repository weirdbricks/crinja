module Crinja::Filter
  Crinja.filter({default_value: "", boolean: false}, :default) do
    default_value = arguments["default_value"]

    value = target.raw
    if target.undefined? || value.nil? || (arguments["boolean"].truthy? && !target.truthy?)
      default_value.raw
    else
      value
    end
  end
  Crinja::Filter::Library.alias :d, :default

  Crinja.filter({name: UNDEFINED}, :attr) do
    Resolver.resolve_getattr(arguments["name"], target)
  end

  Crinja.filter({verbose: false}, :pprint) do
    verbose = arguments["verbose"].truthy?

    Crinja::PythonPprint.pformat(target)
  end
end

# Formerly the pprint filter's engine (a `::PrettyPrint` subclass); kept
# because `Value#pretty_print` and `Context#pretty_print` are typed
# against it. The pprint filter itself now goes through
# `Crinja::PythonPprint` instead.
# :nodoc:
class Crinja::PrettyPrint < ::PrettyPrint
  property verbose : Bool

  def initialize(output : IO, maxwidth = 79, newline = "\n", indent = 0, @verbose = false)
    super(output, maxwidth, newline, indent)
  end
end

# Python's `pprint.pformat` - the function real Jinja2's `do_pprint`
# delegates to (jinja2/filters.py: `pprint.pformat(value, verbose=verbose)`,
# with pprint's default arguments: `indent=1, width=80, sort_dicts=True,
# compact=False`) - as adjusted by real ansible-core 2.19's live behavior
# (verified against ansible-playbook 2.19.11 through a pty):
#
# - Strings take pprint's full string path: Python `repr()` quoting
#   (single quotes preferred; double quotes only when the string contains
#   a single quote but no double quote; apostrophes escaped when both are
#   present), and a repr wider than 80 columns is chunked on whitespace
#   runs and wrapped in parens (adjacent string literals) at top level.
#   Verified live: `{{ longs | pprint }}` renders
#   `('hello world ... '
#    'hello world ...')` in real ansible.
# - Lists and dicts render as a SINGLE-LINE plain Python repr in
#   insertion order, even when far wider than 80 columns: ansible passes
#   its own lazy-container types into pprint, whose repr is not
#   `list.__repr__`/`dict.__repr__`, so pprint's list/dict dispatchers
#   (which wrap overflow and, for dicts, sort keys via `sort_dicts=True`)
#   never engage. Verified live: a 46-element list and an overflowing
#   dict both render on one line, and `{{ {'zebra': 1, 'apple': 2} |
#   pprint }}` renders insertion order, NOT vanilla pprint's sorted
#   `{'apple': 2, 'zebra': 1}`. (Vanilla Jinja2/CPython would sort and
#   wrap; this fork follows real ansible per repo precedent.)
#
# The previous implementation delegated to Crystal's `PrettyPrint`, which
# renders Crystal-style output (`"foo"`, `true`, `nil`, `{'k' => "v"}`)
# where real Jinja2 renders Python repr style (`'foo'`, `True`, `None`,
# `{'k': 'v'}`).
#
# Recursion is guarded with an ancestor set of list/dict/tuple object
# ids; a recursive reference renders as `<Recursion on list with id=...>`
# (Python's plain container repr would die with RecursionError there).
#
# Known approximation: Python's `str.isprintable()` treats the Unicode
# categories Cf, Cs, Co and Cn as non-printable, but Crystal's
# `Char#printable?` only covers control characters and whitespace - a
# string containing e.g. a soft hyphen (U+00AD) reprs differently.
module Crinja::PythonPprint
  WIDTH = 80

  def self.pformat(value : Crinja::Value) : String
    String.build do |io|
      format(value, io, 0, 0, Set(UInt64).new, 0)
    end
  end

  # `PrettyPrinter._format` restricted to the dispatchers real ansible's
  # lazy containers leave active: only strings ever get pprint's wrapping
  # treatment; every other value renders as its single-line repr.
  def self.format(value : Crinja::Value, io, indent : Int32, allowance : Int32, context : Set(UInt64), level : Int32) : Nil
    rep = repr(value, context, level)
    raw = value.raw

    if raw.is_a?(String | SafeString) && rep.size > WIDTH - indent - allowance
      pprint_str(raw.to_s, rep, io, indent, allowance, level + 1)
    else
      io << rep
    end
  end

  # `PrettyPrinter._safe_repr`: the compact repr used both as the
  # "does it fit" candidate and for nested items of a container.
  def self.repr(value : Crinja::Value, context : Set(UInt64), level : Int32) : String
    raw = value.raw
    case raw
    when Nil
      "None"
    when Bool
      raw ? "True" : "False"
    when Number
      format_number(raw)
    when String | SafeString
      python_repr(raw.to_s)
    when Crinja::Dictionary
      repr_container(raw, context, "{}") do
        components = raw.map do |key, ent|
          "#{repr(key, context, level + 1)}: #{repr(ent, context, level + 1)}"
        end
        "{#{components.join(", ")}}"
      end
    when Array(Crinja::Value)
      repr_container(raw, context, "[]") do
        components = raw.map { |item| repr(item, context, level + 1) }
        "[#{components.join(", ")}]"
      end
    when Crinja::Tuple
      repr_container(raw, context, "()") do
        components = raw.map { |item| repr(item, context, level + 1) }
        if raw.size == 1
          "(#{components.first},)"
        else
          "(#{components.join(", ")})"
        end
      end
    when Undefined
      # jinja2.runtime.Undefined.__repr__ renders "Undefined".
      "Undefined"
    else
      raw.to_s
    end
  end

  private def self.repr_container(raw, context : Set(UInt64), empty : String, &) : String
    return empty if raw.empty?
    return recursion_repr(raw) if context.includes?(raw.object_id)

    context << raw.object_id
    rep = yield
    context.delete(raw.object_id)
    rep
  end

  private def self.recursion_repr(raw) : String
    type = case raw
           when Array then "list"
           when Crinja::Dictionary then "dict"
           else "tuple"
           end
    "<Recursion on #{type} with id=#{raw.object_id}>"
  end

  # `_pprint_str`: a long string is split into repr chunks on line
  # boundaries and whitespace runs; at the top level the chunks are
  # wrapped in parens (adjacent string literal concatenation).
  private def self.pprint_str(str : String, rep : String, io, indent, allowance, level) : Nil
    if str.empty?
      io << rep
      return
    end

    chunks = [] of String
    lines = split_lines_keepends(str)
    ind = indent
    allw = allowance
    if level == 1
      ind += 1
      allw += 1
    end
    max_width1 = max_width = WIDTH - ind

    lines.each_with_index do |line, i|
      line_rep = python_repr(line)
      width1 = max_width1
      width1 -= allw if i == lines.size - 1

      if line_rep.size <= width1
        chunks << line_rep
      else
        parts = line.scan(/\S*\s*/).map(&.[0])
        parts.pop if parts.last.empty?
        width2 = max_width
        current = ""
        parts.each_with_index do |part, j|
          candidate = current + part
          width2 -= allw if j == parts.size - 1 && i == lines.size - 1
          if python_repr(candidate).size > width2
            chunks << python_repr(current) unless current.empty?
            current = part
          else
            current = candidate
          end
        end
        chunks << python_repr(current) unless current.empty?
      end
    end

    if chunks.size == 1
      io << rep
      return
    end

    io << "(" if level == 1
    chunks.each_with_index do |chunk, i|
      io << "\n" << (" " * ind) if i > 0
      io << chunk
    end
    io << ")" if level == 1
  end

  # Python's `str.splitlines(keepends=True)` (only the \n, \r\n and \r
  # boundaries, which cover realistic template data).
  private def self.split_lines_keepends(str : String) : Array(String)
    lines = [] of String
    bytes = str.bytes
    start = 0
    i = 0
    while i < bytes.size
      case bytes[i]
      when 0x0A
        lines << str.byte_slice(start, i - start + 1)
        start = i += 1
      when 0x0D
        len = (i + 1 < bytes.size && bytes[i + 1] == 0x0A) ? 2 : 1
        lines << str.byte_slice(start, i - start + len)
        start = i += len
      else
        i += 1
      end
    end
    lines << str.byte_slice(start) if start < bytes.size
    lines
  end

  # Python's `repr()` for strings: single-quote preferred; double quotes
  # only if the string contains a single quote but no double quote; with
  # both present, single quotes win and the apostrophes get escaped.
  # Backslash, \n, \r, \t, the chosen quote and non-printable characters
  # are escaped the standard Python way (`\xHH`, `\uHHHH`, `\UHHHHHHHH`).
  def self.python_repr(str : String) : String
    quote = str.includes?('\'') && !str.includes?('"') ? '"' : '\''

    String.build do |io|
      io << quote
      str.each_char do |char|
        case char
        when '\\'             then io << "\\\\"
        when quote             then io << "\\" << char
        when '\n'             then io << "\\n"
        when '\r'             then io << "\\r"
        when '\t'             then io << "\\t"
        else
          io << escape_non_printable(char) unless char.printable?
          io << char if char.printable?
        end
      end
      io << quote
    end
  end

  private def self.escape_non_printable(char : Char) : String
    code = char.ord
    if code < 0x100
      "\\x#{code.to_s(16).rjust(2, '0')}"
    elsif code < 0x10000
      "\\u#{code.to_s(16).rjust(4, '0')}"
    else
      "\\U#{code.to_s(16).rjust(8, '0')}"
    end
  end

  # Python's `repr()` for floats: scientific notation only outside
  # [1e-4, 1e16), zero-padded two-digit exponents with an explicit sign,
  # no trailing ".0" in the mantissa, and `inf`/`nan` spelled lowercase.
  private def self.format_number(raw : Number) : String
    if raw.is_a?(Float64)
      format_float(raw)
    else
      raw.to_s
    end
  end

  private def self.format_float(f : Float64) : String
    if f.nan?
      return "nan"
    elsif inf = f.infinite?
      return inf > 0 ? "inf" : "-inf"
    end

    str = f.to_s
    e_pos = str.index('e')
    return str if e_pos.nil?

    sign = str[0] == '-' ? "-" : ""
    mantissa = str[0...e_pos].lstrip('-')
    exp_str = str[(e_pos + 1)..]
    exp_negative = exp_str[0] == '-'
    exponent = exp_str.to_i
    digits = mantissa.delete('.')

    if exponent < -4 || exponent >= 16
      digits = digits.rstrip('0')
      mant = digits.size == 1 ? digits : "#{digits[0]}.#{digits[1..]}"
      "#{sign}#{mant}e#{exp_negative ? '-' : '+'}#{exponent.abs.to_s.rjust(2, '0')}"
    elsif exponent >= 0
      int_part = digits[0, {exponent + 1, digits.size}.min].ljust(exponent + 1, '0')
      frac_part = digits.size > exponent + 1 ? digits[(exponent + 1)..].to_s : ""
      "#{sign}#{int_part}.#{frac_part.rstrip('0').empty? ? "0" : frac_part.rstrip('0')}"
    else
      "#{sign}0.#{"0" * (-exponent - 1)}#{digits.rstrip('0')}"
    end
  end
end
