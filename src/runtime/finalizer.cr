require "html"

# This class is used to process the result of a variable expression before it is output.
# It tries to convert values to a meaningful string represenation similar to what `Object#to_s` does
# but with a few adjustments compared to Crystal standard `to_s` methods.
struct Crinja::Finalizer
  def self.stringify(raw, escape = false, in_struct = false)
    String.build do |io|
      stringify(io, raw, escape, in_struct)
    end
  end

  def self.stringify(io : IO, raw, escape = false, in_struct = false)
    new(io, escape, in_struct).stringify(raw)
  end

  # :nodoc:
  protected def initialize(@io : IO, @escape = false, @inside_struct = false)
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
  # `{'k': [1, 2]}`, `zip`/`dictsort` results render as nested lists);
  # only an explicit `| string` keeps the Python `str(tuple)` parens
  # repr, and that filter goes through Tuple#to_s, not this method.
  # Previously rendered `(a, b)` parens, so a `{{ d1 | dictsort }}`
  # interpolated into text produced paren-reprs where real Ansible
  # produces bracketed lists (found via krikri-playbook's round-306
  # follow-up verification).
  protected def stringify(array : Crinja::Tuple)
    @inside_struct = true
    @io << "["
    array.join(@io, ", ") { |item| stringify(item) }
    @io << "]"
  end

  private def quote(&)
    quotes = @inside_struct
    @io << '\'' if quotes
    yield
    @io << '\'' if quotes
  end
end
