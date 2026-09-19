require "html"

# This class is used to process the result of a variable expression before it is output.
# It tries to convert values to a meaningful string represenation similar to what `Object#to_s` does
# but with a few adjustments compared to Crystal standard `to_s` methods.
struct Crinja::Finalizer
  def self.stringify(raw, escape = false, in_struct = false, python_str = false)
    String.build do |io|
      stringify(io, raw, escape, in_struct, python_str)
    end
  end

  def self.stringify(io : IO, raw, escape = false, in_struct = false, python_str = false)
    new(io, escape, in_struct, python_str).stringify(raw)
  end

  # :nodoc:
  protected def initialize(@io : IO, @escape = false, @inside_struct = false, @python_str = false)
  end

  # Convert a `Value` to string.
  protected def stringify(value : Value)
    stringify(value.raw)
  end

  # Convert any type to string.
  protected def stringify(raw)
    raw.to_s(@io)
  end

  # Convert a `nil` to `"None"` - real Python's `str(None)`, same idea
  # as the `Bool` overload just below (which matches Python's
  # `str(True)`/`str(False)`). Verified directly against real
  # `ansible-playbook`: `{{ [none, false, 0] | reject | join('|') }}`
  # (a value flowing through a FILTER, not straight to a template's own
  # top-level output) renders as `None|False|0` - capitalized Python
  # `str()`, NOT empty. This previously rendered lowercase `"none"` -
  # neither real Python's `"None"` nor (see `Renderer#render`'s own
  # `PrintStatement` visit, a few lines of a DIFFERENT, narrower
  # override) real Ansible's top-level-output-only `""` - a value that
  # never actually matched anything real. Found via `buluma.collectd`'s
  # own `collectd_conf_extra` (default `null`) rendering as a literal
  # `none` glued onto the preceding line, round170.
  protected def stringify(raw : Nil)
    @io << "None"
  end

  # Real Jinja2 (via Python's `str()`) renders a bare boolean as
  # "True"/"False" (capitalized) - without this overload, a `Bool` falls
  # through to the generic `raw.to_s(@io)` case above, which is
  # Crystal's own lowercase `Bool#to_s`.
  protected def stringify(raw : Bool)
    @io << (raw ? "True" : "False")
  end

  # Convert a `SafeString` to string.
  protected def stringify(safe : SafeString)
    quote { safe.to_s(@io) }
  end

  # Convert a `SafeString` to string.
  protected def stringify(string : String)
    quote do
      if @escape
        HTML.escape(string).to_s(@io)
      else
        string.to_s(@io)
      end
    end
  end

  # Real Jinja2 (via Python's `str()`/`repr()`, identical for floats in
  # Python 3) renders a bare float with fixed notation for decimal
  # exponents in [-4, 16) and scientific notation with an ALWAYS signed,
  # at-least-two-digit exponent outside it, dropping a trailing ".0"
  # mantissa in scientific form (`repr(1e16)` is '1e+16',
  # `repr(2.56e-09)` is '2.56e-09'). Crystal's own `Float64#to_s`
  # formats several of these differently (`2.56e-9`, `1.0e+16`,
  # `1.0e-5`, and goes scientific already at `1e15`), so real-Jinja2
  # numeric literals in scientific notation diverged - found via a
  # differential harness running real Jinja2 3.1.6's own upstream test
  # suite against this fork (`{{ 25.6e-10 }}` must render `2.56e-09`).
  # The digits come from Crystal's `to_s` (shortest round-trip, the same
  # digits Python's repr produces); only the notation is normalized.
  protected def stringify(raw : Float64)
    string = raw.to_s
    e_index = string.index('e')
    unless e_index
      @io << string
      return
    end

    mantissa = string[0...e_index]
    exponent = string[(e_index + 1)..].to_i

    if exponent < -4 || exponent >= 16
      mantissa = mantissa[0...-2] if mantissa.ends_with?(".0")
      sign = exponent < 0 ? "-" : "+"
      digits = exponent.abs.to_s
      digits = "0#{digits}" if digits.size < 2
      @io << mantissa << 'e' << sign << digits
      return
    end

    # Python's repr keeps fixed notation for these exponents even where
    # Crystal's `to_s` went scientific (`repr(1e15)` is
    # '1000000000000000.0', not '1.0e+15') - reconstruct it from the
    # shortest-round-trip digits.
    sign = mantissa.starts_with?('-') ? "-" : ""
    mantissa = mantissa.lstrip('-')
    int_digits = mantissa.index('.') || mantissa.size
    digits = mantissa.delete('.')
    point = int_digits + exponent
    if point <= 0
      @io << sign << "0." << ("0" * -point) << digits
    elsif point >= digits.size
      @io << sign << digits << ("0" * (point - digits.size)) << ".0"
    else
      @io << sign << digits[0...point] << '.' << digits[point..]
    end
  end

  # Convert an `Array` to string.
  protected def stringify(array : Array)
    @inside_struct = true
    @io << "["
    array.join(@io, ", ") { |item| stringify(item) }
    @io << "]"
  end

  # Convert an `Hash` to string.
  protected def stringify(hash : Hash)
    @inside_struct = true
    @io << "{"
    found_one = false
    hash.each do |key, value|
      @io << ", " if found_one
      stringify(key)
      @io << ": "
      stringify(value)
      found_one = true
    end
    @io << "}"
  end

  # Convert a `Crinja::TimeDelta` to string via its own `to_s`
  # (Python's `str(timedelta)`-style repr).
  protected def stringify(delta : Crinja::TimeDelta)
    delta.to_s(@io)
  end

  # Convert a `Crinja::Tuple` to string as a LIST - real ansible-core's
  # native-types finalization converts Python tuples to lists at every
  # rendered-output position (verified against real ansible-core 2.19.4:
  # `{{ (1, 2) }}` renders `[1, 2]`, `{{ {'k': (1, 2)} }}` renders
  # `{'k': [1, 2]}`, `zip`/`dictsort` results render as nested lists).
  # Previously rendered `(a, b)` parens unconditionally, so a
  # `{{ d1 | dictsort }}` interpolated into text produced paren-reprs
  # where real Ansible produces bracketed lists (found via
  # krikri-playbook's round-306 follow-up verification).
  #
  # The ONE exception is an explicit `| string` filter: real Ansible's
  # `| string` applies Python's own `str()` to the value BEFORE the
  # native-types conversion ever runs, so tuples keep their
  # `str(tuple)` parens repr there (`{{ d1 | dictsort | string }}`
  # renders `[('a', 1), ('b', 2)]` - brackets outer, parens inner).
  # That filter passes python_str: true, switching this method back to
  # the parens form (crystal-play-0.9.27).
  protected def stringify(array : Crinja::Tuple)
    @inside_struct = true
    @io << (@python_str ? "(" : "[")
    array.join(@io, ", ") { |item| stringify(item) }
    @io << (@python_str ? ")" : "]")
  end

  private def quote(&)
    quotes = @inside_struct
    @io << '\'' if quotes
    yield
    @io << '\'' if quotes
  end
end
