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
end
