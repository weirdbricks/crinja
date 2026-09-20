module Crinja::Filter
  # Real Jinja2's `list` filter is lenient about an Undefined target
  # (`{{ some_unset_list | list }}` renders `[]`, not a crash).
  Crinja.filter :list do
    value = target.raw

    case value
    when String
      value.chars
    when Array
      value
    when Undefined
      [] of Value
    when .responds_to?(:to_a)
      target.to_a
    else
      raise TypeError.new("target for list filter cannot be converted to list")
    end
  end

  # Real Jinja2's `do_items` (added in 3.1) is forgiving ONLY for an
  # Undefined target: `if isinstance(value, Undefined): return` yields
  # nothing, so `{{ d|items|list }}` renders `[]` for an unset `d`.
  # For a Mapping it yields the `(key, value)` pairs (`.items()`), and
  # for ANY other value - list, string, scalar - it raises
  # `TypeError("Can only get item pairs from a mapping.")` (verified
  # live against Jinja2 3.1.6 and real ansible-playbook 2.19, which
  # surfaces the same message verbatim). No deprecation warning is
  # emitted in 3.1.6 for any input shape. Pairs use the same
  # `Crinja::Tuple` convention as `dictsort`. The Mapping check is a
  # plain Hash (which includes `Dictionary`), matching `isinstance(
  # value, abc.Mapping)` for the value shapes Crinja produces -
  # Crinja::Object attribute holders are the analog of plain Python
  # objects, which real Jinja2 also rejects.
  Crinja.filter(:items) do
    case raw = target.raw
    when Undefined
      [] of Value
    when Hash
      raw.map { |key, value| Value.new(Crinja::Tuple.from({key, value})) }
    else
      raise TypeError.new("Can only get item pairs from a mapping.")
    end
  end

  Crinja.filter({linecount: 2, fill_with: nil}, :batch) do
    fill_with = arguments["fill_with"]
    linecount = arguments["linecount"].to_i

    if target.sequence?
      array = [] of Value
      batch = [] of Value

      target.each do |item|
        batch << item

        if batch.size == linecount
          array << Value.new batch
          batch = [] of Value
        end
      end

      unless batch.empty?
        (linecount - batch.size).times { batch << fill_with } unless fill_with.none?
        array << Value.new batch
      end

      array
    else
      raise TypeError.new("target for batch filter must be a sequence")
    end
  end

  Crinja.filter({slices: 2, fill_with: nil}, :slice) do
    fill_with = arguments["fill_with"]
    slices = arguments["slices"].to_i

    if target.sequence?
      array = [] of Value
      slice = [] of Value

      num_full_slices = target.size % slices
      per_slice = target.size // slices
      per_full_slice = per_slice + 1

      target.each do |item|
        slice << item

        if array.size < num_full_slices ? slice.size == per_full_slice : slice.size == per_slice
          array << Value.new slice

          if array.size > num_full_slices
            slice << fill_with unless fill_with.none?
          end

          slice = [] of Value
        end
      end

      unless slice.empty?
        array << Value.new slice
      end

      array
    else
      raise TypeError.new("target for batch filter must be a list")
    end
  end

  # Lenient about an Undefined target, matching real Jinja2's `soft_str`/
  # exception-swallowing behavior for `first` on an unset value.
  Crinja.filter(:first) { target.undefined? ? UNDEFINED : target.first.raw }
  Crinja.filter(:last) { target.last.raw }
  Crinja.filter(:length) { target.size }
  Crinja::Filter::Library.alias "count", "length"

  Crinja.filter(:reverse) do
    reversable = target.raw

    if (hash = reversable).is_a?(Hash)
      # Reversed KEYS (Python's `reversed(dict)` iterates keys);
      # Hash#reverse_each would yield {key, value} tuples instead.
      hash.keys.reverse.map { |key| Value.new(key) }
    elsif reversable.responds_to?(:reverse_each)
      # FIXME: `to_a` should not be necessary, but without it creates a silent memory failure
      reversable.reverse_each.to_a
    elsif reversable.responds_to?(:reverse)
      reversable.reverse
    else
      raise TypeError.new(target, "#{target.raw.class} cannot be reversed")
    end
  end

  # Real Python `sum()` supports any `start` value `+` is defined for,
  # not just numbers - a common idiom flattens a list of lists via
  # `| sum(attribute='packages', start=[])`. Branches on `start`'s own
  # type: an array-typed `start` concatenates, everything else keeps the
  # numeric-sum behavior.
  Crinja.filter({attribute: nil, start: 0}, :sum) do
    attribute = arguments["attribute"].as_s?
    start = arguments["start"]

    if (start_array = start.raw).is_a?(Array(Value))
      result = start_array.dup
      target.each do |item|
        item = Resolver.resolve_dig(attribute, item) unless attribute.nil?
        raw = item.raw
        if raw.is_a?(Array(Value))
          result.concat(raw)
        else
          result << item
        end
      end
      result
    else
      sum = start.as_number

      target.each do |value|
        unless attribute.nil?
          value = Resolver.resolve_dig(attribute, value)
        end

        raw = value.raw
        if raw.is_a?(Crinja::Number)
          sum += raw
        else
          raise TypeError.new("cannot add #{raw.class} to sum, value: #{raw.inspect}")
        end
      end

      sum
    end
  end

  # Real Jinja2's `do_random` (jinja2/filters.py 3.1.6) is just Python's
  # `random.choice(seq)`: a STRING target is treated as an iterable of its
  # own characters (`random.choice("1234567890")` returns one of "0".."9"),
  # an empty sequence hits the IndexError that `do_random` catches and
  # turns into `context.environment.undefined("No random item, sequence
  # was empty.")` - confirmed live, and confirmed against a real local
  # `ansible-playbook` 2.19 run (`ansible.builtin.random` calls
  # `r.choice(end)` on any `__iter__` target, identical character
  # semantics for strings). The previous implementation assumed the raw
  # value was already a Crystal `Indexable`, so a plain `String` (not
  # `Indexable`) raised `TypeCastError: Cast from String to Indexable(T)
  # failed` instead of returning a character - found by the differential
  # test harness against real Jinja2 3.1.6's own upstream test suite.
  # Converting through `Value#to_a` (chars for a string, items for any
  # iterable, TypeError "can't iterate over undefined" for an Undefined
  # target, matching real Jinja2's own failure on `undefined|random`)
  # restores all of that; a dict target iterating keys-only stays as the
  # fork's pre-existing behavior.
  Crinja.filter(:random) do
    choices = target.to_a
    choices.empty? ? UNDEFINED : choices.sample
  end

  Crinja.filter(:map) do
    if target.none?
      ""
    elsif arguments.is_set?("attribute")
      attribute = arguments["attribute"].raw
      target.map do |item|
        # resolve_getattr did a single-level lookup, so a dotted attribute
        # like 'stat.exists' (looped `stat:` task results, the common Ansible
        # idiom) always resolved to Undefined. Dig each segment, like the
        # sum/groupby/unique filters in this file already do.
        # .to_s to hit the String overload; the raw value is not a Value.
        Resolver.resolve_dig(attribute.to_s, item)
      end
    else
      varargs = arguments.varargs
      filter = env.filters[varargs.shift.as_s]
      # The filter callable and its declared defaults are identical for
      # every item - only the per-item target changes. Resolving the
      # callable's defaults once and sharing that hash across the per-item
      # Arguments avoids Arguments.new allocating a fresh `Variables.new`
      # for each item, which #execute_call immediately overwrote with the
      # callable's own defaults anyway.
      filter_defaults = filter.responds_to?(:defaults) ? filter.defaults : Variables.new

      target.map do |item|
        args = Arguments.new(env, varargs, arguments.kwargs, defaults: filter_defaults, target: item)
        arguments.env.execute_call(filter, args)
      end
    end
  end

  # :nodoc:
  macro select_reject_attr(func)
    varargs = arguments.varargs

    attribute = varargs.shift
    # The attribute name (and whether it is a dotted path) is the same for
    # every item - convert and classify it once, not once per item.
    attr_name = attribute.to_s
    dotted = attr_name.includes?('.')

    if varargs.size == 0
      # select based on attribute value, no filter
      target.{{ func.id }} do |item|
        # resolve_getattr only did a single-level lookup, so dotted
        # attributes like 'stat.exists' never resolved. Dig each segment,
        # like the sum/groupby/unique filters in this file already do.
        (dotted ? Resolver.resolve_dig(attr_name, item.raw) : Resolver.resolve_attribute(attr_name, item.raw)).truthy?
      end
    else
      test = env.tests[varargs.shift.as_s]
      # The test callable and its declared defaults are identical for every
      # item - only the per-item attribute value changes. Sharing the
      # callable's defaults hash across the per-item Arguments avoids
      # Arguments.new allocating a fresh `Variables.new` for each item,
      # which #execute_call immediately overwrote with the callable's own
      # defaults anyway.
      test_defaults = test.responds_to?(:defaults) ? test.defaults : Variables.new

      target.{{ func.id }} do |item|
        # Same dotted-path fix as above: resolve_getattr treated the whole
        # 'stat.exists' string as one literal key; dig each segment like
        # sum/groupby/unique in this file already do.
        resolved = dotted ? Resolver.resolve_dig(attr_name, item.raw) : Resolver.resolve_attribute(attr_name, item.raw)
        args = Arguments.new(env, varargs, arguments.kwargs, defaults: test_defaults, target: resolved)
        env.execute_call(test, args).truthy?
      end
    end
  end

  # :nodoc:
  macro select_reject(func)
    varargs = arguments.varargs

    if varargs.size == 0
      # select based on actual value, no filter
      target.{{ func.id }} &.truthy?
    else
      test = env.tests[varargs.shift.as_s]
      # Same hoist as select_reject_attr: the test callable and its
      # declared defaults are identical for every item, so share the
      # callable's defaults hash instead of Arguments.new allocating a
      # fresh discarded `Variables.new` per item.
      test_defaults = test.responds_to?(:defaults) ? test.defaults : Variables.new

      target.{{ func.id }} do |item|
        args = Arguments.new(env, varargs, arguments.kwargs, defaults: test_defaults, target: item)
        env.execute_call(test, args).truthy?
      end
    end
  end

  Crinja.filter(:select) do
    Crinja::Filter.select_reject(:select)
  end

  Crinja.filter(:reject) do
    Crinja::Filter.select_reject(:reject)
  end

  Crinja.filter(:selectattr) do
    Crinja::Filter.select_reject_attr(:select)
  end

  Crinja.filter(:rejectattr) do
    Crinja::Filter.select_reject_attr(:reject)
  end

  # Real Jinja2's `do_groupby` yields `(grouper, list)` namedtuples
  # (`_GroupTuple`), not a mapping - its own docstring documents BOTH
  # consumption forms, tuple unpacking (`{% for grouper, list in ... %}`)
  # and attribute access (`group.grouper`, `group.list`). A plain 2-tuple
  # subclass covers the unpacking form via the for tag's existing pair
  # handling; overriding `crinja_attribute` adds the attribute form,
  # which a Dictionary-shaped result (this fork's previous return value)
  # could never provide.
  class GroupTuple < Crinja::Tuple
    def initialize(grouper : Value, list : Value)
      super([grouper, list] of Value)
    end

    def grouper
      self[0]
    end

    def list
      self[1]
    end

    def crinja_attribute(attr : Crinja::Value) : Crinja::Value
      case attr.to_s
      when "grouper" then grouper
      when "list"    then list
      else
        Crinja::Value.new(Crinja::Undefined.new(attr.to_s))
      end
    end
  end

  # Real Jinja2's `do_groupby` sorts the items by the attribute value
  # FIRST and only then runs Python's `itertools.groupby`, which merges
  # ADJACENT equal keys - the pre-sort is what both orders the groups by
  # key and collapses every equal key into one group. With
  # `case_sensitive=false` (the default) the sort AND group key is the
  # attribute value case-folded via `.lower()` (strings only -
  # `ignore_case` checks `isinstance(value, str)` before folding), and
  # the emitted `grouper` is re-derived from the group's FIRST item with
  # an unfolded attrgetter (`out = [_GroupTuple(output_expr(values[0]),
  # values) ...]`), so "a" and "A" merge into one group keyed by
  # whichever original value sorted first. An item missing the attribute
  # entirely falls back to the `default=` kwarg when given; without one,
  # real Jinja2 raises UndefinedError even in the default lenient
  # environment - the sort key becomes an Undefined marker and comparing
  # markers inside `sorted()` fails (verified live against Jinja2 3.1.6:
  # `'dict object' has no attribute 'city'`). This fork previously read
  # NEITHER kwarg and grouped an unsorted sequence by exact key in
  # insertion order, producing a separate empty-key group for missing
  # attributes and the wrong order/grouping even for the default
  # case-insensitive request; found via a differential harness running
  # real Jinja2 3.1.6's own upstream test suite against this fork.
  Crinja.filter({attribute: UNDEFINED, default: UNDEFINED, case_sensitive: false}, :groupby) do
    attribute = arguments["attribute"]
    case_sensitive = arguments["case_sensitive"].truthy?
    default = arguments["default"]
    has_default = arguments.is_set?("default") && !default.none?

    # (item, unfolded key, sort/group key, original index) - the index
    # tiebreak keeps the sort stable like Python's `sorted()`, which
    # `do_groupby` relies on both for within-group order and for which
    # item donates the case-insensitive group's `grouper`.
    entries = [] of ::Tuple(Value, Value, Value, Int32)

    target.to_a.each_with_index do |item, index|
      key = Resolver.resolve_dig(attribute, item)
      if (undefined = key.raw).is_a?(Undefined)
        raise UndefinedError.new(undefined.name) unless has_default
        key = default
      end
      sort_key = if !case_sensitive && key.string?
                   Value.new(key.as_s.downcase)
                 else
                   key
                 end
      entries << {item, key, sort_key, index}
    end

    sorted = entries.sort_by { |entry| {entry[2], entry[3]} }

    result = [] of Value
    index = 0
    while index < sorted.size
      sort_key = sorted[index][2]
      group = [sorted[index][0]]
      index += 1
      while index < sorted.size && sorted[index][2] == sort_key
        group << sorted[index][0]
        index += 1
      end
      grouper = case_sensitive ? sort_key : sorted[index - group.size][1]
      result << Value.new(GroupTuple.new(grouper, Value.new(group)))
    end

    result
  end

  # `max`/`min` - real Jinja2 core filters. Compares elements with
  # `Value`'s own `<=>` (`Comparable`), matching real Jinja2's general
  # (not numeric-only) comparison.
  #
  # Real Jinja2's `_min_or_max` (jinja2/filters.py) always feeds Python's
  # `min`/`max` a key function built by `make_attrgetter(...,
  # postprocess=ignore_case if not case_sensitive else None)` where
  # `ignore_case` lowercases string values and passes everything else
  # through unchanged - so the comparison is case-INsensitive for
  # strings by default (`case_sensitive` defaults to False in both
  # `do_min`/`do_max`), and only an explicit `case_sensitive=true` uses
  # the raw ASCII ordering. This fork previously passed no key function
  # at all, always comparing raw strings: `{{ ["a", "B"]|min }}` wrongly
  # returned `B` (0x42 < 0x61) instead of `a`, and `|max` the mirror
  # image. Confirmed live against real Jinja2 3.1.6 AND a real local
  # `ansible-playbook` run (both give min=`a`/max=`B` by default and the
  # flip with `case_sensitive=true`), so this is NOT an
  # Ansible-environment customization. Python's `min`/`max` return the
  # first item on ties (e.g. `["a", "A"]` -> `a` for both), which
  # Crystal's `min_by`/`max_by` match with their first-wins-on-ties
  # comparison.
  Crinja.filter({case_sensitive: false}, :max) do
    case_sensitive = arguments["case_sensitive"].truthy?
    target.each.to_a.max_by? do |item|
      !case_sensitive && item.string? ? Value.new(item.as_s.downcase) : item
    end.try(&.raw)
  end
  Crinja.filter({case_sensitive: false}, :min) do
    case_sensitive = arguments["case_sensitive"].truthy?
    target.each.to_a.min_by? do |item|
      !case_sensitive && item.string? ? Value.new(item.as_s.downcase) : item
    end.try(&.raw)
  end

  # `unique(case_sensitive=false, attribute=none)` - real Jinja2 core
  # filter. Preserves first-occurrence order.
  Crinja.filter({case_sensitive: false, attribute: nil}, :unique) do
    case_sensitive = arguments["case_sensitive"].truthy?
    attribute = arguments["attribute"]
    has_attribute = !attribute.none?

    seen = Set(String).new
    result = [] of Value

    target.each do |item|
      key_value = has_attribute ? Resolver.resolve_dig(attribute, item) : item
      key = key_value.to_s
      key = key.downcase unless case_sensitive

      unless seen.includes?(key)
        seen << key
        result << item
      end
    end

    result
  end
end
