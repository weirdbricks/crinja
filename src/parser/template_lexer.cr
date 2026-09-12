class Crinja::Parser::TemplateLexer < Crinja::Parser::BaseLexer
  struct State
    getter end_string, end_kind, name

    def initialize(@name : String, @end_string : String, @end_kind : Kind)
    end

    def to_s(io : IO)
      io << "<State:#{name}>"
    end
  end

  @expression_lexer : ExpressionLexer?
  @is_raw = false

  # The lexer states are built from the environment's configurable
  # delimiter strings (Jinja2's `block_start_string`/`block_end_string`/
  # `variable_start_string`/`variable_end_string`/`comment_start_string`/
  # `comment_end_string` options) instead of hard-coded `{`/`%`/`#`
  # symbols, so a template can use non-default delimiters (e.g. `{{`
  # colliding with the templated file's own native syntax).
  getter root_state, expression_state, tag_state, note_state

  def initialize(config : Crinja::Config, input : String)
    initialize(config, CharacterStream.new(input))
  end

  def initialize(config : Crinja::Config, stream : CharacterStream)
    super(config, stream)

    @root_state = State.new "root", "", Kind::EOF
    @expression_state = State.new "expression", config.variable_end_string, Kind::EXPR_END
    @tag_state = State.new "tag", config.block_end_string, Kind::TAG_END
    @note_state = State.new "note", config.comment_end_string, Kind::NOTE

    @stack = [@root_state]
    @state = @root_state
  end

  def expression_lexer
    @expression_lexer ||= ExpressionLexer.new(self.config, stream)
  end

  setter expression_lexer

  def next_token : Token
    @token.reset(stream.position)

    state = @stack.last

    if state == root_state
      next_token_root
    elsif state == expression_state
      if expression_lexer.stack_closed? && check_for_end(state)
        @stack.pop
      else
        @token = expression_lexer.next_token
      end
    elsif state == tag_state
      if check_for_end(state)
        @stack.pop
      else
        next_token_tag
      end
    elsif state == note_state
      # skip
    else
      raise "unreachable"
    end

    @token.dup
  end

  # Matches the longest configured start delimiter
  # (`variable_start_string`/`block_start_string`/`comment_start_string`)
  # at the current stream position (plus *offset*). Returns the matched
  # string with its token kind and lexer state, or `nil`. Empty delimiter
  # strings never match (an empty delimiter would loop the lexer forever).
  private def match_start_delimiter(offset = 0)
    candidates = {
      {config.variable_start_string, Kind::EXPR_START, expression_state},
      {config.block_start_string, Kind::TAG_START, tag_state},
      {config.comment_start_string, Kind::NOTE, note_state},
    }

    match = nil
    candidates.each do |candidate|
      start_string = candidate[0]
      next if start_string.empty?
      next if match && match[0].size >= start_string.size
      match = candidate if matches_at?(start_string, offset)
    end
    match
  end

  # Matches the longest configured end delimiter at the current stream
  # position (plus *offset*), or `nil`.
  private def match_end_delimiter(offset = 0)
    candidates = [config.variable_end_string, config.block_end_string, config.comment_end_string]

    match = nil
    candidates.each do |end_string|
      next if end_string.empty?
      next if match && match.size >= end_string.size
      match = end_string if matches_at?(end_string, offset)
    end
    match
  end

  def matches_at?(string : String, offset = 0) : Bool
    string.chars.each_with_index do |char, i|
      return false if char != peek_char(offset + i)
    end
    true
  end

  # Hook for `BaseLexer#consume_fixed`: fixed text ends wherever a
  # configured start delimiter begins.
  def at_delimiter_start?(offset = 0) : Bool
    !match_start_delimiter(offset).nil?
  end

  def next_token_root
    if @is_raw
      return next_token_raw
    end

    if current_char == Char::ZERO
      @token.kind = Kind::EOF
    elsif start = match_start_delimiter
      start_string, kind, state = start
      @token.kind = kind
      @stack << state

      if kind == Kind::NOTE
        @token.value = consume_note
        return
      end

      @token.value = String.build do |io|
        start_string.size.times do
          io << current_char
          next_char
        end
      end

      if current_char == Symbol::TRIM_WHITESPACE
        @token.value += current_char
        @token.trim_left = true
        next_char
      elsif current_char == Symbol::PLUS && @token.kind == Kind::TAG_START
        # `{%+` - Jinja2's explicit "do NOT apply lstrip_blocks" override
        # (only valid on block tags, not on `{{` expressions / `{#` notes).
        @token.value += current_char
        @token.plus_left = true
        next_char
      end
    else
      @token.kind = Kind::FIXED
      @token.value = consume_fixed
      return
    end
  end

  def next_token_raw
    @token.value = consume_raw
    @token.kind = Kind::FIXED
    @is_raw = false
  end

  def consume_raw
    @buffer.clear

    while true
      char = current_char
      break if char == Char::ZERO
      if matches_at?(config.block_start_string) &&
         peek_string?(Symbol::RAW_END, config.block_start_string.size)
        break
      end

      @buffer << char
      next_char
    end

    @buffer.to_s
  end

  def peek_string?(string, offset = 1)
    offset = peek_for_whitespace_offset(offset)
    string.chars.each_with_index(offset) do |char, i|
      return false if char != peek_char(i)
    end
    true
  end

  def next_token_tag
    @token.location = stream.position

    if @token.kind == Kind::TAG_START
      # if last token is TAG_START, read tag name
      @token.whitespace_before = skip_whitespace
      consume_name(with_special_constants: false)

      if @token.value == Symbol::RAW_START
        @is_raw = true
      elsif @token.value == Symbol::RAW_END
        @is_raw = false
      end
    else
      @token = expression_lexer.next_token
    end
  end

  def consume_note
    String.build do |io|
      config.comment_start_string.each_char do |char|
        io << char
        next_char
      end

      if current_char == Symbol::TRIM_WHITESPACE
        @token.trim_left = true
      end

      while current_char
        if check_for_end(@stack.last)
          @stack.pop
          break
        end

        io << current_char
        next_char
      end
    end
  end

  def peek_for_whitespace_offset(offset = 1)
    while peek_char(offset).whitespace?
      offset += 1
    end
    offset
  end

  # check if current scope closes
  def check_for_end(current_scope)
    trim_whitespace = false
    plus_whitespace = false

    whitespace = peek_for_whitespace_offset(0)

    lookahead = 0

    if peek_char(whitespace + lookahead) == Symbol::TRIM_WHITESPACE
      trim_whitespace = true
      lookahead += 1
    elsif peek_char(whitespace + lookahead) == Symbol::PLUS
      # `+%}` - force-disable trim_blocks on the right. Only meaningful for tags
      # (`+}}` is not a real Jinja2 form).
      plus_whitespace = true
      lookahead += 1
    end

    if peek_char(whitespace + lookahead) == Char::ZERO
      raise "Unterminated #{@stack.last.name}"
    end

    end_string = match_end_delimiter(whitespace + lookahead)
    return false if end_string.nil?

    @token.value = String.build do |io|
      io << Symbol::TRIM_WHITESPACE if trim_whitespace
      io << Symbol::PLUS if plus_whitespace && end_string == config.block_end_string
      io << end_string
    end

    if end_string != current_scope.end_string
      raise "Terminated #{@stack.last} with '#{@token.value}'"
    end

    @token.kind = current_scope.end_kind

    @token.whitespace_before = String.build do |io|
      whitespace.times { io << current_char; next_char }
    end

    (lookahead + end_string.size).times { next_char }

    if trim_whitespace
      @token.trim_right = true
    end

    if plus_whitespace && end_string == config.block_end_string
      @token.plus_right = true
    end

    true
  end
end
