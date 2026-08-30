require "../src/crinja"
env = Crinja.new
puts "FILTERS: #{env.filters.keys.sort.join(",")}"
puts "TESTS: #{env.tests.keys.sort.join(",")}"
puts "FUNCS: #{env.functions.keys.sort.join(",")}"
