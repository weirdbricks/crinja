require "../spec_helper.cr"

describe Crinja::Operator do
  describe Crinja::Operator::Library do
    it "has default operators registered" do
      library = Crinja::Operator::Library.new

      library.keys.should eq ["+", "-", "/", "//", "%", "*", "**", "~", "==", "!=", ">", ">=", "<", "<=", "and", "or", "not", "in", "not in"]
    end

    it "should have + operator" do
      library = Crinja::Operator::Library.new
      library.has_key?("+").should be_true
    end

    it "plus operator is valid" do
      library = Crinja::Operator::Library.new(false)
      plus = Crinja::Operator::Plus.new
      library << plus
    end
  end

  describe "+" do
    it "concatenates two strings" do
      evaluate_expression("'a' + 'b'").should eq("ab")
    end
    it "concatenates two arrays" do
      evaluate_expression("['a'] + ['b']").should eq(%(['a', 'b']))
    end
    it "stringifies a non-numeric, non-array operand through Finalizer (Python parity)" do
      evaluate_expression(%(true + "x")).should eq("Truex")
    end
  end

  describe "-" do
    it "subtracts two integers" do
      evaluate_expression("1 - 3").should eq("-2")
    end

    it "subtracts integer from float" do
      evaluate_expression("4.5 - 2").should eq("2.5")
    end

    it "fails to subtract string" do
      expect_raises(Crinja::Arguments::Error) do
        evaluate_expression(%(42 - "a"))
      end
    end
  end

  describe "/" do
    it "divides two integers" do
      evaluate_expression("4 / 2").should eq("2.0")
    end
    it "divides integer by float" do
      evaluate_expression("2 / 1.0").should eq("2.0")
    end
    it "divides two floats" do
      evaluate_expression("1.0 / 2.0").should eq("0.5")
    end
    it "fails to divde string" do
      expect_raises(Crinja::Arguments::Error) do
        evaluate_expression(%(42 / "a"))
      end
    end
  end

  describe "//" do
    it "int divides two integers" do
      evaluate_expression("4 // 2").should eq("2")
    end
    it "int divides integer by float" do
      evaluate_expression("20 // 7.0").should eq("2")
    end
    it "int divides two floats" do
      evaluate_expression("1.0 // 2.0").should eq("0")
    end
    it "fails to int divde string" do
      expect_raises(Crinja::Arguments::Error) do
        evaluate_expression(%(42 // "a"))
      end
    end
  end

  describe "%" do
    it "modulo two integers" do
      evaluate_expression("11 % 7").should eq("4")
    end
    it "modulo integer by float" do
      evaluate_expression("5 % 1.5").should eq("0")
    end
    it "modulo two floats" do
      evaluate_expression("1.0 % 2.0").should eq("1")
    end
    it "fails to modulo string" do
      expect_raises(Crinja::Arguments::Error) do
        evaluate_expression(%(42 % "a"))
      end
    end
  end

  describe "*" do
    it "multiplies two integers" do
      evaluate_expression("2 * 3 ").should eq("6")
    end
    it "multiplies integer by float" do
      evaluate_expression("20 * 7.0 ").should eq("140.0")
    end
    it "multiplies two floats" do
      evaluate_expression("1.0 * 2.0 ").should eq("2.0")
    end
    it "fails to multiply string" do
      expect_raises(Crinja::Arguments::Error) do
        evaluate_expression(%(42 * "a"))
      end
    end
  end

  describe "**" do
    it "raises two integers" do
      evaluate_expression("2 ** 3").should eq("8")
    end
    it "raises integer by float" do
      evaluate_expression("2 ** -1").should eq("0.5")
    end
    it "raises two floats" do
      evaluate_expression("4.0 ** 0.5").should eq("2.0")
    end
    it "fails to raise string" do
      expect_raises(Crinja::Arguments::Error) do
        evaluate_expression(%(42 ** "a"))
      end
    end
  end

  describe "and" do
    it "works" do
      evaluate_expression("true and true").should eq("True")
    end
    it "works" do
      evaluate_expression("1 and 1").should eq("1")
    end
    it "works" do
      evaluate_expression("true and none").should eq("none")
    end
    it "evaluates right branch if first is true" do
      env = Crinja.new
      test_called = false
      env.functions["test"] = Crinja.function { test_called = true }
      env.evaluate("true and test()")
      test_called.should be_true
    end
    it "does not evaluate right branch if first is false" do
      env = Crinja.new
      test_called = false
      env.functions["test"] = Crinja.function { test_called = true }
      env.evaluate("false and test()")
      test_called.should be_false
    end
  end

  describe "or" do
    it "works" do
      evaluate_expression("true or true").should eq("True")
      evaluate_expression("false or none").should eq("none")
      evaluate_expression("1 or 1").should eq("1")
      evaluate_expression("true or none").should eq("True")
    end
    it "evaluates right branch if first is false" do
      env = Crinja.new
      test_called = false
      env.functions["test"] = Crinja.function { test_called = true }
      env.evaluate("false or test()")
      test_called.should be_true
    end
    it "does not evaluate right branch if first is true" do
      env = Crinja.new
      test_called = false
      env.functions["test"] = Crinja.function { test_called = true }
      env.evaluate("true or test()")
      test_called.should be_false
    end
  end

  describe "precedence" do
    it { evaluate_expression(%(true or false and false)).should eq "True" }
    it { evaluate_expression(%((true or false) and false)).should eq "False" }
    it { evaluate_expression(%(2 + 4 * 2)).should eq "10" }
    it { evaluate_expression(%((2 + 4) * 2)).should eq "12" }
  end

  describe "==" do
    it { evaluate_expression(%([1, 2] == [1, 2, 3])).should eq "False" }
    it { evaluate_expression(%([1, 3] == [1, 3])).should eq "True" }
    it { evaluate_expression(%([1, 2] == 2)).should eq "False" }
    it { evaluate_expression(%(true == 2)).should eq "False" }
    it { evaluate_expression(%(1 == false)).should eq "False" }
    it { evaluate_expression(%({ foo: bar } == 2)).should eq "False" }
    it { evaluate_expression(%(1 == 2)).should eq "False" }
    it { evaluate_expression(%(2 == 2)).should eq "True" }
    it { evaluate_expression(%("a" == "b")).should eq "False" }
    it { evaluate_expression(%("b" == "b")).should eq "True" }
  end
  describe "!=" do
    it { evaluate_expression(%([1, 2] != [1, 2, 3])).should eq "True" }
    it { evaluate_expression(%([1, 3] != [1, 3])).should eq "False" }
    it { evaluate_expression(%([1, 2] != 2)).should eq "True" }
    it { evaluate_expression(%(true != 2)).should eq "True" }
    it { evaluate_expression(%(1 != true)).should eq "True" }
    it { evaluate_expression(%({ foo: bar } != 2)).should eq "True" }
    it { evaluate_expression(%(1 != 2)).should eq "True" }
    it { evaluate_expression(%(2 != 2)).should eq "False" }
    it { evaluate_expression(%("a" != "b")).should eq "True" }
    it { evaluate_expression(%("b" != "b")).should eq "False" }
  end

  describe "comparators" do
    describe ">" do
      it { evaluate_expression(%([1, 2] > [1, 2])).should eq "False" }
      it { evaluate_expression(%([1, 2] > [1, 2, 3])).should eq "False" }
      it { evaluate_expression(%([1, 3] > [1, 2, 3])).should eq "True" }
      it { expect_raises(Crinja::TypeError) { evaluate_expression(%([1, 2] > 2)) } }
      it { expect_raises(Crinja::TypeError) { evaluate_expression(%(true > 2)) } }
      it { expect_raises(Crinja::TypeError) { evaluate_expression(%(1 > false)) } }
      it { expect_raises(Crinja::TypeError) { evaluate_expression(%({ foo: bar } > 2)) } }
      it { evaluate_expression(%(1 > 1)).should eq "False" }
      it { evaluate_expression(%(1 > 2)).should eq "False" }
      it { evaluate_expression(%(2 > 1)).should eq "True" }
      it { evaluate_expression(%("a" > "a")).should eq "False" }
      it { evaluate_expression(%("a" > "b")).should eq "False" }
      it { evaluate_expression(%("b" > "a")).should eq "True" }
    end
    describe ">=" do
      it { evaluate_expression(%([1, 2] >= [1, 2])).should eq "True" }
      it { evaluate_expression(%([1, 2] >= [1, 2, 3])).should eq "False" }
      it { evaluate_expression(%([1, 3] >= [1, 2, 3])).should eq "True" }
      it { expect_raises(Crinja::TypeError) { evaluate_expression(%([1, 2] >= 2)) } }
      it { expect_raises(Crinja::TypeError) { evaluate_expression(%(true >= 2)) } }
      it { expect_raises(Crinja::TypeError) { evaluate_expression(%(1 >= false)) } }
      it { expect_raises(Crinja::TypeError) { evaluate_expression(%({ foo: bar } >= 2)) } }
      it { evaluate_expression(%(1 >= 1)).should eq "True" }
      it { evaluate_expression(%(1 >= 2)).should eq "False" }
      it { evaluate_expression(%(2 >= 1)).should eq "True" }
      it { evaluate_expression(%("a" >= "a")).should eq "True" }
      it { evaluate_expression(%("a" >= "b")).should eq "False" }
      it { evaluate_expression(%("b" >= "a")).should eq "True" }
    end
    describe "<=" do
      it { evaluate_expression(%([1, 2] <= [1, 2])).should eq "True" }
      it { evaluate_expression(%([1, 2] <= [1, 2, 3])).should eq "True" }
      it { evaluate_expression(%([1, 3] <= [1, 2, 3])).should eq "False" }
      it { expect_raises(Crinja::TypeError) { evaluate_expression(%([1, 2] <= 2)) } }
      it { expect_raises(Crinja::TypeError) { evaluate_expression(%(true <= 2)) } }
      it { expect_raises(Crinja::TypeError) { evaluate_expression(%(1 <= false)) } }
      it { expect_raises(Crinja::TypeError) { evaluate_expression(%({ foo: bar } <= 2)) } }
      it { evaluate_expression(%(1 <= 1)).should eq "True" }
      it { evaluate_expression(%(1 <= 2)).should eq "True" }
      it { evaluate_expression(%(2 <= 1)).should eq "False" }
      it { evaluate_expression(%("a" <= "a")).should eq "True" }
      it { evaluate_expression(%("a" <= "b")).should eq "True" }
      it { evaluate_expression(%("b" <= "a")).should eq "False" }
    end
    describe "<" do
      it { evaluate_expression(%([1, 2] < [1, 2])).should eq "False" }
      it { evaluate_expression(%([1, 2] < [1, 2, 3])).should eq "True" }
      it { evaluate_expression(%([1, 3] < [1, 2, 3])).should eq "False" }
      it { expect_raises(Crinja::TypeError) { evaluate_expression(%([1, 2] < 2)) } }
      it { expect_raises(Crinja::TypeError) { evaluate_expression(%(true < 2)) } }
      it { expect_raises(Crinja::TypeError) { evaluate_expression(%(1 < false)) } }
      it { expect_raises(Crinja::TypeError) { evaluate_expression(%({ foo: bar } < 2)) } }
      it { evaluate_expression(%(1 < 1)).should eq "False" }
      it { evaluate_expression(%(1 < 2)).should eq "True" }
      it { evaluate_expression(%(2 < 1)).should eq "False" }
      it { evaluate_expression(%("a" < "a")).should eq "False" }
      it { evaluate_expression(%("a" < "b")).should eq "True" }
      it { evaluate_expression(%("b" < "a")).should eq "False" }
    end
    describe "~" do
      it { evaluate_expression(%("b" ~ "a")).should eq "ba" }
      it "stringifies a Bool operand through Finalizer (Python parity, not Crystal's lowercase to_s)" do
        evaluate_expression(%("flag=" ~ true)).should eq "flag=True"
      end
      it "stringifies an Array operand through Finalizer, not a raw Value inspect" do
        evaluate_expression(%("list=" ~ [1, 2])).should eq "list=[1, 2]"
      end
    end
  end
end
