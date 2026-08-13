Crinja.function(:namespace) do
  ns = Crinja::Namespace.new
  arguments.kwargs.each do |key, value|
    ns[key] = value
  end
  Crinja::Value.new(ns)
end
