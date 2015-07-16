require "./Errors.cr"

module Wit
  module Scanner
    PRECMOD = 4

    enum TokenType
      # NOTE: These tokens are sorted for efficient precedence comparisons.
      # precedence(token) = token.value % PRECMOD

      LShift # 0
      Plus # 1
      Star # 2
      Amp # 3
      RShift # 0
      Minus # 1
      Slash # 2
      Pipe # 3
      NullOp0 # null op for filling in hole
      NullOp1 # and again
      Percent # 2
      Caret # 3

      OpGuard

      Id
      Integer
      Float
      Char
      Dot
      Eq
      Colon
      Assign
      Comma
      Semic
      Lparen
      Rparen
      Lbr
      Rbr
      EOF

      Export
      Var
      As
      Begin
      End

      # Is this an operator?
      def op?
        self.value < TokenType::OpGuard.value
      end

      # Is this an unary operator?
      def unaryop?
        [TokenType::Amp, TokenType::Minus].includes? self
      end
    end

    class Token
      getter type, value, lineno, colno

      def initialize(lineno, colno, type, value)
        @type = type
        @value = value
        @lineno = lineno
        @colno = colno
      end

      # For debugging.
      def to_s
        "Token #{@type} '#{@value.gsub('\'', "\\\'")}', #{@lineno}:#{@colno}"
      end
    end

    class Scanner
      getter lineno, colno

      # A hash of keywords and their token types.
      @@kw = {"begin" => TokenType::Begin, "end" => TokenType::End,
              "var" => TokenType::Var, "export" => TokenType::Export,
              "as" => TokenType::As}

      def initialize
        @lineno = 1
        @colno = 0
        # The "backups".
        # Used to save the start of a token.
        @blineno = @bcolno = 0
        @look = ' '
        self.getc
      end

      # Read a character from stdin
      def getc
        chr = STDIN.read_char
        if chr
          @look = chr
        else
          raise EOFError.new @lineno, @colno
        end
        @colno += 1
      end

      # Is the current character a letter?
      def alpha?
        @look.alpha?
      end

      # Is the current character a digit?
      def digit?
        @look.digit?
      end

      # Is the current character in the range [A-Za-z0-9]?
      def alnum?
        @look.alphanumeric?
      end

      # Can the current character be in an identifier?
      def idchar?
        self.alnum? || @look == '_'
      end

      # Skip whitespace and comments.
      def skipwhite
        while [' ', '\t', '\n', '#'].includes? @look
          if @look == '\n'
            @lineno += 1
            @colno = 0
          end
          if @look == '#'
            # Read the rest of the line.
            self.getc until @look == '\n'
          else
            self.getc
          end
        end
      end

      # Returns a new token with saved position.
      def token(type, value="")
        Token.new @blineno, @bcolno, type, value
      end

      def next
        self.skipwhite
        # Save the starting position.
        @blineno, @bcolno = @lineno, @colno
        if self.alpha?
          # Identifier.
          id = String.build do |ss|
            while self.idchar?
              ss << @look
              self.getc
            end
          end
          self.token @@kw.fetch(id, TokenType::Id), id
        elsif self.digit?
          # Number.
          val = String.build do |ss|
            while self.digit? || @look == '.'
              ss << @look
              self.getc
            end
          end
          # Numeric suffixes.
          if @look == 'l'
            val += @look
            self.getc
          end
          # Determine whether it's a float or integer.
          type = if val.includes? '.'
            TokenType::Float
          else
            TokenType::Integer
          end
          self.token type, val
        elsif @look == ':'
          # Colon or assignment.
          self.getc
          if @look == '='
            self.getc
            self.token TokenType::Assign, ":="
          else
            self.token TokenType::Colon, ":"
          end
        elsif @look == '\''
          # Character literal.
          self.getc
          if @look == '\\'
            # Escape sequence.
            self.getc
            esc = true
          else
            esc = false
          end
          chr = @look
          self.getc
          raise LexError.new @lineno, @colno, "unterminated char literal" \
            if @look != '\''
          if esc
            # Generate the escaped character.
            chr = case chr
            when 'n'
              '\n'
            when 't'
              '\t'
            when 'r'
              '\r'
            else
              raise LexError.new @lineno, @colno, "invalid escape sequence \
                \\#{chr}"
            end
          end
          self.getc
          self.token TokenType::Char, chr.to_s
        else
          # Lex a simple token.
          type = case @look
          when ','
            TokenType::Comma
          when ';'
            TokenType::Semic
          when '('
            TokenType::Lparen
          when ')'
            TokenType::Rparen
          when '['
            TokenType::Lbr
          when ']'
            TokenType::Rbr
          when '+'
            TokenType::Plus
          when '-'
            TokenType::Minus
          when '*'
            TokenType::Star
          when '&'
            TokenType::Amp
          when '|'
            TokenType::Pipe
          when '^'
            TokenType::Caret
          else
            raise LexError.new @lineno, @colno, "invalid token"
          end
          chr = @look
          self.getc
          self.token type, chr.to_s
        end
      end
    end
  end
end
