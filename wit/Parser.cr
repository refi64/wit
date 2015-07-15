require "./Scanner"
require "./Errors"
require "./Codegen"

module Wit
  module Parser
    class Object
    end

    class Variable < Object
      setter info
      getter name, typ, export, info

      def initialize(@name, @typ, @export)
        @info = nil
      end
    end

    abstract class Proc < Object
      getter ret, args
    end

    class BuiltinProc < Proc
      getter procinfo

      def initialize(@sym, @ret, @args)
        @procinfo = Codegen::X64BuiltinProcInfo.new sym
      end
    end

    abstract class Type < Object
      abstract def tystr
    end

    class BuiltinType < Type
      getter typeinfo, sym

      def initialize(@sym)
        @typeinfo = Codegen::X64BuiltinTypeInfo.new sym
      end

      def ==(other)
        other.is_a?(BuiltinType) && @sym == other.sym
      end

      def tystr
        @sym.to_s
      end
    end

    class PointerType < Type
      getter base

      def initialize(@base)
      end

      def ==(other)
        other.is_a?(PointerType) && @base == other.base
      end

      def tystr
        "#{base.tystr}*"
      end
    end

    abstract class Item
      abstract def typ
      abstract def addressable?
    end

    class ConstItem < Item
      getter typ, value

      def initialize(@typ, @value)
      end

      def addressable?
        false
      end
    end

    class RegItem < Item
      getter reg, size, typ

      def initialize(@reg, @size, @typ)
      end

      def addressable?
        false
      end
    end

    class MemItem < Item
      getter base, mul, offs, typ

      def initialize(@base, @mul, @offs, @typ)
      end

      def addressable?
        true
      end
    end

    class VoidItem < Item
      def typ
        BuiltinType.new(:Void)
      end

      def addressable?
        false
      end
    end

    class Parser
      def initialize
        @scanner = Scanner::Scanner.new
        @token = Scanner::Token.new 0, 0, Scanner::TokenType::EOF, ""
        @gen = Codegen::X64Generator.new
        @global = true
        @scopes = [{"Byte" => BuiltinType.new(:Byte) as Object,
                    "Char" => BuiltinType.new(:Char) as Object,
                    "Int" => BuiltinType.new(:Int) as Object,
                    "Long" => BuiltinType.new(:Long) as Object}]
        @scopes[0]["write_eln"] = BuiltinProc.new :WriteELn, nil, [] of Object
        #@scopes[0]["writeln"] = BuiltinProc.new :WriteLn, nil, []
        @scopes[0]["d2i"] = BuiltinProc.new :D2I, @scopes[0]["Byte"],
                                            [@scopes[0]["Char"]]
        self.next
      end

      def next
        @token = @scanner.next
      end

      def error(msg, t=@token)
        raise ParseError.new t.lineno, t.colno, msg
      end

      def expect(t)
        self.error "expected #{t}, got #{@token.type}" if @token.type != t
      end

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
        self.error "undeclared identifier #{varname}" unless var
        self.error "#{varname} is not a variable" unless var.is_a? Variable
        var
      end

      def typlookup(typname)
        typ = self.lookup typname
        self.error "undeclared type #{typname}" unless typ
        self.error "#{typname} is not a type" unless typ.is_a? Type
        typ
      end

      def proclookup(procname)
        proc = self.lookup procname
        self.error "undeclared procedure #{procname}" unless proc
        self.error "#{procname} is not a procedure" unless proc.is_a? Proc
        proc
      end

      def check_i(val)
        self.error "cannot use floating point value in bitshift" \
            if val != val.to_i.to_f
      end

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

      def parse_declared_type
        self.expect Scanner::TokenType::Id
        typ = @token.value
        typobj = self.typlookup typ
        self.next
        case @token.type
        when Scanner::TokenType::Lbr
          self.next
          if @token.value == Scanner::TokenType::Rbr
            self.next
            raise "123"
          else
            raise "123"
          end
        when Scanner::TokenType::Star
          self.next
          PointerType.new typobj
        else
          typobj
        end
      end

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

      def parse_call(tgt)
        proc = self.proclookup tgt
        self.next if paren = @token.type == Scanner::TokenType::Lparen
        args = [] of Item
        if paren
          until @token.type == Scanner::TokenType::Rparen
            args.push self.parse_expr
            self.expect Scanner::TokenType::Rparen \
              if @token.type != Scanner::TokenType::Comma
          end
          self.next
        end
        self.error "procedure expects #{proc.args.length} arguments, \
          got #{args.length}" if args.length != proc.args.length
        proc.args.each_with_index do |req, index|
          act = args[index]
          self.error "argument #{index+1} to procedure expected argument of type \
            #{(req as Type).tystr}, got #{act.typ.tystr}" if act.typ != req
        end
        @gen.call proc, args
      end

      def parse_unary
        op = @token
        self.next
        item = self.parse_expr Scanner::UNARY
        res = case op.type
        when Scanner::TokenType::Amp
          self.error "expression is not addressable" if !item.addressable?
          @gen.address item
        when Scanner::TokenType::Minus
          raise "123"
        else
          raise "invalid token type #{op.type} labeled as unary"
        end
        {op, res}
      end

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
          {@token, self.parse_assign_or_call bare: true}
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

      def parse_expr(min_prec=0)
        t, res = self.parse_prim
        self.error "cannot use void value as expression", t if res.is_a? VoidItem

        if @token.type == Scanner::TokenType::As && min_prec == 0
          self.next
          typ = self.parse_declared_type
          res = @gen.cast res, typ
        end

        if @token.type.op?
          while @token.type.op? && (prec = @token.type.value % 4) >= min_prec
            op = @token
            self.next
            rhs = parse_expr min_prec+1
            self.error "incompatible types #{res.typ.tystr} and #{rhs.typ.tystr} \
              in binary operation", op if res.typ != rhs.typ
            res = if res.is_a? ConstItem && rhs.is_a? ConstItem
              ConstItem.new res.typ, self.eval res.value, rhs.value, op
            else
              @gen.op res, rhs, op.type
            end
          end
        end
        res
      end

      def parse_assign_or_call(bare=false)
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
        else
          var = self.lookup id
          if var.is_a? Proc
            self.parse_call id
          else
            self.error "expected assignment or call" unless bare
            @gen.id self.varlookup id
          end
        end
      end

      def parse_block
        while @token.type != Scanner::TokenType::End
          case @token.type
          when Scanner::TokenType::Id
            self.parse_assign_or_call
          else
            self.error "expected statement"
          end
        end
      end

      def parse_program
        @gen.prprolog
        if @token.type == Scanner::TokenType::Var
          @gen.datasect
          self.parse_vardecls
        end
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
