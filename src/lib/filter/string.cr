
module Crinja::Util
  # Python's own `str.splitlines()` (no keepends), which real Jinja2's
  # `do_indent` relies on: every Python line boundary (\n, \r, \r\n,
  # \v, \f, \x1c, \x1d, \x1e, \x85, \u2028, \u2029) TERMINATES a line,
  # so consecutive boundaries each produce their own (possibly empty)
  # line - but a string ending in a single boundary yields NO trailing
  # empty line (unlike `split("\n")`, which would), and empty input
  # yields `[]`. That trailing-boundary rule is exactly what keeps
  # `do_indent` from re-indenting the phantom line after a trailing
  # newline (crystal-play-0.9.42, differential harness finding).
  def self.python_splitlines(string : String) : Array(String)
    boundaries = {'\n', '\u000b', '\u000c', '\u001c', '\u001d', '\u001e', '\u0085', '\u2028', '\u2029'}
    lines = [] of String
    buf = IO::Memory.new
    chars = string.chars
    i = 0
    while i < chars.size
      c = chars[i]
      if c == '\r'
        i += 1 if i + 1 < chars.size && chars[i + 1] == '\n'
        lines << buf.to_s
        buf.clear
      elsif boundaries.includes?(c)
        lines << buf.to_s
        buf.clear
      else
        buf << c
      end
      i += 1
    end
    lines << buf.to_s unless buf.size == 0
    lines
  end

  REGEX_WORD = /\s\-\(\{\[\</
end

module Crinja::Filter
  Crinja.filter(:upper) { target.to_s.upcase }

  Crinja.filter(:lower) { target.to_s.downcase }

  Crinja.filter(:capitalize) { target.to_s.capitalize }

  Crinja.filter({width: 80}, :center) do
    string = target.to_s
    width = arguments["width"].to_i
    if string.size >= width
      string
    else
      pad_width = width - string.size
      left_pad = pad_width // 2

      String.build do |io|
        io << " " * left_pad
        string.to_s(io)
        io << " " * (pad_width - left_pad)
      end
    end
  end

  Crinja.filter :striptags do
    # Pure-Crystal port of markupsafe's Markup.striptags (what real
    # Ansible's jinja2 striptags filter delegates to): comments removed
    # first (an unterminated comment is left alone), then tags removed by
    # scanning to the NEXT '>' (markupsafe does not special-case quoted
    # '>' inside attribute values - '<b title="x">c' loses
    # '<b title="x">' and keeps the rest), whitespace collapsed to single
    # spaces, and HTML entities unescaped LAST (so '&nbsp;' survives the
    # whitespace collapse as U+00A0, matching Python's
    # collapse-then-unescape order).
    #
    # This replaces XML.parse_html, whose libxml2 linkage dragged
    # libxml2.so.2 into every binary that rendered a template (the last
    # remaining libxml2 dependency in krikri's controller binary).
    s = target.to_s

    while true
      start = s.index("<!--") || break
      stop = s.index("-->", start) || break
      s = "#{s[0...start]}#{s[(stop + 3)..]}"
    end

    while true
      start = s.index("<") || break
      stop = s.index(">", start) || break
      s = "#{s[0...start]}#{s[(stop + 1)..]}"
    end

    HTML.unescape(s.split.map(&.strip).reject(&.empty?).join(" ")).strip
  end

  Crinja.filter(:format) { sprintf target.to_s, arguments.varargs }

  # Direct port of real Jinja2's `do_indent(s, width=4, first=False,
  # blank=False)` (jinja2/filters.py, verified against the installed
  # 3.1.6 source): append a newline quirk (`s += newline` "necessary for
  # splitlines method"), split with Python's `str.splitlines()`, then
  # either join ALL lines with `newline + indention` (blank=true) or
  # keep the first line bare and prepend `indention` only to non-empty
  # following lines (blank=false, where the trailing empty line that the
  # newline quirk creates for input ending in `\n` stays empty - which
  # is why real Jinja2 does NOT tack an indent after the final newline).
  # `first` then unconditionally prefixes `indention` - including for a
  # single-line input with no newline at all, where splitlines still
  # yields that one line (crystal-play-0.9.42, differential harness
  # finding: this fork previously regex-gsubbed every `\n` - adding a
  # trailing indent after the last real newline - and named the second
  # positional/kwarg `indentfirst`, the pre-2.10 Jinja2 name that Jinja2
  # 3.x removed, so `first=true` was never read and a newline-less
  # single line was never indented).
  Crinja.filter({
    width: 4,
    first: false,
    blank: false,
  }, :indent) do
    raw_width = arguments["width"].raw
    indention = raw_width.is_a?(String) ? raw_width : " " * arguments["width"].to_i
    newline = "\n"
    string = target.to_s + newline

    lines = Crinja::Util.python_splitlines(string)
    if arguments["blank"].truthy?
      rv = lines.join(newline + indention)
    else
      rv = lines.shift
      unless lines.empty?
        rv += newline + lines.join(newline) { |line| line.empty? ? line : indention + line }
      end
    end

    rv = indention + rv if arguments["first"].truthy?
    rv
  end

  # Python `str()` semantics: an explicit `| string` stringifies the
  # value BEFORE ansible-core's native-types finalization converts
  # tuples to lists, so tuples keep their `str(tuple)` parens repr here
  # (`{{ d1 | dictsort | string }}` -> `[('a', 1), ...]` - brackets
  # outer, parens inner) while bare interpolation renders brackets.
  # Verified against real ansible-core 2.19.4 (crystal-play-0.9.27).
  Crinja.filter(:string) { env.stringify target, env.context.autoescape?, true }

  Crinja.filter(:title) do
    target.to_s.gsub(/[^#{Crinja::Util::REGEX_WORD.source}]+/, &.capitalize)
  end

  Crinja.filter({length: 255, killwords: false, end: "...", leeway: nil}, :truncate) do
    length = arguments["length"].to_i
    append = arguments["end"].to_s
    end_size = append.size
    raise "expected length >= #{end_size}, got #{length}" if length < end_size
    leeway = arguments.fetch("leeway") { env.policies.fetch("truncate.leeway", 5) }.to_i
    raise "expected leeway >= 0, got #{leeway}" if leeway < 0
    killwords = arguments["killwords"].truthy?

    if leeway >= length
      # if string has very short length, don't use leeway and kill words
      leeway = 0
      killwords = true unless arguments.is_set?(:killwords)
    end

    s = target.to_s
    if s.size <= length + leeway
      s
    else
      trimmed = s[0, length - end_size]
      trimmed = trimmed.rpartition(' ').first unless killwords
      trimmed + append
    end
  end

  Crinja.filter(:wordcount) do
    target.to_s.split(/[#{Crinja::Util::REGEX_WORD.source}]+/).size
  end

  # Real Jinja2 string filters coerce their target through Python's
  # `soft_str()` internally, which stringifies a (non-strict) Undefined
  # to `''` rather than raising.
  Crinja.filter({old: UNDEFINED, new: UNDEFINED, count: nil}, :replace) do
    if target.undefined?
      ""
    else
      search = arguments["old"].to_s
      replace = arguments["new"]
      count = arguments["count"]

      if count.raw.nil?
        target.as_s_or_safe.gsub(search, replace)
      else
        string = target.to_s
        count.to_i.times do
          running = false
          string = string.sub(search) { running = true; replace }
          break unless running
        end
        string
      end
    end
  end

  # Real Jinja2's `do_trim(value, chars=None)` (jinja2/filters.py) is
  # just `soft_str(value).strip(chars)`: with no `chars=` argument it
  # strips default whitespace, but an explicit `chars=` string switches
  # to Python's own `str.strip(chars)` set-of-characters semantics,
  # stripping ONLY the given characters from both ends and leaving any
  # other leading/trailing characters (e.g. spaces) untouched.
  # crystal-play-0.9.42, differential harness finding: this fork
  # previously ignored `chars=` entirely and always whitespace-stripped
  # (`" ..stays.."|trim(".")` came back `..stays..` instead of ` ..stays`).
  Crinja.filter({chars: nil}, :trim) do
    if target.undefined?
      ""
    else
      chars = arguments["chars"].raw
      string = target.as_s_or_safe
      chars.nil? ? string.strip : string.strip(chars.to_s)
    end
  end

  # Matches Python's own `textwrap.wrap` (what real Ansible's Jinja2
  # `wordwrap` filter actually calls): greedily PACKS WHOLE WORDS onto
  # each line up to `width`, only breaking WITHIN a word when that one
  # word alone exceeds `width` (governed by `break_long_words`). The
  # previous implementation instead chopped the source line into fixed
  # `width`-sized character chunks unconditionally, only trying (weakly)
  # to backtrack to a space *within that already-truncated chunk* -
  # completely different output shape for anything but single-character
  # "words". Found benchmarking robertdebock.functions: `"Extra spaces."
  # | wordwrap(5)` real Ansible gives "Extra\nspace\ns." (whole word
  # "Extra" fits exactly in one line; "spaces." doesn't fit so it's
  # split at the width boundary) - this filter previously gave
  # "\nExtr\na spa\nces. " instead.
  Crinja.filter({width: 79, break_long_words: true, wrapstring: nil}, :wordwrap) do
    width = arguments["width"].to_i
    break_long_words = arguments["break_long_words"].truthy?
    wrapstring = arguments.fetch("wrapstring", "\n").to_s
    width = 1 if width < 1

    String.build do |io|
      first_source_line = true
      target.as_s.each_line do |line|
        io << wrapstring unless first_source_line
        first_source_line = false

        wrapped_lines = [] of String
        current = String::Builder.new

        line.split.each do |word|
          while break_long_words && word.size > width
            if current.bytesize > 0 && current.bytesize < width
              # A word continuation onto a non-empty line needs its own
              # separating space counted against the remaining width
              # (real textwrap: "A" + "regular"[...width] wrapped at 5
              # gives "A reg", not "Aregu" - the space between the
              # already-accumulated "A" and the word piece IS part of
              # the width budget). If only the separator itself fits
              # (remaining == 0), the line still ends with a trailing
              # space and none of the word - real textwrap does this
              # too ("with" + "integers."[...5] wrapped at 5 gives
              # "with ", not "with").
              remaining = width - current.bytesize - 1
              current << ' '
              if remaining > 0
                current << word[0, remaining]
                word = word[remaining..-1]
              end
              wrapped_lines << current.to_s
              current = String::Builder.new
            elsif current.bytesize > 0
              wrapped_lines << current.to_s
              current = String::Builder.new
            else
              wrapped_lines << word[0, width]
              word = word[width..-1]
            end
          end

          if current.bytesize == 0
            current << word
          elsif current.bytesize + 1 + word.size <= width
            current << ' ' << word
          else
            wrapped_lines << current.to_s
            current = String::Builder.new
            current << word
          end
        end
        wrapped_lines << current.to_s if current.bytesize > 0
        wrapped_lines << "" if wrapped_lines.empty?

        io << wrapped_lines.join(wrapstring)
      end
    end
  end
end
