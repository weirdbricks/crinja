module Crinja::Parser
  class CharacterStream
    @reader : Char::Reader
    @position = StreamPosition.new

    def initialize(string)
      @reader = Char::Reader.new(string)
    end

    delegate :current_char, to: @reader

    def rewind
      @reader.pos = 0
    end

    def peek_char(lookahead = 1)
      if lookahead == 0
        @reader.current_char
      elsif lookahead == 1
        @reader.peek_next_char
      elsif lookahead > 1
        original_pos = @reader.pos
        (lookahead - 1).times do
          @reader.next_char
        end
        char = @reader.peek_next_char
        @reader.pos = original_pos
        char
      else
        raise Arguments::Error.new("lookahead must be >= 0, was #{lookahead}")
      end
    end

    # The raw character immediately before current_char (nil at the very
    # start of the stream). Only meaningful for ASCII comparisons: a
    # multi-byte character yields nil rather than any part of its bytes.
    def prev_char : Char?
      pos = @reader.pos
      return nil if pos == 0

      byte = @reader.string.byte_at(pos - 1)
      byte < 128 ? byte.chr : nil
    end

    def next_char : Char
      char = @reader.next_char

      @position.column += 1

      if char == '\n'
        @position.column = 0
        @position.line += 1
      end

      char
    end

    def position
      @position.pos = @reader.pos
      @position.dup
    end
  end

  struct StreamPosition
    property pos : Int32
    property line : Int32
    property column : Int32

    def initialize(@line : Int32 = 1, @column : Int32 = 1, @pos : Int32 = 0)
    end

    def +(other : String)
      self.pos += other.size
      lines = other.split('\n')
      self.line += lines.size - 1
      if lines.size > 1
        self.column = lines.last.size
      else
        self.column += other.size
      end
      self
    end

    def to_s(io)
      io << line << ":" << column
    end

    def inspect(io)
      to_s(io)
      io << "@" << pos
    end
  end
end
