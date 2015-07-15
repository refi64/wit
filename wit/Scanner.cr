require "./Errors.cr"

module Wit
  module Scanner
    UNARY = 4

    enum TokenType
      # NOTE: These tokens are sorted for efficient precedence comparisons.
      # precedence(token) = token.value % 4
      # unary precedence = 4 (highest)

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

      def op?
        self.value < TokenType::OpGuard.value
      end

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

      def to_s
        "Token #{@type} '#{@value.gsub('\'', "\\\'")}', #{@lineno}:#{@colno}"
      end
    end

    class Scanner
      getter lineno, colno

      @@kw = {"begin" => TokenType::Begin, "end" => TokenType::End,
              "var" => TokenType::Var, "export" => TokenType::Export,
              "as" => TokenType::As}

      def initialize
        @lineno = 1
        @colno = 0
        @blineno = @bcolno = 0
        @look = ' '
        self.getc
      end

      def getc
        chr = STDIN.read_char
        if chr
          @look = chr
        else
          raise EOFError.new @lineno, @colno
        end
        @colno += 1
      end

      def alpha?
        @look.alpha?
      end

      def digit?
        @look.digit?
      end

      def alnum?
        @look.alphanumeric?
      end

      def idchar?
        self.alnum? || @look == '_'
      end

      def skipwhite
        while [' ', '\t', '\n', '#'].includes? @look
          if @look == '\n'
            @lineno += 1
            @colno = 0
          end
          if @look == '#'
            self.getc until @look == '\n'
          else
            self.getc
          end
        end
      end

      def token(type, value="")
        Token.new @blineno, @bcolno, type, value
      end

      def next
        self.skipwhite
        @blineno, @bcolno = @lineno, @colno
        if self.alpha?
          id = String.build do |ss|
            while self.idchar?
              ss << @look
              self.getc
            end
          end
          self.token @@kw.fetch(id, TokenType::Id), id
        elsif self.digit?
          val = String.build do |ss|
            while self.digit? || @look == '.'
              ss << @look
              self.getc
            end
          end
          if @look == 'l'
            val += @look
            self.getc
          end
          type = if val.includes? '.'
            TokenType::Float
          else
            TokenType::Integer
          end
          self.token type, val
        elsif @look == ':'
          self.getc
          if @look == '='
            self.getc
            self.token TokenType::Assign, ":="
          else
            self.token TokenType::Colon, ":"
          end
        elsif @look == '\''
          self.getc
          if @look == '\\'
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
