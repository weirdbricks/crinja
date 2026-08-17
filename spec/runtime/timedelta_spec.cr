require "../spec_helper.cr"

# Time arithmetic: real Ansible's `to_datetime(...) - to_datetime(...)`
# produces a timedelta whose `.days`/`.seconds`/`.total_seconds()` a role
# reads (dev-sec os_hardening's password-ageing assert). These specs
# exercise the fork-side `-` on `Time` values directly (registering a
# `to_datetime`-style binder here; the real Ansible-specific `to_datetime`
# filter lives in crystal-ansible).
describe "time delta" do
  bindings = {
    "a" => Crinja::Value.new(Time.utc(2024, 1, 2)),
    "b" => Crinja::Value.new(Time.utc(2024, 1, 1)),
    "c" => Crinja::Value.new(Time.utc(2024, 1, 1, 0, 1, 0)),
    "d" => Crinja::Value.new(Time.utc(2024, 1, 1)),
  }

  it "subtracts two times into a timedelta with a .days attribute" do
    evaluate_expression(%((a - b).days), bindings).should eq("1")
  end

  it "reads .seconds off a sub-day difference" do
    evaluate_expression(%((c - d).seconds), bindings).should eq("60")
  end

  it "reads .total_seconds() off a difference" do
    evaluate_expression(%((c - d).total_seconds()), bindings).should eq("60.0")
  end

  it "stringifies a bare day-scale timedelta like Python" do
    evaluate_expression(%(a - b), bindings).should eq("1 day, 0:00:00")
  end

  it "leaves plain numeric subtraction untouched" do
    evaluate_expression(%(10 - 4)).should eq("6")
  end

  it "adds a timedelta back onto a time, in either operand order" do
    evaluate_expression(%((a - b) + b), bindings).should eq(Time.utc(2024, 1, 2).to_s)
    evaluate_expression(%(b + (a - b)), bindings).should eq(Time.utc(2024, 1, 2).to_s)
  end

  it "adds two timedeltas together" do
    evaluate_expression(%(((a - b) + (a - b)).days), bindings).should eq("2")
  end

  it "multiplies a timedelta by a scalar, in either operand order" do
    evaluate_expression(%(((a - b) * 3).days), bindings).should eq("3")
    evaluate_expression(%((3 * (a - b)).days), bindings).should eq("3")
  end
end
