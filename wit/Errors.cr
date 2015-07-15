module Wit
  class ParseError < Exception
    getter lineno, colno

    def initialize(lineno, colno, msg)
      @lineno = lineno
      @colno = colno
      super msg
    end
  end

  class LexError < ParseError
  end

  class EOFError < ParseError
    def initialize(lineno, colno)
      super lineno, colno, "unexpected EOF"
    end
  end
end
