require "../spec_helper"

describe Crinja::Value do
  it "compare pytuple" do
    Crinja::Tuple.new("foo", 1).should eq Crinja::Tuple.new("foo", 1)
  end

  it "sorts a list of tuples element-wise, like Python's own tuple ordering" do
    # Value#compare had no branch for Crinja::Tuple at all, so a
    # Tuple-vs-Tuple comparison (needed to sort dict.items(), a list of
    # 2-tuples) fell to the generic "cannot compare" TypeError -
    # found via krikri's own Oefenweb.bash template:
    # `{% for key, value in bash_aliases.items() | sort %}`.
    unsorted = [
      Crinja::Value.new(Crinja::Tuple.new("ll", "ls -la")),
      Crinja::Value.new(Crinja::Tuple.new("la", "ls -A")),
    ]
    sorted = unsorted.sort
    sorted[0].raw.as(Crinja::Tuple)[0].should eq Crinja::Value.new("la")
    sorted[1].raw.as(Crinja::Tuple)[0].should eq Crinja::Value.new("ll")
  end

  describe "raw_each" do
    it "array" do
      a = [1, 2, 3]
      Crinja::Value.new(a).map(&.raw).to_a.should eq a.map(&.as(Crinja::Raw))
    end

    it "hash" do
      # Real Jinja2/Python iterates a bare dict yielding its KEYS
      # (`for k in dict:`); (key, value) pairs are the explicit opt-ins
      # (`.items()`, `dictsort`, two-variable for).
      hash = Crinja::Dictionary.new
      hash[Crinja::Value.new "foo"] = Crinja::Value.new 1
      hash[Crinja::Value.new "bar"] = Crinja::Value.new 3
      Crinja::Value.new(hash).map(&.raw).to_a.should eq ["foo", "bar"]
    end
  end

  describe "each" do
    it "array" do
      a = [1, 2, 3]
      Crinja::Value.new(a).to_a.should eq a.map { |item| Crinja::Value.new(item) }
    end

    it "hash" do
      # Keys-only for a bare dict - see the raw_each "hash" spec above.
      hash = Crinja::Dictionary.new
      hash[Crinja::Value.new "foo"] = Crinja::Value.new 1
      hash[Crinja::Value.new "bar"] = Crinja::Value.new 3
      Crinja::Value.new(hash).to_a.should eq [Crinja::Value.new("foo"), Crinja::Value.new("bar")]
    end

    it "#each" do
      Crinja::Value.new([1]).each.should be_a(Iterator(Crinja::Value))
      Crinja::Value.new([1]).each.each_with_index do |item, index|
        item.should eq Crinja::Value.new 1
        index.should eq 0
      end

      Crinja::Value.new([1]).each_with_index do |item, index|
        item.should eq Crinja::Value.new 1
        index.should eq 0
      end
    end

    it "raw_#each" do
      # be_a matcher doesn't support uninstantiated generic type
      Crinja::Value.new([1]).raw_each.is_a?(Crinja::Value::RawIterator).should be_true

      Crinja::Value.new([1]).raw_each.each_with_index do |item, index|
        item.should eq 1
        index.should eq 0
      end

      count = 0
      Crinja::Value.new([1]).raw_each do |item|
        item.should eq 1
        count += 1
      end
      count.should eq 1
    end
  end
end
