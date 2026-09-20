require "uri"
require "html"
require "../../util/json_builder"

module Crinja::Filter
  # Real Jinja2's `do_urlize` (jinja2/filters.py) accepts `trim_url_limit`,
  # `nofollow`, `target`, `rel` and `extra_schemes` kwargs.
  Crinja.filter({trim_url_limit: nil, nofollow: false, target: nil, rel: nil, extra_schemes: nil}, :urlize) do
    # Real Jinja2's `do_urlize` collects `rel` parts from the `rel` kwarg,
    # the `nofollow` kwarg and the `urlize.rel` policy into a set and then
    # emits them space-joined in SORTED order (`" ".join(sorted(rel_parts))`),
    # which is why `urlize(nofollow=true)` renders `rel="nofollow noopener"`.
    rel_parts = arguments["rel"].to_s.split(' ')
    rel_parts << "nofollow" if arguments["nofollow"].truthy?
    rel_parts |= env.policies.fetch("urlize.rel", "noopener").to_s.split(' ')
    rel = rel_parts.reject(&.empty?).to_set.to_a.sort.join(' ')

    target_attr = arguments.fetch("target") { env.policies.fetch("urlize.target", nil) }.raw.as(String?)
    # Template number literals arrive as Int64, so accept any Int and narrow.
    trim_url_limit = arguments["trim_url_limit"].raw.as?(Int).try(&.to_i32)

    # Real Jinja2's `do_urlize` falls back to the `urlize.extra_schemes`
    # policy when the `extra_schemes` kwarg is not given, and validates each
    # scheme against `_uri_scheme_re` (`^([\w.+-]{2,}:(/){0,2})$`), raising
    # `FilterArgumentError` for anything else.
    schemes_value = arguments.fetch("extra_schemes") { env.policies.fetch("urlize.extra_schemes", nil) }
    extra_schemes = [] of String
    unless schemes_value.none? || schemes_value.undefined?
      schemes_value.each do |scheme|
        scheme = scheme.to_s
        unless Crinja::Util::URI_SCHEME_RE.matches?(scheme)
          raise Arguments::Error.new("extra_schemes", "#{scheme.inspect} is not a valid URI scheme prefix.")
        end
        extra_schemes << scheme
      end
    end

    Crinja::Util.urlize(target.to_s, trim_url_limit, rel.empty? ? nil : rel, target_attr, extra_schemes)
  end

  Crinja.filter(:urlencode) do
    if (hash = target.raw).is_a?(Hash)
      # Real Jinja2's urlencode pairs up a dict's items (`{0: 1} |
      # urlencode` -> "0=1"). A bare dict iterates its KEYS since
      # crystal-play-0.9.25, so the (key, value) pairs are built here
      # explicitly instead of relying on iteration to tuple them.
      hash.map { |key, value| "#{URI.encode_www_form(key.to_s)}=#{URI.encode_www_form(value.to_s)}" }.join("&")
    elsif target.iterable?
      target.map do |item|
        if item.iterable? && item.size == 2
          [URI.encode_www_form(item[0].to_s), "=", URI.encode_www_form(item[1].to_s)].join
        else
          URI.encode_www_form(item.to_s)
        end
      end.join("&")
    else
      URI.encode_www_form(target.to_s, space_to_plus: false)
    end
  end

  # TODO: This is still a draft implementation.
  # `responds_to?(:to_json)` is true for every object, because to_json.cr adds the wrappers everywhere.
  Crinja.filter({indent: nil}, :tojson) do
    raw = target.raw

    indent = arguments.fetch("indent", 0).to_i

    SafeString.escape do |io|
      JsonBuilder.to_json(io, raw, indent)
    end
  end

  Crinja.filter({autoescape: true}, :xmlattr) do
    string = SafeString.build do |io|
      target.as_h.each do |key, value|
        next if value.none? || value.undefined?

        io << sprintf %( %s="%s"), Crinja::Util.markupsafe_escape(key.to_s), Crinja::Util.markupsafe_escape(value.to_s)
      end
    end

    if string.size > 0 && !arguments["autoescape"].truthy?
      string = string[1..-1]
    end

    string
  end
end

module Crinja::Util
  # Real Jinja2's `urlize` (jinja2/utils.py) splits the text on
  # `re.split(r"(\s+)", str(markupsafe.escape(text)))`, so candidates are
  # matched against the HTML-escaped text (`&` -> `&amp;` etc.) and
  # whitespace runs are kept as separate tokens.
  #
  # Candidate detection is `_http_re`, an anchored regex that accepts ONLY:
  # `http(s)://` or `www.` followed by a valid-ish domain with a TLD of at
  # least 2 letters (or an IDNA `xn--` TLD), a bare domain on a fixed list
  # of TLDs (com/net/int/edu/gov/org/info/mil), or `http(s)://` followed by
  # an IPv4 or bracketed IPv6 address - plus optional port and
  # path/query/fragment. Anything else (e.g. `ftp://localhost` without
  # `extra_schemes`, a scheme-less host on an unknown TLD) stays plain
  # text, unlike the previous rails_autolink-style heuristic this fork used
  # (which linked ANY `scheme://` and missed bare domains entirely - found
  # via a differential harness running real Jinja2 3.1.6's own upstream
  # test suite against this fork).
  HTTP_URL_RE = /^(
      (https?:\/\/|www\.)(([\w%\-]+\.)+)?([a-z]{2,63}|xn\-\-[\w%]{2,59})
    | ([\w%\-]{2,63}\.)+(com|net|int|edu|gov|org|info|mil)
    | (https?:\/\/)
      ((([\d]{1,3})(\.[\d]{1,3}){3})|(\[([\da-f]{0,4}:){2}([\da-f]{0,4}:?){1,6}\]))
  )(?::[\d]{1,5})?(?:[\/?#]\S*)?$/ix

  # Real Jinja2's `_email_re` (`^\S+@\w[\w.-]*\.\w+$`).
  EMAIL_URL_RE = /^\S+@\w[\w.\-]*\.\w+$/

  # Real Jinja2's `_uri_scheme_re` (jinja2/filters.py), used to validate
  # `extra_schemes` entries.
  URI_SCHEME_RE = /^[\w.+\-]{2,}:(\/){0,2}$/

  # Real Jinja2's `urlize` strips leading `(`/`<` (or `&lt;`) punctuation
  # into a "head" and trailing `)`/`>`/`.`/`,`/newline (or `&gt;`)
  # punctuation into a "tail", both re-joined around the (possibly
  # linkified) middle afterwards.
  LEAD_PUNCT_RE = /^(?:[(<]|&lt;)+/
  TRAIL_PUNCT_RE = /(?:[)>.,\n]|&gt;)+$/

  # THE shared markupsafe-compatible escape table for this fork, used by
  # the `escape`/`e`/`forceescape` filters, `SafeString.escape` (and thus
  # autoescape output), `xmlattr` and `urlize`. Real markupsafe's escape
  # table is `&` -> `&amp;`, `<` -> `&lt;`, `>` -> `&gt;`, `'` -> `&#39;`,
  # `"` -> `&#34;` - all four non-ampersand entities are NUMERIC, unlike
  # Crystal's `HTML.escape` (`&quot;` for `"`). Verified against real
  # markupsafe and real `ansible-playbook` 2.19 (`{{ s | escape }}` with
  # all 5 special characters renders `&lt; &gt; &amp; &#34; &#39;`).
  def self.markupsafe_escape(string : String)
    string.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub("\"", "&#34;").gsub("'", "&#39;")
  end

  # Real Jinja2's `trim_url` only shortens the DISPLAYED url, and appends
  # "..." after the first `trim_url_limit` characters (not within them).
  def self.trimmed_display(url : String, trim_url_limit : Int32?)
    if limit = trim_url_limit
      return url[0, limit] + "..." if url.size > limit
    end
    url
  end

  def self.urlize(text, trim_url_limit, rel, target, extra_schemes : Array(String)?)
    rel_attr = ""
    rel_attr = %( rel="%s") % markupsafe_escape(rel) unless rel.nil? || rel.empty?

    target_attr = ""
    target_attr = %( target="%s") % markupsafe_escape(target) unless target.nil? || target.empty?

    escaped = markupsafe_escape(text)

    SafeString.build do |io|
      escaped.split(/(\s+)/).each do |word|
        head = ""
        middle = word
        tail = ""

        if match = middle.match(LEAD_PUNCT_RE)
          head = match[0]
          middle = middle[match.end..]
        end

        # Unlike lead, which is anchored to the start of the string,
        # real Jinja2 only searches for trailing punctuation when the
        # word actually ends with one of those characters, to avoid
        # backtracking.
        if middle.ends_with?(')') || middle.ends_with?('>') || middle.ends_with?('.') ||
           middle.ends_with?(',') || middle.ends_with?('\n') || middle.ends_with?("&gt;")
          if match = middle.match(TRAIL_PUNCT_RE)
            tail = match[0]
            middle = middle[0...match.begin]
          end
        end

        # Real Jinja2's urlize prefers balancing parentheses/angle
        # brackets in the URL over leaving them in the tail.
        [{"(", ")"}, {"<", ">"}, {"&lt;", "&gt;"}].each do |start_char, end_char|
          start_count = middle.count(start_char)
          next if start_count <= middle.count(end_char)

          [start_count, tail.count(end_char)].min.times do
            if index = tail.index(end_char)
              end_index = index + end_char.size
              middle += tail[0...end_index]
              tail = tail[end_index..]
            end
          end
        end

        if HTTP_URL_RE.matches?(middle)
          # Real Jinja2 generates `https://` hrefs for schemeless and
          # `www.`-prefixed URLs, and only the DISPLAY is trimmed.
          if middle.starts_with?("https://") || middle.starts_with?("http://")
            middle = %(<a href="#{middle}"#{rel_attr}#{target_attr}>#{trimmed_display(middle, trim_url_limit)}</a>)
          else
            middle = %(<a href="https://#{middle}"#{rel_attr}#{target_attr}>#{trimmed_display(middle, trim_url_limit)}</a>)
          end
        elsif middle.starts_with?("mailto:") && EMAIL_URL_RE.matches?(middle[7..])
          # Real Jinja2 emits NO rel/target attributes on mailto links.
          middle = %(<a href="#{middle}">#{middle[7..]}</a>)
        elsif middle.includes?('@') && !middle.starts_with?("www.") && !middle.starts_with?("@") &&
              !middle.includes?(':') && EMAIL_URL_RE.matches?(middle)
          middle = %(<a href="mailto:#{middle}">#{middle}</a>)
        elsif (schemes = extra_schemes)
          # Real Jinja2 only linkifies an extra scheme when the word
          # actually STARTS WITH the prefix (and isn't the bare prefix).
          schemes.each do |scheme|
            if middle != scheme && middle.starts_with?(scheme)
              middle = %(<a href="#{middle}"#{rel_attr}#{target_attr}>#{middle}</a>)
              break
            end
          end
        end

        io << head << middle << tail
      end
    end
  end
end
