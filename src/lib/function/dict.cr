Crinja.function(:dict) do
  # Real Python's `dict` builtin accepts a single positional argument that
  # is a mapping *or* an iterable of [key, value] pairs (each pair a
  # 2-item list/tuple), followed by optional keyword arguments that merge
  # on top. The original here read only `arguments.kwargs`, silently
  # ignoring any positional argument - which meant `dict([['a', 1],
  # ['b', 2]])` (real Ansible's exposed-Python-`dict` form, used e.g. by
  # prometheus.prometheus's _common role to build a checksum-filename
  # lookup) succeeded with an EMPTY dict instead of raising, an unsafe-to-
  # fall-back-from silent-wrong-value. Now handles the single-positional
  # form precisely, raising a clean `Arguments::Error` for anything it
  # can't build a dict from.
  result = Crinja::Dictionary.new

  unless arguments.varargs.empty?
    raise Crinja::Arguments::Error.new(
      "dict",
      "expected at most 1 positional argument, got #{arguments.varargs.size}"
    ) if arguments.varargs.size > 1

    source = arguments.varargs[0]
    case raw = source.raw
    when Crinja::Dictionary
      raw.each { |key, value| result[key] = value }
    when Array(Crinja::Value), Crinja::Tuple
      raw.each do |pair_value|
        pair = pair_key_value(pair_value)
        result[pair[0]] = pair[1]
      end
    else
      raise Crinja::Arguments::Error.new(
        "dict",
        "argument must be a mapping or an iterable of [key, value] pairs, got #{source.inspect}"
      )
    end
  end

  arguments.kwargs.each { |key, value| result[Crinja::Value.new(key)] = value }
  result
end

private def pair_key_value(pair_value : Crinja::Value) : ::Tuple(Crinja::Value, Crinja::Value)
  case raw = pair_value.raw
  when Array(Crinja::Value)
    if raw.size == 2
      {raw[0], raw[1]}
    else
      raise Crinja::Arguments::Error.new(
        "dict",
        "dictionary update sequence element has length #{raw.size}, 2 is required"
      )
    end
  when Crinja::Tuple
    if raw.size == 2
      {raw[0], raw[1]}
    else
      raise Crinja::Arguments::Error.new(
        "dict",
        "dictionary update sequence element has length #{raw.size}, 2 is required"
      )
    end
  else
    raise Crinja::Arguments::Error.new(
      "dict",
      "cannot convert dictionary update sequence element #{raw.inspect} to a sequence"
    )
  end
end
