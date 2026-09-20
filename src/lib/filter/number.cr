require "big"

module Crinja::Filter
  Crinja.filter :abs do
    if target.number?
      target.as_number.abs
    else
      raise Arguments::Error.new("abs", "Cannot render abs value for #{target.raw.class}, only accepts numbers")
    end
  end

  Crinja.filter({default: 0.0}, :float) do
    raw = target.raw
    if raw.responds_to?(:to_f?) && (result = raw.to_f?)
      return Value.new result
    end

    arguments["default"].to_f
  end

  Crinja.filter({default: 0, base: 10}, :int) do
    # Real Jinja2's `do_int` (jinja2/filters.py 3.1.6, read from the
    # installed source) is `int(value, base)` for strings and
    # `int(value)` for anything already numeric, with a float fallback
    # on failure and `default` as the last resort. Python ints are
    # arbitrary precision, so any real-world byte/inode/timestamp-scale
    # value (`ansible_facts['mounts'][n].size_available`, gigabyte/
    # terabyte-scale byte counts) parses exactly, no matter how large -
    # this filter previously narrowed through Int64 and silently
    # returned its own `default` (0) for anything beyond Int64::MAX,
    # and passed `prefix: true` to `String#to_i64?`, whose prefix
    # detection OVERRIDES the `base` argument (defaulting to base 10
    # when no 0x/0o/0b prefix is present), so `base=` was silently
    # discarded (`{{ "011"|int(base=8) }}` rendered `11` instead of
    # `9`). Parsing now goes through BigInt with explicit prefix
    # handling: an explicit 0x/0o/0b prefix still selects its own base
    # (the fork's pre-existing "prefix overwrites base" behavior, kept
    # for the existing base-16-overwrite spec), otherwise the given
    # `base` applies. Values that fit in Int64 are wrapped as plain
    # numbers so all realistic values keep full numeric semantics
    # (comparisons, arithmetic); only truly beyond-Int64 results fall
    # back to their exact decimal string so rendering never truncates.
    # The float fallback also converts through BigInt, so
    # `{{ 1e300|int }}` renders Python's exact (huge) integer instead
    # of collapsing to `default`. String-parse failures fall back to
    # `default` exactly as before; the added float fallback mirrors
    # `do_int`'s own `int(float(value))` branch, verified live against
    # real ansible-playbook: `'9'|int(base=8)` renders `9`, `'1_000'`
    # renders `1000`.
    raw = target.raw
    raw = raw.to_s if raw.is_a?(SafeString)
    result = nil
    if raw.is_a?(String)
      result = Crinja::Filter::IntParser.parse_string(raw, arguments["base"].to_i)
    elsif raw.is_a?(Float64)
      result = raw.finite? ? BigInt.new(raw) : nil
    elsif raw.responds_to?(:to_i64?)
      result = raw.to_i64?
    elsif raw.responds_to?(:to_i64)
      result = raw.to_i64
    end

    if result
      if result.is_a?(BigInt) && (result < Int64::MIN || result > Int64::MAX)
        Value.new result.to_s
      else
        Value.new result.to_i64
      end
    else
      arguments["default"].to_i
    end
  end

  class IntParser
    # Parses *str* into an arbitrary-precision integer, mirroring
    # Python's `int(str, base)` as used by real Jinja2's `do_int`:
    # surrounding whitespace and a leading sign are allowed, digits
    # must be valid for the base, and `1_000`-style underscores are
    # accepted. An explicit `0x`/`0o`/`0b` prefix selects its own base
    # (overriding *base*, the fork's pre-existing prefix-overwrites-base
    # behavior); without a prefix, *base* applies as given. Returns nil
    # when the string parses as neither integer nor float, leaving the
    # filter to fall back to its `default`.
    def self.parse_string(str : String, base : Int32) : Int64 | BigInt | Nil
      s = str.strip
      return nil if s.empty?

      sign = ""
      body = s
      if s[0] == '+' || s[0] == '-'
        sign = s[0].to_s
        body = s[1..]
      end

      parse_base = base
      if body.size >= 2 && body[0] == '0'
        case body[1]
        when 'x', 'X'
          parse_base = 16
          body = body[2..]
        when 'o', 'O'
          parse_base = 8
          body = body[2..]
        when 'b', 'B'
          parse_base = 2
          body = body[2..]
        end
      end

      begin
        BigInt.new(sign + body, parse_base)
      rescue ArgumentError
        float_fallback(s)
      end
    end

    # Real `do_int`'s failure branch: `int(float(value))`. Uses BigInt
    # so huge floats (`1e300`) keep Python's exact integer value instead
    # of overflowing; non-finite floats (`inf`, `nan`) fail like
    # Python's own `int(float("inf"))` OverflowError and return nil.
    private def self.float_fallback(s : String) : BigInt | Nil
      f = s.to_f?
      return nil if f.nil? || !f.finite?

      BigInt.new(f)
    end
  end

  Crinja.filter({binary: false}, :filesizeformat) do
    Crinja::Filter::Filesizeformat.filesize_to_human(target.to_f, arguments["binary"].truthy?)
  end

  class Filesizeformat
    def self.filesize_to_human(size, binary = false)
      if binary
        {
          "Bytes" => 1024_i64,
          "KiB"   => 1024_i64 ** 2,
          "MiB"   => 1024_i64 ** 3,
          "GiB"   => 1024_i64 ** 4,
          "TiB"   => 1024_i64 ** 5,
          "PiB"   => 1024_i64 ** 6,
        }
      else
        {
          "Bytes" => 1000_i64,
          "kB"    => 1000_i64 ** 2,
          "MB"    => 1000_i64 ** 3,
          "GB"    => 1000_i64 ** 4,
          "TB"    => 1000_i64 ** 5,
          "PB"    => 1000_i64 ** 6,
        }
      end.each do |unit, magnitude|
        if size < magnitude
          return String.build do |io|
            converted = (size / (magnitude // (binary ? 1024 : 1000)))
            if unit == "Bytes"
              io << converted.to_i
            else
              io << converted.round(1)
            end
            io << " "
            io << unit
          end
        end
      end
    end
  end

  Crinja.filter({precision: 0, method: "common", base: 10}, :round) do
    precision = arguments["precision"].to_i
    value = target.as_number
    base = arguments["base"].as_number
    base = base.to_f if precision < 0

    case arguments["method"].as_s
    when "common"
      value.round(precision, base)
    when "ceil"
      multi = base ** precision
      (value * multi).ceil.to_f / multi
    when "floor"
      multi = base ** precision
      (value * multi).floor.to_f / multi
    else
      raise Arguments::Error.new("method", "argument `method` for filter `round` must be 'common', 'ceil' or 'floor'")
    end
  end
end
