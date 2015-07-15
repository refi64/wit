module Wit
  module Codegen
    PTRSIZE = 8

    enum Reg
      Rax
      Rbx
      Rcx
      Rdx
      Rsi
      Rdi
      Rsp
      Rbp
      R8
      R9
      R10
      R11

      def reg64?
        self.value >= 8
      end

      def regsz(sz)
        reg64 = self.reg64?
        base = self.to_s.downcase
        case sz
        when 1
          reg64 ? base + 'b' : base[1].to_s + 'l'
        when 2
          reg64 ? base + 'w' : base[1..2]
        when 4
          reg64 ? base + 'd' : "e" + base[1..2]
        when 8
          base
        else
          raise "invalid size #{sz} given to Reg.regsz"
        end
      end
    end

    class X64BuiltinTypeInfo
      getter size

      def initialize(sym)
        @size = case sym
        when :Byte, :Char
          1
        when :Int
          4
        when :Long
          8
        else
          raise "invalid type symbol #{sym}"
        end
      end
    end

    class X64VarInfo
      getter global, size, label, offs

      def initialize(@global, @size, @label, @offs)
      end
    end

    class X64BuiltinProcInfo
      getter sym

      def initialize(@sym)
      end
    end

    class X64Generator
      @@allregs = [Reg::Rbx, Reg::Rcx, Reg::Rdx, Reg::Rsi, Reg::Rdi, Reg::R8,
                   Reg::R9, Reg::R10, Reg::R11]

      def initialize
        @totals = [] of Int32
        @usedregs = [] of Reg
      end

      def getszstr(sz)
        case sz
        when 1
          "byte"
        when 2
          "word"
        when 4
          "dword"
        when 8
          "qword"
        else
          raise "invalid size #{sz} given to szstr"
        end
      end

      def emit(line="")
        puts line
      end

      def emittb(line="")
        self.emit "  #{line}"
      end

      def getreg
        reg = @@allregs.select{|reg| !@usedregs.includes? reg}[0]
        @usedregs.push reg
        reg
      end

      def freereg(reg)
        @usedregs.delete reg
      end

      def ofree(maybereg)
        self.freereg maybereg.reg if maybereg.is_a? Parser::RegItem
      end

      def regblock
        yield reg = self.getreg
        self.freereg reg
      end

      def needsregsfor(regs)
        used = regs.select{|reg| @usedregs.includes? reg}
        used.each do |reg|
          self.emittb "push #{reg}"
          @usedregs.push reg
        end
        yield
        used.each do |reg|
          self.emittb "pop #{reg}"
          @usedregs.delete reg
        end
      end

      def tysize(typ)
        case typ
        when Parser::BuiltinType
          typ.typeinfo.size
        when Parser::PointerType
          PTRSIZE
        else
          raise "invalid type #{typ.class} given to tysize"
        end
      end

      def itemstr(item)
        case item
        when Parser::ConstItem
          # to_s will give scientific notation of large numbers
          "%d" % item.value
        when Parser::MemItem
          if item.mul == "1" && item.offs == "0"
            "[#{item.base}]"
          else
            "[#{item.base}*#{item.mul}+#{item.offs}]"
          end
        when Parser::RegItem
          item.reg.regsz item.size
        else
          raise "invalid item #{item.class} given to itemstr"
        end
      end

      def prprolog
        self.emit "global _start"
        self.emit
      end

      def datasect
        self.emit "section .data"
        self.emittb "wit$newl: db 10"
      end

      def isect
        self.emit "section .text"
      end

      def prepilog
      end

      def emitglobals(globals)
        labels = {} of String => String
        globals.each do |name, var|
          labels[name] = var.export ? name : "wit$global$#{name}"
          self.emittb "global #{labels[name]}" if var.export
        end
        globals.each do |name, var|
          sz = self.tysize var.typ
          var.info = X64VarInfo.new true, sz, labels[name], 0
          sp = case sz
          when 1
            "db"
          when 2
            "dw"
          when 4
            "dd"
          when 8
            "dq"
          else
            raise "invalid type size: #{sz}"
          end
          self.emittb "#{labels[name]}: #{sp} 0"
        end
      end

      def emitlocals(locals)
        total = 0
        locals.values.each do |var|
          sz = self.tysize var.typ
          total += sz
          var.info = X64VarInfo.new false, sz, "", total
        end
        @totals.push total
        return unless total != 0
        self.emittb "push rbp"
        self.emittb "mov rbp, rsp"
        self.emittb "sub rsp, #{total}"
      end

      def id(id)
        info = id.info as X64VarInfo
        if info.global
          Parser::MemItem.new info.label, "1", "0", id.typ
        else
          Parser::MemItem.new "rbp", "1", "-#{info.offs}", id.typ
        end
      end

      def address(item)
        raise "invalid item #{item.class} given to address"\
          if !item.is_a? Parser::MemItem
        reg = self.getreg
        self.emittb "lea #{reg.regsz PTRSIZE}, #{self.itemstr item}"
        Parser::RegItem.new reg, PTRSIZE, Parser::PointerType.new item.typ
      end

      def op(lhs, rhs, op)
        optype = op.value % 3
        dst = if lhs.is_a? Parser::RegItem
          lhs.reg
        else
          reg = self.getreg
          self.emittb "mov #{reg.regsz PTRSIZE}, #{self.itemstr lhs}"
          reg
        end
        dsts = dst.regsz PTRSIZE
        rhss = self.itemstr rhs
        case optype
        when 0 # +, -
          ops = case op
          when Scanner::TokenType::Plus
            "add"
          when Scanner::TokenType::Minus
            "sub"
          end

          self.emittb "#{ops} #{dsts}, #{rhss}"
        end
        self.ofree rhs
        Parser::RegItem.new dst, self.tysize(lhs.typ), lhs.typ
      end

      def cast(item, typ)
        srcsz = self.tysize item.typ
        dstsz = self.tysize typ
        case item
        when Parser::RegItem
          self.emittb "and #{item.reg.regsz srcsz}, 0x#{"F"*(dstsz-srcsz).abs}"
          Parser::RegItem.new item.reg, dstsz, typ
        when Parser::MemItem
          reg = self.getreg
          self.emittb "xor #{reg.regsz dstsz}" if dstsz > srcsz
          self.emittb "mov #{reg.regsz dstsz}, #{self.itemstr item}"
          Parser::RegItem.new reg, dstsz, typ
        when Parser::ConstItem
          Parser::ConstItem.new typ, item.value
        else
          raise "invalid item #{item.class} given to cast"
        end
      end

      def call(tgt, args)
        if tgt.is_a? Parser::BuiltinProc
          case sym = tgt.procinfo.sym
          when :WriteELn
            self.needsregsfor [Reg::Rdi, Reg::Rsi, Reg::Rdx] do
              self.emittb "mov rax, 1"
              self.emittb "mov rdi, 1"
              self.emittb "mov rsi, wit$newl"
              self.emittb "mov rdx, 1"
              self.emittb "syscall"
            end
            Parser::VoidItem.new
          when :D2I
            reg = self.getreg
            self.emittb "mov #{reg.regsz 1}, #{self.itemstr args[0]}"
            self.emittb "sub #{reg.regsz 1}, 48"
            Parser::RegItem.new reg, 1, tgt.ret as Parser::Type
          else
            raise "invalid proc #{sym} given to call"
          end
        else
          raise "invalid proc type #{tgt.class} given to call"
        end
      end

      def assign(tgt, expr)
        info = tgt.info as X64VarInfo
        szstr = self.getszstr info.size
        out, item = if info.global
          {info.label, Parser::MemItem.new info.label, "1", "0", tgt.typ}
        else
          {"rbp-#{info.offs}", Parser::MemItem.new "rbp", "1", "-#{info.offs}",
            tgt.typ}
        end
        itemstr = self.itemstr expr
        if expr.is_a? Parser::MemItem
          self.regblock do |reg|
            regsz = reg.regsz info.size
            self.emittb "mov #{regsz}, #{itemstr}"
            self.emittb "mov [#{out}], #{regsz}"
          end
        else
          self.emittb "mov #{szstr} [#{out}], #{itemstr}"
        end
        self.ofree expr
        item
      end

      def mainprolog
        self.emit "_start:"
      end

      def mainepilog
        if @totals[-1] != 0
          self.emittb "mov rsp, rbp"
          self.emittb "pop rbp"
        end
        @totals.pop
        self.emittb "mov rax, 60"
        self.emittb "xor rdi, rdi"
        self.emittb "syscall"
      end

      def prolog
      end

      def epilog
        if @totals[-1] != 0
          self.emittb "mov rsp, rbp"
          self.emittb "pop rbp"
        end
        @totals.pop
        self.emittb "ret"
      end
    end
  end
end
