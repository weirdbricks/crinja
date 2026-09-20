# :nodoc:
module Crinja::Parser
  abstract class BaseLexer
    # :nodoc:
    alias Kind = Token::Kind

    SPECIAL_CONSTANTS = {
      "true"  => Kind::BOOL,
      "false" => Kind::BOOL,
      "none"  => Kind::NONE,
    }.tap do |hash|
      # because `True` equaling to false causes confusion, it is possible to write these constants
      # in camel case. However lower case is preferred.
      hash.each { |key, value| hash[key.camelcase] = value }
    end

    getter config, stream

    def initialize(config : Crinja::Config, input : String)
      initialize(config, CharacterStream.new(input))
    end

    def initialize(@config : Crinja::Config, @stream : CharacterStream = CharacterStream.new)
      @token = Token.new
      @buffer = IO::Memory.new
    end

    delegate :next_char, :current_char, :peek_char, to: stream

    abstract def next_token : Token

    def tokenize
      tokens = [] of Token

      while t = next_token
        tokens << t
        break if t.kind == Kind::EOF
      end

      @stream.rewind

      tokens
    end

    # Overridden by lexers that recognize configurable start delimiter
    # strings (see TemplateLexer): `consume_fixed` stops scanning fixed
    # text wherever a start delimiter begins. The base implementation
    # never breaks - the expression lexer consumes fixed boundaries
    # through the template lexer instead.
    def at_delimiter_start?(offset = 0) : Bool
      false
    end

    def consume_fixed
      @buffer.clear
      @buffer << current_char

      while true
        case char = next_char
        when Char::ZERO
          break
        else
          break if at_delimiter_start?
          @buffer << char
        end
      end

      @buffer.to_s
    end

    def consume_name(with_special_constants = true)
      @buffer.clear
      @buffer << current_char

      while true
        case char = next_char
        when .alphanumeric?, '_'
          @buffer << char
        else
          break
        end
      end

      @token.value = @buffer.to_s
      @token.kind = Kind::IDENTIFIER

      if with_special_constants && SPECIAL_CONSTANTS.has_key?(@token.value)
        @token.kind = SPECIAL_CONSTANTS[@token.value]
      end
    end

    def consume_string
      @buffer.clear
      escaped = false
      delimiter = current_char

      while true
        char = next_char

        if char == Char::ZERO
          raise "Unterminated string literal"
        end

        if escaped
          escaped = false

          case char
          when 'n'
            @buffer << '\n'
          when '"', '\''
            @buffer << char
          when Symbol::STRING_ESCAPE
            @buffer << Symbol::STRING_ESCAPE
          else
            # Real Python/Jinja2 string literals pass an unrecognized
            # escape straight through as literal text (`'\1'` is the two
            # characters `\` and `1` - not a real Python string escape,
            # no error) - needed for real Ansible regex backreference
            # syntax (`regex_search(pattern, '\1')`).
            @buffer << Symbol::STRING_ESCAPE
            @buffer << char
          end
        else
          escaped = false
          case char
          when delimiter
            next_char
            break
          when Symbol::STRING_ESCAPE
            escaped = true
          else
            @buffer << char
          end
        end
      end

      @buffer.to_s
    end

    # Real Jinja2's numeric grammar lives in two regexes in
    # jinja2/lexer.py (`integer_re`/`float_re`, verified directly against
    # the installed 3.1.6 source): integers are
    # `0b(_?[0-1])+ | 0o(_?[0-7])+ | 0x(_?[\da-f])+ | [1-9](_?\d)* |
    # 0(_?0)*` (case-insensitive, so `0X`/`0O`/`0B` prefixes work too)
    # and floats are digits-with-underscore-groups plus either an
    # optional fractional part followed by an `e[+-]?` exponent or a
    # required fractional part - underscores are digit-group separators
    # ONLY ever between two digits (never leading/trailing/doubled,
    # mirroring Python's own numeric-literal rules). This lexer used to
    # accept only plain decimal digits: every one of those forms raised
    # `Invalid number. Found char: ...` - found via a differential
    # harness running real Jinja2 3.1.6's own upstream test suite
    # against this fork (`{{ 12_34_56 }}`, `{{ 1e0 }}`, `{{ 0x123abc }}`,
    # `{{ 0o123 }}`, `{{ 0b1001_1111 }}` etc.).
    #
    # Underscores are validated but never stored in the token value
    # (real Jinja2 strips nothing - Python's own `int(text, 0)` /
    # `float(text)` accept them natively); the parser converts the
    # base-prefixed forms via Crystal's `to_i64(prefix: true)`, which
    # handles `0x`/`0o`/`0b` exactly like Python's `int(text, 0)`.
    def consume_numeric(allow_float = true)
      @buffer.clear
      is_float = false
      has_exponent = false

      @buffer << current_char
      prev = current_char

      base = current_char == '0' ? base_prefix(peek_char) : nil
      prefix_char = peek_char
      if base
        @buffer << next_char
        # the base prefix MUST be followed by digits - but Jinja2's own
        # regex (`0b(_?[0-1])+` etc.) allows ONE underscore between the
        # prefix and the first digit (`0b_1` renders 1), unlike Python's
        # own numeric literals; a bare `0x`/`0o8`/`0b__1` is invalid
        # (real Jinja2 fails them as `expected token 'end of print
        # statement'`)
        unless base_digit?(peek_char, base) || (peek_char == '_' && base_digit?(peek_char(2), base))
          raise "Invalid number. Found char: '#{peek_char}'(#{peek_char.ord})"
        end
      end

      while true
        char = next_char

        if base
          if char == '_'
            # an underscore separator is only valid between two digits
            # of the base, or (once, Jinja2's own `_?`) right after the
            # prefix - never doubled (`0b__1` is invalid)
            unless (prev == prefix_char || base_digit?(prev, base)) && base_digit?(peek_char, base)
              raise "Invalid number. Found char: '#{char}'(#{char.ord})"
            end
          elsif base_digit?(char, base)
            @buffer << char
          else
            break
          end
          prev = char
          next
        end

        case char
        when .number?
          @buffer << char
        when '_'
          # Python's own underscore rules, which Jinja2's regexes mirror
          # via `_?`/`(_?\d)*`: a separator only ever sits BETWEEN two
          # digits - `1_`, `_1` (impossible here, the token starts on a
          # digit), `1__2` and `1e+_1` are all rejected (real Jinja2
          # fails them as `expected token 'end of print statement'`).
          unless prev.number? && peek_char.number?
            raise "Invalid number. Found char: '#{char}'(#{char.ord})"
          end
        when '.'
          # Django-style numeric attribute access (`foo.0`, `foo.0.0`):
          # when the number token starts right after a member-access dot,
          # the fractional part must not merge in. Real Jinja2's float_re
          # (jinja2/lexer.py 3.1.6) carries a `(?<!\.)` lookbehind for
          # exactly this, so `].0.0` lexes as `.` `0` `.` `0` and
          # parse_subscript (jinja2/parser.py) turns each dot+integer
          # into a chained Getitem - real Jinja2 renders
          # `{{ [[1]].0.0 }}` as `1`. Without it this lexer consumed the
          # second `.0` into one FLOAT "0.0" and the parser failed with
          # `Expected IDENTIFIER, got FLOAT` (differential-harness
          # finding). With the fractional part forbidden the number can
          # no longer continue past the dot, so the token simply ends
          # here - the integer_re-only match real Jinja2 falls back to.
          break unless allow_float

          raise "Invalid floating point number" if is_float

          # make sure the next char is numeric, otherwise the point can be a member operator
          break unless peek_char.number?

          @buffer << char
          is_float = true
        when 'e', 'E'
          # integer_re has no exponent part, so a number that started
          # right after a member-access dot also ends before one -
          # same `(?<!\.)` lookbehind reasoning as the '.' case above.
          break unless allow_float

          # exponent part of real Jinja2's `float_re`:
          # `e[+\-]?(\d+_)*\d+` - a bare `1e` or `1e+` (no exponent
          # digits) is not a number and is rejected, exactly like real
          # Jinja2's syntax error on `{{ 1e }}`
          raise "Invalid floating point number" if has_exponent
          is_float = true
          has_exponent = true
          @buffer << char
          if peek_char.in?('+', '-')
            raise "Invalid number. Found char: '#{char}'(#{char.ord})" unless peek_char(2).number?
            @buffer << next_char
          elsif !peek_char.number?
            raise "Invalid number. Found char: '#{char}'(#{char.ord})"
          end
        when ' ', '\n', '\t', '\r', Char::ZERO, Symbol::RIGHT_PAREN, Symbol::RIGHT_BRACKET, Symbol::RIGHT_CURLY, Symbol::DICT_ASSIGN, Symbol::COMMA, Symbol::PIPE,
             '~', '+', '-', '*', '/', '%', '=', '>', '<', '!'
          break
        else
          raise "Invalid number. Found char: '#{char}'(#{char.ord})"
        end
        prev = char
      end

      {is_float ? Kind::FLOAT : Kind::INTEGER, @buffer.to_s}
    end

    private def base_prefix(char : Char) : Int32?
      case char
      when 'x', 'X' then 16
      when 'o', 'O' then 8
      when 'b', 'B' then 2
      end
    end

    private def base_digit?(char : Char, base : Int32) : Bool
      case base
      when 16 then char.hex?
      when 8  then char.in?('0'..'7')
      else char.in?('0', '1')
      end
    end

    def skip_whitespace
      # Char#whitespace? (Unicode White_Space property), not a fixed
      # ASCII-only [' ', '\t', '\n', '\r'] set - real Jinja2 (Python's
      # `re` module, Unicode-mode by default) treats a much broader
      # class as whitespace, including U+00A0 NO-BREAK SPACE. Found via
      # a real Galaxy role (buluma.bind's own etc_named.conf.j2) whose
      # `{{ bind_dnssec_validation }}` had accidentally picked up a
      # U+00A0 right after `{{` (a common copy/paste artifact) - real
      # ansible-playbook rendered it fine; this lexer's old ASCII-only
      # check didn't recognize the NBSP as whitespace-before-token at
      # all, corrupting the expression parse ("Not implemented
      # expression value").
      whitespace = String.build do |io|
        while true
          if current_char.whitespace?
            @skipped_whitespace = true
            io << current_char
            next_char
          else
            break
          end
        end
      end
      if whitespace.empty?
        nil
      else
        whitespace
      end
    end

    def raise(message : String)
      ::raise(Crinja::TemplateSyntaxError.new(message).at(stream.position, stream.position))
    end
  end
end
