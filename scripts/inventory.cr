require "../src/crinja"

# PATTERN2_AUDIT.md helper: dump the registered default feature names so the
# ansible-core filter/test diff can be re-run at any time.
env = Crinja.new
filters = env.filters.keys
filters.sort!
tests = env.tests.keys
tests.sort!
funcs = env.functions.keys
funcs.sort!
puts "FILTERS: #{filters.join(",")}"
puts "TESTS: #{tests.join(",")}"
puts "FUNCS: #{funcs.join(",")}"
