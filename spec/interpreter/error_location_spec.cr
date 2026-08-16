require "../spec_helper"

describe "error locations" do
  # These two used to demonstrate error-location tracking for an
  # UndefinedError raised mid-chain (`non_existing.prop`,
  # `site.authors[johannes].name`). As of 0.9.8, chained access on an
  # undefined base self-propagates as Undefined instead of raising
  # (matches real Ansible's own `Marker.__getattr__`/`__getitem__`
  # self-propagation - see PATCHES.md's 0.9.8 entry and
  # spec/expression/identifiers_spec.cr's identical update), so neither
  # of these raises anymore - both now render as empty output for the
  # undefined expression, same as a plain unchained `{{ non_existing }}`
  # already did before this fork existed. Location-tracking itself is
  # still covered by spec/parser/error_spec.cr and
  # spec/parser/location_spec.cr, which don't depend on this behavior.
  it "basic error (no longer raises - see comment above)" do
    render(<<-'TPL_HTML').should eq <<-'HTML'
        <html>
          <div>{{ non_existing.prop }}</div>
        </html>
        TPL_HTML
      <html>
        <div></div>
      </html>
      HTML
  end

  it "complex expression (no longer raises - see comment above)" do
    result = render <<-'TPL_HTML', {"post" => {"author" => "johannes"}, "site" => {"authors" => {} of String => String}}
        <header>
        <div class="meta">
          {% if post.author %} by <span class="post-author">{{ site.authors[post.author].name }}</span>{% endif %}
        TPL_HTML

    result.should contain %(<span class="post-author"></span>)
  end
end
