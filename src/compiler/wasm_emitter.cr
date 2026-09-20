# WebAssembly emitter, derived from chasm's binary encoder.
#
# The module shape:
#
# - imports from `env`, one per builtin the program uses, in a fixed order
#   (`puts scan cannon drive damage speed loc_x loc_y sleep rand sqrt sin
#   cos tan atan`); every host, the interpreter's `Host` included, can back
#   these with the same methods.
# - one mutable i32 global per `global(...)` and per top-level constant.
# - `run`, exported: initializes globals, executes the top-level statements
#   and then the `main` body, returns 0.
# - helper functions `floordiv` and `floormod` when the program divides, so
#   `//` and `%` match the interpreter (floored) and return 0 on division
#   by zero like CROBOTS.
# - one function per `def`: i32 parameters, one i32 result; the result is
#   the value of the last expression statement executed, or `return`.
#
# Strings are not representable, so `puts "text"` is rejected.
module CrystalRobots::Compiler
  class WASM_Emitter
    class Unsupported < Exception
    end

    # Builtins in import order with their type index (see `typeSection`).
    # `tick` is only imported when cycle accounting is requested: the module
    # then calls `env.tick(n)` wherever the interpreter charges n cycles,
    # so a host can count or schedule exactly as it does for the interpreter.
    IMPORTS = [
      {"tick", 2},
      {"puts", 2}, {"scan", 3}, {"cannon", 3}, {"drive", 3},
      {"damage", 1}, {"speed", 1}, {"loc_x", 1}, {"loc_y", 1}, {"sleep", 1},
      {"rand", 2}, {"sqrt", 2}, {"sin", 2}, {"cos", 2}, {"tan", 2}, {"atan", 2},
    ]

    # https://webassembly.github.io/spec/core/binary/modules.html#sections
    enum Section : UInt8
      Custom  =  0
      Type    =  1
      Import  =  2
      Func    =  3
      Table   =  4
      Memory  =  5
      Global  =  6
      Export  =  7
      Start   =  8
      Element =  9
      Code    = 10
      Data    = 11
    end

    # https://webassembly.github.io/spec/core/binary/types.html
    enum Valtype : UInt8
      Externref = 0x6f
      Funcref   = 0x70
      V128      = 0x7b
      F64       = 0x7c
      F32       = 0x7d
      I64       = 0x7e
      I32       = 0x7f
    end

    # https://webassembly.github.io/spec/core/binary/instructions.html
    enum Opcodes : UInt8
      Block      = 0x02
      Loop       = 0x03
      If         = 0x04
      Else       = 0x05
      End        = 0x0b
      Br         = 0x0c
      Br_if      = 0x0d
      Return     = 0x0f
      Call       = 0x10
      Drop       = 0x1a
      Local_get  = 0x20
      Local_set  = 0x21
      Local_tee  = 0x22
      Global_get = 0x23
      Global_set = 0x24
      I32_const  = 0x41
      I32_eqz    = 0x45
      I32_eq     = 0x46
      I32_ne     = 0x47
      I32_lt_s   = 0x48
      I32_gt_s   = 0x4a
      I32_le_s   = 0x4c
      I32_ge_s   = 0x4e
      I32_add    = 0x6a
      I32_sub    = 0x6b
      I32_mul    = 0x6c
      I32_div_s  = 0x6d
      I32_rem_s  = 0x6f
      I32_and    = 0x71
      I32_or     = 0x72
      I32_xor    = 0x73
    end

    enum ExportType : UInt8
      Func   = 0x00
      Table  = 0x01
      Mem    = 0x02
      Global = 0x03
    end

    FunctionType      =    0x60
    BlockVoid         = 0x40_u8
    MagicModuleHeader = Bytes[0, 'a'.ord, 's'.ord, 'm'.ord]
    ModuleVersion     = Bytes[1, 0, 0, 0]

    # Per-function compilation state.
    private class Ctx
      getter locals = {} of String => Int32
      getter loops = [] of Int32 # label depth of each enclosing loop's exit block
      property depth = 0         # number of enclosing labels (block/loop/if)
      getter in_def : Bool
      property ret : Int32 = -1 # local holding the implicit return value
      property temps = 0

      def initialize(@in_def : Bool)
      end
    end

    getter program : Program
    getter costs : Interpreter::Costs?

    # Pass `costs` to emit `env.tick` calls with the interpreter's cycle
    # model; without it the module has no cycle accounting.
    def initialize(@program : Program, @costs : Interpreter::Costs? = nil)
      @imports = [] of String
      @functions = [] of String # user functions in definition order
      @arity = {} of String => Int32
      @globals = [] of String
      @extra_arities = [] of Int32
      @uses_division = false
      analyze
      @functions.each { |name| type_for(@arity[name]) } # fix the type table before emitting
    end

    # ---- encoding helpers -------------------------------------------------

    # https://en.wikipedia.org/wiki/LEB128
    def unsignedLEB128(n : UInt32 | Int32) : Bytes
      buffer = Bytes[]
      loop do
        byte = n & 0x7f
        n = n >> 7
        byte |= 0x80 if n != 0
        buffer += Bytes[byte]
        break if n == 0
      end
      buffer
    end

    def signedLEB128(n : Int32) : Bytes
      buffer = Bytes[]
      more = true
      while more
        byte = (n & 0x7f).to_u8
        n = n >> 7
        if (n == 0 && (byte & 0x40) == 0) || (n == -1 && (byte & 0x40) != 0)
          more = false
        else
          byte = byte | 0x80
        end
        buffer += Bytes[byte]
      end
      buffer
    end

    def encodeVector(data : Bytes) : Bytes
      unsignedLEB128(data.size) + data
    end

    def encodeString(string : String) : Bytes
      unsignedLEB128(string.bytesize) + string.encode("UTF-8")
    end

    def createSection(type : Section, data : Bytes)
      Bytes[type.value] + encodeVector(data)
    end

    private def op(code : Opcodes) : Bytes
      Bytes[code.value]
    end

    private def const(n : Int32) : Bytes
      op(Opcodes::I32_const) + signedLEB128(n)
    end

    private def local_get(i : Int32) : Bytes
      op(Opcodes::Local_get) + unsignedLEB128(i)
    end

    private def local_set(i : Int32) : Bytes
      op(Opcodes::Local_set) + unsignedLEB128(i)
    end

    private def call(i : Int32) : Bytes
      op(Opcodes::Call) + unsignedLEB128(i)
    end

    # `env.tick(n)` when cycle accounting is on and n > 0.
    private def tick(n : Int32) : Bytes
      return Bytes[] if @costs.nil? || n <= 0
      const(n) + call(import_index("tick")) + op(Opcodes::Drop)
    end

    private def cost : Interpreter::Costs
      @costs || Interpreter::Costs.statements
    end

    # ---- analysis ----------------------------------------------------------

    private def analyze : Nil
      names = Set(String).new
      @program.ast.each_with_index do |n, i|
        next unless n.level == 0
        case n.type
        when Type::ZeroArgMethod, Type::OneArgMethod, Type::TwoArgMethod
          names << @program.value(n)
        when Type::FloorDivOperator, Type::DivOperator, Type::ModOperator, Type::ModAssign
          @uses_division = true
        end
      end
      names << "tick" if @costs
      IMPORTS.each { |(name, _)| @imports << name if names.includes?(name) }
      @program.children(@program.root).each do |stmt|
        case @program[stmt].rule
        when :def
          head = @program.arg(stmt, 0)
          idents = @program.children(head).select { |i| @program.type(i) == Type::Identifier }
          name = @program.lexeme(idents[0])
          @functions << name unless @functions.includes?(name)
          @arity[name] = idents.size - 1
        when :global
          @globals << @program.lexeme(@program.children(stmt)[2])
        when :exprstmt
          expr = @program.arg(stmt, 0)
          if @program[expr].rule == :assign
            name = @program.lexeme(@program.arg(expr, 0))
            @globals << name unless @globals.includes?(name)
          end
        end
      end
    end

    private def import_index(name : String) : Int32
      @imports.index(name) || raise Unsupported.new("no import for #{name}")
    end

    private def run_index : Int32
      @imports.size
    end

    private def floordiv_index : Int32
      run_index + 1
    end

    private def floormod_index : Int32
      run_index + 2
    end

    private def function_index(name : String) : Int32
      run_index + (@uses_division ? 3 : 1) + (@functions.index(name) || raise Unsupported.new("no function #{name}"))
    end

    # ---- sections ----------------------------------------------------------

    # Types 0..3 are fixed; functions with more parameters get one extra
    # type each, in order of first use.
    def typeSection
      data = unsignedLEB128(4 + @extra_arities.size) +
             Bytes[FunctionType, 0, 0] +                                         # 0: () -> ()
             Bytes[FunctionType, 0, 1, Valtype::I32] +                           # 1: () -> i32
             Bytes[FunctionType, 1, Valtype::I32, 1, Valtype::I32] +             # 2: (i32) -> i32
             Bytes[FunctionType, 2, Valtype::I32, Valtype::I32, 1, Valtype::I32] # 3: (i32, i32) -> i32
      @extra_arities.each do |arity|
        data += Bytes[FunctionType] + unsignedLEB128(arity) + Bytes.new(arity, Valtype::I32.value) + Bytes[1, Valtype::I32.value]
      end
      createSection(Section::Type, data)
    end

    # The type index for a function taking `arity` i32 parameters.
    private def type_for(arity : Int32) : Int32
      return arity + 1 if arity <= 2
      @extra_arities << arity unless @extra_arities.includes?(arity)
      4 + @extra_arities.index!(arity)
    end

    def importSection
      data = unsignedLEB128(@imports.size)
      @imports.each do |name|
        type = IMPORTS.find! { |(n, _)| n == name }[1]
        data += encodeString("env") + encodeString(name) + Bytes[ExportType::Func.value] + Bytes[type.to_u8]
      end
      createSection(Section::Import, data)
    end

    # Type index of every function in the code section, in order.
    private def function_types : Array(Int32)
      types = [1] # run
      types += [3, 3] if @uses_division
      @functions.each { |name| types << type_for(@arity[name]) }
      types
    end

    def funcSection
      types = function_types
      createSection(Section::Func, unsignedLEB128(types.size) + Bytes.new(types.map(&.to_u8).to_unsafe, types.size).dup)
    end

    def globalSection : Bytes
      return Bytes[] if @globals.empty?
      data = unsignedLEB128(@globals.size)
      @globals.size.times { data += Bytes[Valtype::I32.value, 1] + const(0) + op(Opcodes::End) }
      createSection(Section::Global, data)
    end

    def exportSection
      createSection(Section::Export,
        Bytes[1] + encodeString("run") + Bytes[ExportType::Func.value] + unsignedLEB128(run_index))
    end

    def codeSection : Bytes
      bodies = [run_body]
      bodies += [floordiv_body, floormod_body] if @uses_division
      @functions.each { |name| bodies << function_body(name) }
      data = unsignedLEB128(bodies.size)
      bodies.each { |b| data += encodeVector(b) }
      createSection(Section::Code, data)
    end

    def to_wasm : Bytes
      MagicModuleHeader + ModuleVersion + typeSection + importSection + funcSection +
        globalSection + exportSection + codeSection
    end

    # ---- function bodies ---------------------------------------------------

    private def locals_decl(count : Int32) : Bytes
      count == 0 ? Bytes[0] : Bytes[1] + unsignedLEB128(count) + Bytes[Valtype::I32.value]
    end

    # `run`: globals in declaration order, then top-level statements, then
    # the main body; returns 0.
    private def run_body : Bytes
      ctx = Ctx.new(in_def: false)
      main_stmts = [] of Int32
      code = Bytes[]
      @program.children(@program.root).each do |stmt|
        case @program[stmt].rule
        when :def
        when :global
          kids = @program.children(stmt)
          code += expression(kids[4], ctx) + global_set(@program.lexeme(kids[2]))
        when :main
          main_stmts = body_of(stmt)
        else
          code += statement(stmt, ctx)
        end
      end
      main_stmts.each { |s| code += statement(s, ctx) }
      code += const(0) + op(Opcodes::End)
      locals_decl(ctx.locals.size) + code
    end

    private def function_body(name : String) : Bytes
      stmt = @program.children(@program.root).find! do |s|
        @program[s].rule == :def && @program.lexeme(@program.children(@program.arg(s, 0))[1]) == name
      end
      head = @program.arg(stmt, 0)
      params = @program.children(head).select { |i| @program.type(i) == Type::Identifier }[1..].map { |i| @program.lexeme(i) }
      ctx = Ctx.new(in_def: true)
      params.each { |p| ctx.locals[p] = ctx.locals.size }
      ctx.ret = new_local(ctx, "$ret")
      code = Bytes[]
      body_of(stmt).each { |s| code += statement(s, ctx) }
      code += local_get(ctx.ret) + op(Opcodes::End)
      locals_decl(ctx.locals.size - params.size) + code
    end

    # floordiv(a, b): b == 0 ? 0 : a / b rounded toward negative infinity.
    private def floordiv_body : Bytes
      a, b, q = 0, 1, 2
      code = local_get(b) + op(Opcodes::I32_eqz) + op(Opcodes::If) + Bytes[Valtype::I32.value] +
             const(0) +
             op(Opcodes::Else) +
             local_get(a) + local_get(b) + op(Opcodes::I32_div_s) + local_set(q) +
             local_get(a) + local_get(b) + op(Opcodes::I32_rem_s) + const(0) + op(Opcodes::I32_ne) +
             local_get(a) + local_get(b) + op(Opcodes::I32_xor) + const(0) + op(Opcodes::I32_lt_s) +
             op(Opcodes::I32_and) + op(Opcodes::If) + Bytes[BlockVoid] +
             local_get(q) + const(1) + op(Opcodes::I32_sub) + local_set(q) +
             op(Opcodes::End) +
             local_get(q) +
             op(Opcodes::End) + op(Opcodes::End)
      locals_decl(1) + code
    end

    # floormod(a, b): b == 0 ? 0 : a - b * floordiv(a, b).
    private def floormod_body : Bytes
      a, b = 0, 1
      code = local_get(b) + op(Opcodes::I32_eqz) + op(Opcodes::If) + Bytes[Valtype::I32.value] +
             const(0) +
             op(Opcodes::Else) +
             local_get(a) + local_get(b) + local_get(a) + local_get(b) + call(floordiv_index) +
             op(Opcodes::I32_mul) + op(Opcodes::I32_sub) +
             op(Opcodes::End) + op(Opcodes::End)
      locals_decl(0) + code
    end

    private def body_of(block : Int32) : Array(Int32)
      @program.children(block).select { |i| @program.type(i) == Type::Statement }
    end

    private def new_local(ctx : Ctx, name : String) : Int32
      ctx.locals[name] = ctx.locals.size
    end

    private def global_index(name : String) : Int32
      @globals.index(name) || raise Unsupported.new("unknown global #{name}")
    end

    private def global_set(name : String) : Bytes
      op(Opcodes::Global_set) + unsignedLEB128(global_index(name))
    end

    private def global_get(name : String) : Bytes
      op(Opcodes::Global_get) + unsignedLEB128(global_index(name))
    end

    # An identifier in value position: a variable fetch, or a call to a
    # zero-parameter function.
    private def identifier_get(name : String, ctx : Ctx) : Bytes
      if !ctx.locals.has_key?(name) && !@globals.includes?(name) && @arity[name]? == 0
        tick(cost.call) + call(function_index(name))
      else
        tick(cost.fetch) + variable_get(name, ctx)
      end
    end

    # Read a variable: local first, then global.
    private def variable_get(name : String, ctx : Ctx) : Bytes
      if (i = ctx.locals[name]?)
        local_get(i)
      elsif @globals.includes?(name)
        global_get(name)
      elsif @arity[name]? == 0
        call(function_index(name))
      else
        raise Unsupported.new("undefined variable #{name}")
      end
    end

    # Store the value on the stack into a variable and leave a copy of it.
    private def variable_tee(name : String, ctx : Ctx) : Bytes
      if @globals.includes?(name) && !ctx.locals.has_key?(name)
        global_set(name) + global_get(name)
      else
        i = ctx.locals[name]? || new_local(ctx, name)
        op(Opcodes::Local_tee) + unsignedLEB128(i)
      end
    end

    # ---- statements --------------------------------------------------------

    private def statement(stmt : Int32, ctx : Ctx) : Bytes
      case @program[stmt].rule
      when :exprstmt
        value = expression(@program.arg(stmt, 0), ctx) + tick(cost.statement)
        ctx.in_def ? value + local_set(ctx.ret) : value + op(Opcodes::Drop)
      when :return
        kids = @program.children(stmt)
        value = kids.size > 2 ? expression(kids[1], ctx) : const(0)
        value + tick(cost.branch) + op(Opcodes::Return)
      when :break
        exit = ctx.loops.last? || raise Unsupported.new("break outside of a loop")
        tick(cost.branch) + op(Opcodes::Br) + unsignedLEB128(ctx.depth - exit)
      when :if
        if_statement(stmt, ctx)
      when :while
        loop_statement(stmt, ctx, true)
      when :until
        loop_statement(stmt, ctx, false)
      when :case
        case_statement(stmt, ctx)
      when :global
        kids = @program.children(stmt)
        expression(kids[4], ctx) + global_set(@program.lexeme(kids[2]))
      else
        raise Unsupported.new("statement #{@program[stmt].rule} is not supported in WASM")
      end
    end

    # if / elsif / else as nested `if` blocks.
    private def if_statement(stmt : Int32, ctx : Ctx) : Bytes
      branches = [] of {Int32?, Array(Int32)} # condition node (nil for else), statements
      @program.children(stmt).each do |k|
        case @program.type(k)
        when Type::IfHead, Type::ElsifHead
          branches << {@program.arg(k, 1), [] of Int32}
        when Type::ElseKeyword
          branches << {nil, [] of Int32}
        when Type::Statement
          branches.last[1] << k
        end
      end
      emit_branches(branches, ctx)
    end

    private def emit_branches(branches : Array({Int32?, Array(Int32)}), ctx : Ctx) : Bytes
      return Bytes[] if branches.empty?
      cond, stmts = branches[0]
      if cond.nil?
        return stmts.sum(Bytes[]) { |s| statement(s, ctx) }
      end
      code = expression(cond, ctx) + tick(cost.branch) + op(Opcodes::If) + Bytes[BlockVoid]
      ctx.depth += 1
      stmts.each { |s| code += statement(s, ctx) }
      rest = branches[1..]
      unless rest.empty?
        code += op(Opcodes::Else)
        code += emit_branches(rest, ctx)
      end
      ctx.depth -= 1
      code + op(Opcodes::End)
    end

    # while / until: block { loop { cond; br_if exit; body; br loop } }.
    # Loops evaluate to nothing, so the implicit return value resets to 0.
    private def loop_statement(stmt : Int32, ctx : Ctx, while_true : Bool) : Bytes
      cond = @program.arg(@program.arg(stmt, 0), 1)
      code = op(Opcodes::Block) + Bytes[BlockVoid]
      ctx.depth += 1
      exit = ctx.depth
      ctx.loops << exit
      code += op(Opcodes::Loop) + Bytes[BlockVoid]
      ctx.depth += 1
      code += expression(cond, ctx)
      code += op(Opcodes::I32_eqz) if while_true
      code += tick(cost.branch)
      code += op(Opcodes::Br_if) + unsignedLEB128(ctx.depth - exit)
      body_of(stmt).each { |s| code += statement(s, ctx) }
      code += op(Opcodes::Br) + unsignedLEB128(0)
      ctx.depth -= 1
      code += op(Opcodes::End)
      ctx.loops.pop
      ctx.depth -= 1
      code += op(Opcodes::End)
      code += const(0) + local_set(ctx.ret) if ctx.in_def
      code
    end

    # case: the subject goes into a temporary, each `when` compares to it.
    private def case_statement(stmt : Int32, ctx : Ctx) : Bytes
      kids = @program.children(stmt)
      subject = new_local(ctx, "$case#{ctx.temps += 1}")
      code = expression(@program.arg(kids[0], 1), ctx) + local_set(subject)
      branches = [] of {Int32?, Array(Int32)}
      whens = [] of Int32
      kids[1..].each do |k|
        case @program.type(k)
        when Type::WhenHead
          whens << @program.arg(k, 1)
          branches << {whens.last, [] of Int32}
        when Type::ElseKeyword
          branches << {nil, [] of Int32}
        when Type::Statement
          branches.last[1] << k
        end
      end
      code + emit_case_branches(branches, subject, ctx)
    end

    private def emit_case_branches(branches : Array({Int32?, Array(Int32)}), subject : Int32, ctx : Ctx) : Bytes
      return Bytes[] if branches.empty?
      cond, stmts = branches[0]
      if cond.nil?
        return stmts.sum(Bytes[]) { |s| statement(s, ctx) }
      end
      code = local_get(subject) + expression(cond, ctx) + op(Opcodes::I32_eq) + tick(cost.branch) + op(Opcodes::If) + Bytes[BlockVoid]
      ctx.depth += 1
      stmts.each { |s| code += statement(s, ctx) }
      rest = branches[1..]
      unless rest.empty?
        code += op(Opcodes::Else) + emit_case_branches(rest, subject, ctx)
      end
      ctx.depth -= 1
      code + op(Opcodes::End)
    end

    # ---- expressions -------------------------------------------------------

    # Emit code that leaves the value of expression node i on the stack.
    def expression(i : Int32, ctx : Ctx = Ctx.new(in_def: false)) : Bytes
      n = @program[i]
      case n.rule
      when :lex
        case n.type
        when Type::Number        then tick(cost.fetch) + const(@program.value(n).to_i32)
        when Type::Identifier    then identifier_get(@program.value(n), ctx)
        when Type::ZeroArgMethod then tick(cost.builtin) + call(import_index(@program.value(n)))
        when Type::String        then raise Unsupported.new("strings are not supported in WASM")
        else                          raise Unsupported.new("#{n.type} is not a value")
        end
      when :literal
        tick(cost.fetch) + const(@program.type(@program.arg(i, 0)) == Type::TrueKeyword ? 1 : 0)
      when :paren
        expression(@program.arg(i, 1), ctx)
      when :neg
        const(0) + expression(@program.arg(i, 1), ctx) + op(Opcodes::I32_sub) + tick(cost.operator)
      when :mul, :add, :cmp, :eq, :and, :or
        binary(@program.type(@program.arg(i, 1)), expression(@program.arg(i, 0), ctx), expression(@program.arg(i, 2), ctx)) + tick(cost.operator)
      when :assign
        expression(@program.arg(i, 2), ctx) + tick(cost.store) + variable_tee(@program.lexeme(@program.arg(i, 0)), ctx)
      when :opassign
        name = @program.lexeme(@program.arg(i, 0))
        opt = case @program.type(@program.arg(i, 1))
              when Type::AddAssign then Type::AddOperator
              when Type::SubAssign then Type::SubOperator
              when Type::MulAssign then Type::MulOperator
              else                      Type::ModOperator
              end
        binary(opt, variable_get(name, ctx), expression(@program.arg(i, 2), ctx)) +
          tick(cost.fetch + cost.operator + cost.store) + variable_tee(name, ctx)
      when :call0
        tick(cost.builtin) + call(import_index(@program.lexeme(i)))
      when :call1, :command1, :call2, :command2
        kids = @program.children(i)
        args = kids[1..].reject { |k| {Type::OpenParen, Type::CloseParen, Type::Comma}.includes?(@program.type(k)) }
        args.sum(Bytes[]) { |a| expression(a, ctx) } + tick(cost.builtin) + call(import_index(@program.lexeme(kids[0])))
      when :call
        kids = @program.children(i)
        name = @program.lexeme(kids[0])
        args = kids[2..].reject { |k| {Type::CloseParen, Type::Comma}.includes?(@program.type(k)) }
        args.sum(Bytes[]) { |a| expression(a, ctx) } + tick(cost.call) + call(function_index(name))
      else
        raise Unsupported.new("expression #{n.rule} is not supported in WASM")
      end
    end

    # Logical operators yield 0 or 1 like the interpreter; both sides are
    # evaluated, also like the interpreter.
    private def binary(opt : Type, left : Bytes, right : Bytes) : Bytes
      case opt
      when Type::AddOperator then left + right + op(Opcodes::I32_add)
      when Type::SubOperator then left + right + op(Opcodes::I32_sub)
      when Type::MulOperator then left + right + op(Opcodes::I32_mul)
      when Type::FloorDivOperator, Type::DivOperator
        left + right + call(floordiv_index)
      when Type::ModOperator then left + right + call(floormod_index)
      when Type::EqOperator  then left + right + op(Opcodes::I32_eq)
      when Type::NeOperator  then left + right + op(Opcodes::I32_ne)
      when Type::LtOperator  then left + right + op(Opcodes::I32_lt_s)
      when Type::GtOperator  then left + right + op(Opcodes::I32_gt_s)
      when Type::LeOperator  then left + right + op(Opcodes::I32_le_s)
      when Type::GeOperator  then left + right + op(Opcodes::I32_ge_s)
      when Type::AndOperator
        left + const(0) + op(Opcodes::I32_ne) + right + const(0) + op(Opcodes::I32_ne) + op(Opcodes::I32_and)
      when Type::OrOperator
        left + const(0) + op(Opcodes::I32_ne) + right + const(0) + op(Opcodes::I32_ne) + op(Opcodes::I32_or)
      when Type::XorOperator then left + right + op(Opcodes::I32_xor)
      else
        raise Unsupported.new("operator #{opt} is not supported in WASM")
      end
    end
  end
end
