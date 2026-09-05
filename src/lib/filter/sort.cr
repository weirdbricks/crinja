module Crinja::Filter
  Crinja.filter({
    case_sensitive: false,
    by:             "key",
  }, :dictsort) do
    case_sensitive = arguments["case_sensitive"].truthy?

    # Real dictsort returns (key, value) pairs sorted by key (or by
    # value with `by=value`). Since crystal-play-0.9.25 Value#to_a
    # yields a dict's KEYS only (Python semantics), the pairs are built
    # here explicitly from the raw Hash instead of relying on to_a's
    # old tuple-by-default behavior.
    array = if (hash = target.raw).is_a?(Hash)
              hash.map { |key, value| Value.new(Crinja::Tuple.from({key, value})) }
            else
              target.to_a
            end

    compare = ->(a : Value, b : Value) do
      if !case_sensitive && a.string? && b.string?
        a.as_s.compare(b.as_s, true)
      else
        a <=> b
      end
    end

    if arguments["by"].to_s == "value"
      array = array.sort { |key1, key2| compare.call(key1[1], key2[1]) }
    else
      array = array.sort { |key1, key2| compare.call(key1[0], key2[0]) }
    end

    array
  end

  Crinja.filter({
    reverse:        false,
    case_sensitive: false,
    attribute:      nil,
  }, :sort) do
    case_sensitive = arguments["case_sensitive"].truthy?

    # Real Jinja2's `sort` on a dict sorts and returns its KEYS
    # (Python's `sorted(dict)` semantics). Kept as an explicit
    # special case even though Value#to_a now yields keys-only for a
    # Hash (crystal-play-0.9.25): this branch also documents WHY the
    # sort must not see tuples, and keeps the behavior stable if the
    # dict ever arrives wrapped in something that responds to to_a
    # differently.
    array = if (hash = target.raw).is_a?(Hash)
              hash.keys.map { |key| Value.new(key) }
            else
              target.to_a
            end

    attribute = nil

    if arguments["attribute"].string?
      attribute = arguments["attribute"].as_s
    end

    array = array.sort do |key1, key2|
      unless attribute.nil?
        key1 = key1[attribute.not_nil!] # ameba:disable Lint/NotNil
        key2 = key2[attribute.not_nil!] # ameba:disable Lint/NotNil
      end

      if !case_sensitive && key1.string? && key2.string?
        key1.as_s.compare(key2.as_s, true)
      else
        key1 <=> key2
      end
    end

    if arguments["reverse"].truthy?
      array = array.reverse
    end

    array
  end
end
