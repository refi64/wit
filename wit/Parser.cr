require "./Scanner"
require "./Errors"
require "./Types"
require "./Codegen"

module Wit
  module Parser
    class Parser
      def initialize
        @scanner = Scanner::Scanner.new
        @token = Scanner::Token.new 0, 0, Scanner::TokenType::EOF, ""
        @gen = Codegen::X64Generator.new
        # This determines whether or not the current scope is the global scope.
        @global = true
        # A list of scopes.
        # [global, nesting0, nesting1, nesting2, ...]
        @scopes = [{"Byte" => BuiltinType.new(:Byte) as Object,
                    "Char" => BuiltinType.new(:Char) as Object,
                    "Int" => BuiltinType.new(:Int) as Object,
                    "Long" => BuiltinType.new(:Long) as Object}]
        @scopes[0]["write_eln"] = BuiltinProc.new :WriteELn, nil, [] of Object
        #@scopes[0]["writeln"] = BuiltinProc.new :WriteLn, nil, []
        @scopes[0]["d2i"] = BuiltinProc.new :D2I, @scopes[0]["Byte"] as Type,
                                            [@scopes[0]["Char"] as Type]
        self.next
      end

      def next
        @token = @scanner.next
      end

      # Shows an error at the given token.
      def error(msg, t=@token)
        raise ParseError.new t.lineno, t.colno, msg
      end

      # Throw an error if the current token is not the expected one.
      def expect(t)
        self.error "expected #{t}, got #{@token.type}" if @token.type != t
      end

      # Lookup an Object
      def lookup(name)
        @scopes.reverse_each do |scope|
          if scope.has_key? name
            return scope[name]
          end
        end
        nil
      end

      def varlookup(varname)
        var = self.lookup varname
        self.error "undeclared identifier #{varname}" if !var
        self.error "#{varname} is not a variable" unless var.is_a? Variable
        var
      end

      def typlookup(typname)
        typ = self.lookup typname
        self.error "undeclared type #{typname}" if !typ
        self.error "#{typname} is not a type" unless typ.is_a? Type
        typ
      end

      def proclookup(procname)
        proc = self.lookup procname
        self.error "undeclared procedure #{procname}" if !proc
        self.error "#{procname} is not a procedure" unless proc.is_a? Proc
        proc
      end

      # Check if the value is an integer (i.e. has no decimal places).
      def check_i(val)
        self.error "cannot use floating point value in bitshift" \
            if val != val.to_i.to_f
      end

      # Evaluate the given expression at compile time.
      def eval(lhs, rhs, op)
        case op.type
        when Scanner::TokenType::Plus
          lhs + rhs
        when Scanner::TokenType::Minus
          lhs - rhs
        when Scanner::TokenType::Star
          lhs * rhs
        when Scanner::TokenType::Slash
          (lhs / rhs).to_i.to_f
        when Scanner::TokenType::Percent
          (lhs.to_i % rhs.to_i).to_f
        when Scanner::TokenType::LShift
          self.check_i lhs
          self.check_i rhs
          (lhs.to_i << rhs.to_i).to_f
        when Scanner::TokenType::RShift
          self.check_i lhs
          self.check_i rhs
          (lhs.to_i >> rhs.to_i).to_f
        else
          raise "invalid op #{@token.type} given to eval"
        end
      end

      # Parse a type specification.
      def parse_declared_type
        self.expect Scanner::TokenType::Id
        typ = @token.value
        base = self.typlookup typ
        self.next
        case @token.type
        when Scanner::TokenType::Lbr
          # An array type.
          self.next
          if @token.value == Scanner::TokenType::Rbr
            self.next
            raise "VLAs not yet implemented"
          else
            size = self.parse_expr
            res = if size.is_a? ConstItem
              ArrayType.new base, size.value.to_i
            else
              self.error "array size must be constant"
            end

            self.expect Scanner::TokenType::Rbr
            self.next
            res
          end
        when Scanner::TokenType::Star
          # A pointer type.
          self.next
          PointerType.new base
        else
          base
        end
      end

      # Parse a sequence of variable declarations.
      def parse_vardecls
        self.next
        vars = {} of String => Variable
        loop do
          export = if @token.type == Scanner::TokenType::Export
            self.error "cannot export non-global variable" unless @global
            self.next
            true
          else
            false
          end
          self.expect Scanner::TokenType::Id
          id = @token.value
          self.next
          self.expect Scanner::TokenType::Colon
          self.next
          typ = self.parse_declared_type
          # Add the variable to the current scope and the variable dictionary.
          vars[id] = @scopes[-1][id] = Variable.new id, typ, export
          break if @token.type != Scanner::TokenType::Comma
          self.next
        end
        if @global
          @gen.emitglobals vars
        else
          @gen.emitlocals vars
        end
      end

      # Parse an integer literal.
      def parse_int_expr
        value = @token.value
        self.next
        typ = case value[-1]
        when 'l'
          "Long"
        else
          "Int"
        end
        ConstItem.new @scopes[0][typ] as Type, value.to_f
      end

      # Parse a function call.
      def parse_call(tgt)
        proc = self.proclookup tgt
        # paren is a variable that determines whether or not the call is
        # parenthesized.
        # Wit uses the Pascal style of being able to omit parenthesis when the
        # procedure takes no arguments.
        self.next if paren = @token.type == Scanner::TokenType::Lparen
        args = [] of Item
        if paren
          # Parse an argument list.
          until @token.type == Scanner::TokenType::Rparen
            args.push self.parse_expr
            self.expect Scanner::TokenType::Rparen \
              if @token.type != Scanner::TokenType::Comma
          end
          self.next
        end
        self.error "procedure expects #{proc.args.length} arguments, \
          got #{args.length}" if args.length != proc.args.length
        # Make sure the argument types are correct.
        proc.args.each_with_index do |req, index|
          act = args[index]
          self.error "argument #{index+1} to procedure expected argument of type \
            #{(req as Type).tystr}, got #{act.typ.tystr}" if act.typ != req
        end
        @gen.call proc, args
      end

      # Parse an index expression..
      def parse_index(base_id)
        base = self.varlookup base_id
        self.error "#{base.typ.tystr} does not support indexing"\
          if !base.typ.indexes?
        self.next
        index = self.parse_expr
        self.error "#{base.typ.tystr} cannot be indexed with #{index.typ.tystr}"\
          if !base.typ.indexes_with? index.typ
        self.expect Scanner::TokenType::Rbr
        self.next
        @gen.index (@gen.id base), index
      end

      # Parse an unary operator with an expression.
      def parse_unary
        op = @token
        self.next
        item = self.parse_prim[1]
        res = case op.type
        when Scanner::TokenType::Amp
          self.error "expression is not addressable" if !item.addressable?
          @gen.address item
        when Scanner::TokenType::Minus
          if item.is_a? ConstItem
            ConstItem.new item.typ, -item.value
          else
            @gen.neg item
          end
        else
          raise "invalid token type #{op.type} labeled as unary"
        end
        {op, res}
      end

      # Parse a primitive atom expression.
      # Unlike most parse* functions, this returns a tuple {start token, item}
      # instead of just an item. This is so parse_expr's error messages will be
      # more exact.
      def parse_prim
        case @token.type
        when Scanner::TokenType::Integer
          {@token, self.parse_int_expr}
        when Scanner::TokenType::Char
          res = {@token, ConstItem.new @scopes[0]["Char"] as Type,
                            @token.value[0].ord.to_f}
          self.next
          res
        when Scanner::TokenType::Id
          {@token, self.parse_id_with_suffix bare: true}
        when Scanner::TokenType::Lparen
          self.next
          res = {@token, self.parse_expr}
          self.expect Scanner::TokenType::Rparen
          self.next
          res
        else
          if @token.type.unaryop?
            self.parse_unary
          else
            self.error "expected expression"
          end
        end
      end

      # Parse an expression.
      def parse_expr(min_prec=-1)
        t, res = self.parse_prim
        self.error "cannot use void value as expression", t if res.is_a? VoidItem

        # XXX: casts should have the highest precedence, other than unary
        # operators.
        if @token.type == Scanner::TokenType::As
          self.next
          typ = self.parse_declared_type
          res = if res.is_a? ConstItem
            res.retype typ
          else
            @gen.cast res, typ
          end
        end

        if @token.type.op?
          min_prec = @token.type.prec if min_prec == -1
          # For @token.type.value, see Scanner.cr.
          while @token.type.op? && (prec = @token.type.prec) >= min_prec
            op = @token
            self.next
            rhs = self.parse_expr min_prec+1
            # Make sure both types are equal.
            self.error "type #{res.typ.tystr} does not support this binary \
              operation" if !res.typ.supports? op.type
            self.error "incompatible types #{res.typ.tystr} and #{rhs.typ.tystr} \
              in binary operation", op if !res.typ.supports_with? op.type, rhs.typ
            # If they are both constant, evaluate the expression at compile time.
            res = if res.is_a? ConstItem && rhs.is_a? ConstItem
              ConstItem.new res.typ, self.eval res.value, rhs.value, op
            else
              if res.typ != rhs.typ
                res, rhs = @gen.eqtyp res, rhs
              end
              # XXX:
              # Given variable+constant_0+constant_1+constant_N..., this will
              # generatd N instructions, even though the entire right-hand-side is
              # entirely constant.
              @gen.op res, rhs, op.type
            end
          end
        end
        res
      end

      # Parse an assignment, function call, or index.
      # bare determines whether an error should occur if just a plain expression
      # is found.
      def parse_id_with_suffix(bare=false)
        id = @token.value
        self.next
        case @token.type
        when Scanner::TokenType::Assign
          tgt = self.varlookup id
          tok = @token
          self.next
          expr = self.parse_expr
          self.error "incompatible types #{tgt.typ.tystr} and #{expr.typ.tystr} \
            in assignment", tok if tgt.typ != expr.typ
          @gen.assign tgt, expr
        when Scanner::TokenType::Lparen
          self.parse_call id
        when Scanner::TokenType::Lbr
          self.parse_index id
        else
          var = self.lookup id
          if var.is_a? Proc
            self.parse_call id
          else
            self.error "expected assignment or call" if !bare
            @gen.id self.varlookup id
          end
        end
      end

      # Parse a block.
      def parse_block
        while @token.type != Scanner::TokenType::End
          case @token.type
          when Scanner::TokenType::Id
            self.parse_id_with_suffix
          else
            self.error "expected statement"
          end
        end
      end

      # Parse the entire program.
      def parse_program
        @gen.prprolog
        if @token.type == Scanner::TokenType::Var
          @gen.datasect
          self.parse_vardecls
        end
        # End of globals.
        @global = false
        @gen.isect
        self.expect Scanner::TokenType::Begin
        self.next
        @gen.mainprolog
        self.parse_vardecls if @token.type == Scanner::TokenType::Var
        self.parse_block
        self.expect Scanner::TokenType::End
        @gen.mainepilog
        @gen.prepilog
        # Make sure EOF was reached.
        begin
          self.next
        rescue ex : EOFError
        rescue ex : ParseError
          raise ex
        else
          self.error "expected EOF"
        end
      end
    end
  end
end
