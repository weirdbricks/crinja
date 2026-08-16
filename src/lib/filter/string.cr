require "xml"

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
    xml = XML.parse_html target.to_s
    xml.inner_text.gsub(/\s+/, " ").strip
  end

  Crinja.filter(:format) { sprintf target.to_s, arguments.varargs }

  Crinja.filter({
    width:       4,
    indentfirst: false,
  }, :indent) do
    indent = " " * arguments["width"].to_i
    nl = "\n" + indent
    string = target.to_s
    string = indent + string if arguments["indentfirst"].truthy?
    string.gsub(/\n/, nl)
  end

  Crinja.filter(:string) { env.stringify target }

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

  Crinja.filter(:trim) do
    if target.undefined?
      ""
    else
      target.as_s_or_safe.strip
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

module Crinja::Util
  REGEX_WORD = /\s\-\(\{\[\</
end
