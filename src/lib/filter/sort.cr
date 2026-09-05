module Crinja::Filter
  Crinja.filter({
    case_sensitive: false,
    by:             "key",
  }, :dictsort) do
    case_sensitive = arguments["case_sensitive"].truthy?

    array = target.to_a

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
    # (Python's `sorted(dict)` semantics), not (key, value) tuples:
    # `{% for backend in pdns_backends | sort() %}` over a dict-bound
    # variable yielded Crinja::Tuple pairs here, so `backend` was a
    # tuple and a downstream `backend | replace(...)` failed with
    # "Cast from Crinja::Tuple to (Crinja::SafeString | String)
    # failed" (found via PowerDNS.pdns in krikri-playbook's round 300
    # Kata campaign). Value#to_a still yields pairs for a Hash -
    # `dictsort` above depends on that (real dictsort returns
    # (key, value) pairs) - so only the dict case is special-cased
    # here, mapping the raw keys back into Values.
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
