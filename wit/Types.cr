module Wit
  module Parser # XXX: This should'nt be the Parser module!?
    # This represents an abstract identifier.
    class Object
    end

    # A variable.
    class Variable < Object
      setter info
      getter name, typ, export, info

      def initialize(@name, @typ, @export)
        @info = nil
      end
    end

    # A procedure.
    abstract class Proc < Object
      # ret: return type
      # args: array of argument types
      getter ret, args
    end

    # A builtin procedure.
    class BuiltinProc < Proc
      getter procinfo

      def initialize(@sym, @ret, @args)
        @procinfo = Codegen::X64BuiltinProcInfo.new sym
      end
    end

    # A type.
    abstract class Type < Object
      # Convert the type to a string representation suitable for error messages.
      abstract def tystr
      # Can values of the type be indexed?
      abstract def indexes?
      # Can values of the type be indexed with the given type?
      abstract def indexes_with?(typ)
      # Can the type be used to index a pointer or array?
      abstract def index?
      # Does the type support the given binary operation?
      abstract def supports?(op)
      # Does the type support the given binary operation with the given type?
      abstract def supports_with?(op, typ)
    end

    # A builtin type
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

      def indexes?
        false
      end

      def indexes_with?(typ)
        false
      end

      def index?
        true
      end

      def supports?(op)
        true # XXX: op should be checked. This will explode.
      end

      def supports_with?(op, typ)
        # XXX: op should be checked. This will also explode.
        if typ.is_a? BuiltinType
          @sym == typ.sym
        else
          false
        end
      end
    end

    abstract class DerivedType < Type
      getter base
    end

    class PointerType < DerivedType
      def initialize(@base)
      end

      def ==(other)
        other.is_a?(PointerType) && @base == other.base
      end

      def tystr
        "#{base.tystr}*"
      end

      def indexes?
        true
      end

      def indexes_with?(typ)
        typ.index?
      end

      def index?
        false
      end

      def supports?(op)
        true # XXX: See above comments.
      end

      def supports_with?(op, typ)
        # XXX: op should also be checked here.
        if typ.is_a? PointerType
          @base == typ.base
        else
          true
        end
      end
    end

    class ArrayType < DerivedType
      getter cap

      def initialize(@base, @cap)
      end

      def ==(other)
        other.is_a? ArrayType && @base == other.base && @cap == other.cap
      end

      def tystr
        "#{base.tystr}[#{@cap}]"
      end

      def indexes?
        true
      end

      def indexes_with?(typ)
        typ.index?
      end

      def index?
        false
      end

      def supports?(op)
        false # XXX: What operands should static arrays support?
      end

      def supports_with?(op, typ)
        false
      end
    end

    # An abstract expression.
    abstract class Item
      # The expression's type.
      abstract def typ
      # Can it's address be taken? (only true for memory locations)
      abstract def addressable?
      # Shallow copy the current item, changing the result's type to typ.
      abstract def retype(typ)
    end

    # A compile-time constant value.
    class ConstItem < Item
      getter typ, value

      def initialize(@typ, @value)
      end

      def addressable?
        false
      end

      def retype(typ)
        ConstItem.new typ, @value
      end
    end

    # A machine register
    class RegItem < Item
      getter reg, typ

      def initialize(@reg, @typ)
      end

      def addressable?
        false
      end

      def retype(typ)
        RegItem.new @reg, typ
      end
    end

    # A memory location: [base*mul+offs].
    class MemItem < Item
      getter base, mul, offs, typ

      def initialize(@base, @mul, @offs, @typ)
      end

      def addressable?
        true
      end

      def retype(typ)
        MemItem.new @base, @mul, @offs, typ
      end
    end

    # Represents lack of a value.
    class VoidItem < Item
      def typ
        # XXX
        BuiltinType.new(:Void)
      end

      def addressable?
        false
      end

      def retype(typ)
        raise "called retype on void item"
      end
    end
  end
end
