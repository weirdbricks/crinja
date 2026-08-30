require "../spec_helper"

describe "expressions" do
  it "`none` evaluates to 'None' via the bare-expression API, matching real Python's str()" do
    # `evaluate_expression`/`env.evaluate(String, bindings)` is a bare
    # expression-string evaluator, NOT a template render - it goes
    # through the shared `env.stringify`/`Finalizer#stringify(Nil)`
    # path (same one `join`/`~`/`+` use), which matches real Python's
    # `str(None)` ("None", capitalized - same idea as the `Bool`
    # overload). Previously this incorrectly returned lowercase "none".
    evaluate_expression(%(none)).should eq "None"
    evaluate_expression(%(x), {x: nil}).should eq "None"
  end

  it "`{{ none }}` in an actual TEMPLATE renders as an empty string, matching real Ansible" do
    # A template's own top-level `{{ }}` output goes through a
    # DIFFERENT, narrower path (`Renderer#render`'s own `PrintStatement`
    # visit) - real Ansible's own Jinja Environment finalize hook
    # (`templar.py`: `'' if x is None else x`) renders None as nothing
    # at all there specifically, verified directly against a real
    # ansible-playbook run. This is the path krikri's own
    # CrinjaRenderer actually uses (`Template#render`), unlike the bare
    # `env.evaluate(String)` helper the sibling spec above exercises.
    render(%({{ none }}|{{ x }}), {x: nil}).should eq "|"
  end

  it "parses double array" do
    evaluate_expression(%([[1,2,3]])).should eq "[[1, 2, 3]]"
  end
end
