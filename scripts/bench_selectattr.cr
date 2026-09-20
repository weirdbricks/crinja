# selectattr/rejectattr/select/reject per-item dispatch benchmark.
#
# Measures the per-invocation cost of the native selectattr filter over
# lists of 4 / 50 / 500 items (realistic Ansible inventory-shaped entries),
# calling the registered filter callable directly - the same methodology as
# krikri's scripts/crinja_corpus/bench_selectattr_pilot.cr, but exercising
# this fork's filter registration without any bridge code. The callable is
# resolved from the registry ONCE (as the select_reject_attr macro does);
# what varies per measurement is the per-item loop inside the filter.
#
# Run from the repo root:
#   crystal run --release scripts/bench_selectattr.cr

require "../src/crinja"

def make_entries(n : Int32) : Array(Crinja::Value)
  (0...n).map do |i|
    entry = Crinja::Variables.new
    entry["mount"] = Crinja::Value.new("/srv/app#{i}")
    entry["device"] = Crinja::Value.new("/dev/vd#{('a'.ord + i % 26).chr}#{i}")
    entry["fstype"] = Crinja::Value.new(i % 3 == 0 ? "ext4" : "xfs")
    entry["state"] = Crinja::Value.new(i % 2 == 0 ? "present" : "absent")
    entry["enabled"] = Crinja::Value.new(i % 3 != 1)
    entry["size"] = Crinja::Value.new((i + 1) * 1024)
    Crinja::Value.new(entry)
  end
end

def bench(label : String, n : Int32, &)
  n.times { yield } # warmup
  start = Time.instant
  n.times { yield }
  elapsed = Time.instant - start
  per_call_ns = (elapsed.total_nanoseconds / n).round.to_i
  puts "#{label.ljust(62)} total=#{elapsed.total_milliseconds.round(1)}ms  per_call=#{per_call_ns}ns"
end

N = 20_000

env = Crinja.new
filter = env.filters["selectattr"]

puts "selectattr dispatch bench (N=#{N} per measurement)"

{4, 50, 500}.each do |size|
  entries = make_entries(size)

  puts "--- list of #{size} entries ---"
  bench("selectattr('state','equalto','present') x#{size}", N) do
    arguments = Crinja::Arguments.new(
      env,
      varargs: [Crinja::Value.new("state"), Crinja::Value.new("equalto"), Crinja::Value.new("present")] of Crinja::Value,
      kwargs: Crinja::Variables.new,
      target: Crinja::Value.new(entries),
    )
    arguments.defaults = filter.defaults if filter.responds_to?(:defaults)
    filter.call(arguments)
  end

  bench("selectattr('state') truthy-only x#{size}", N) do
    arguments = Crinja::Arguments.new(
      env,
      varargs: [Crinja::Value.new("state")] of Crinja::Value,
      kwargs: Crinja::Variables.new,
      target: Crinja::Value.new(entries),
    )
    arguments.defaults = filter.defaults if filter.responds_to?(:defaults)
    filter.call(arguments)
  end
end
