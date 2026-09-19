require "../spec_helper"

describe Crinja::Operator do
  describe "==" do
    context "valid" do
      it "compares two strings" do
        evaluate_expression(%('a' == 'a')).should eq("True")
      end
      it "compares two arrays" do
        evaluate_expression(%(['a'] == ['a'])).should eq("True")
      end
    end
    context "invalid" do
      it "compares two strings" do
        evaluate_expression(%('a' == 'b')).should eq("False")
      end
      it "compares two arrays" do
        evaluate_expression(%(['a'] == ['b'])).should eq("False")
      end
    end
  end

  describe "!=" do
    context "valid" do
      it "compares two strings" do
        evaluate_expression(%('a' != 'b')).should eq("True")
      end
      it "compares two arrays" do
        evaluate_expression(%(['a'] != ['b'])).should eq("True")
      end
    end
    context "invalid" do
      it "compares two strings" do
        evaluate_expression(%('a' != 'a')).should eq("False")
      end
      it "compares two arrays" do
        evaluate_expression(%(['a'] != ['a'])).should eq("False")
      end
    end
  end

  # Chained comparisons are Python-style sugar for an implicit `and`
  # between each adjacent pair (real Jinja2's own `nodes.Compare` grammar,
  # see `PATCHES.md`), NOT left-to-right nesting - the latter evaluates
  # the intermediate boolean as the next comparison's left operand and
  # raises `Cannot compare Bool value` (found via the differential
  # harness against real Jinja2 3.1.6's own test suite). Expected values
  # verified live against real Jinja2 3.1.6.
  describe "chained comparison" do
    it "evaluates a single comparison exactly as before" do
      evaluate_expression(%(2 < 3)).should eq("True")
    end
    it "short-circuits on the first False pair" do
      evaluate_expression(%(4 < 2 < 3)).should eq("False")
      evaluate_expression(%(a < b < c), {a: 4, b: 2, c: 3}).should eq("False")
      evaluate_expression(%(4 > 2 > 3)).should eq("False")
      evaluate_expression(%(a > b > c), {a: 4, b: 2, c: 3}).should eq("False")
    end
    it "is True when every adjacent pair is True" do
      evaluate_expression(%(4 > 2 < 3)).should eq("True")
      evaluate_expression(%(a > b < c), {a: 4, b: 2, c: 3}).should eq("True")
      evaluate_expression(%(1 < 2 < 3 < 4)).should eq("True")
    end
  end
end
