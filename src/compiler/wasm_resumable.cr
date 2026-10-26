# The resumable encoder keeps every live value in linear memory. Each
# activation occupies one fixed-size frame; the only native stack in step()
# is emptied before a charged cycle returns to its host.
# step() returns 0 for a pause, 1 when main completes, and 2 for a runtime
# error. error_code is the one-based index of the function whose call exceeded
# MAX_CALL_DEPTH (the only runtime error a checked, numeric WASM program has).
module CrystalRobots::Compiler
  class WASM_Emitter
    private FRAME_BYTES = 2048
    private SLOT_PC     =    0
    private SLOT_DEST   =    1
    private SLOT_VALUE  =    2

    private class ResumeCtx
      getter vars = {} of String => Int32
      getter constant_flags = {} of String => Int32
      getter top_level : Bool
      property slot = 3

      def initialize(@top_level = false)
      end

      def temp : Int32
        old = @slot
        raise WASM_Emitter::Unsupported.new("too many locals and temporaries") if old >= FRAME_BYTES // 4
        @slot += 1
        old
      end
    end

    private def rg(i : Int32) : Bytes
      op(Opcodes::Global_get) + unsignedLEB128(i)
    end

    private def rs(i : Int32) : Bytes
      op(Opcodes::Global_set) + unsignedLEB128(i)
    end

    private def depth_g : Int32
      @globals.size
    end

    private def remain_g : Int32
      @globals.size + 1
    end

    private def init_g : Int32
      @globals.size + 2
    end

    private def error_g : Int32
      @globals.size + 3
    end

    private def load_slot(slot : Int32) : Bytes
      local_get(0) + op(Opcodes::I32_load) + Bytes[2] + unsignedLEB128(slot * 4)
    end

    private def store_slot(slot : Int32, value : Bytes) : Bytes
      local_get(0) + value + op(Opcodes::I32_store) + Bytes[2] + unsignedLEB128(slot * 4)
    end

    private def jump(pc : Int32) : Bytes
      store_slot(SLOT_PC, const(pc))
    end

    private def block(code : Bytes) : Int32
      @resume_blocks << code
      @resume_blocks.size - 1
    end

    private def reserve : Int32
      block(Bytes[])
    end

    private def charge(n : Int32, after : Int32) : Int32
      return after if n <= 0
      block(jump(after) + const(n - 1) + rs(remain_g) + const(0) + op(Opcodes::Return))
    end

    private def variable(name : String, ctx : ResumeCtx) : Bytes
      if (flag = ctx.constant_flags[name]?)
        load_slot(flag) + op(Opcodes::If) + Bytes[Valtype::I32.value] +
          load_slot(ctx.vars[name]) + op(Opcodes::Else) + global_get(name) + op(Opcodes::End)
      elsif (slot = ctx.vars[name]?)
        load_slot(slot)
      elsif @globals.includes?(name)
        global_get(name)
      else
        raise Unsupported.new("undefined variable #{name}")
      end
    end

    private def assign_code(name : String, value : Bytes, ctx : ResumeCtx) : Bytes
      if @resume_globals.includes?(name) || (ctx.top_level && @resume_constants.includes?(name))
        value + global_set(name)
      else
        slot = ctx.vars[name]? || (ctx.vars[name] = ctx.temp)
        code = store_slot(slot, value)
        code += store_slot(ctx.constant_flags[name], const(1)) if ctx.constant_flags.has_key?(name)
        code
      end
    end

    private def user_call(name : String, args : Array(Int32), dst : Int32, after : Int32) : Int32
      entry = @resume_entries[name]? || raise Unsupported.new("no function #{name}")
      arity = @arity[name]? || raise Unsupported.new("no function #{name}")
      raise Unsupported.new("#{name} expects #{arity} arguments") unless arity == args.size
      # The caller's PC and destination survive while the callee runs.
      code = jump(after) + store_slot(SLOT_DEST, const(dst)) + local_get(0) + local_set(3)
      code += rg(depth_g) + const(Compiler::Interpreter::MAX_CALL_DEPTH) + op(Opcodes::I32_ge_s)
      code += op(Opcodes::If) + Bytes[BlockVoid]
      code += const(@resume_function_ids[name]) + rs(error_g)
      code += const(0) + rs(depth_g) + frame_pointer + jump(@resume_main_pc)
      code += const(2) + op(Opcodes::Return)
      code += op(Opcodes::End)
      code += rg(depth_g) + const(1) + op(Opcodes::I32_add) + rs(depth_g)
      code += frame_pointer
      code += store_slot(SLOT_PC, const(entry))
      args.each_with_index do |slot, i|
        from_caller = local_get(3) + op(Opcodes::I32_load) + Bytes[2] + unsignedLEB128(slot * 4)
        code += store_slot(3 + i, from_caller)
      end
      block(code)
    end

    private def frame_pointer : Bytes
      rg(depth_g) + const(FRAME_BYTES) + op(Opcodes::I32_mul) + local_set(0)
    end

    private def builtin_call(name : String, args : Array(Int32), dst : Int32, after : Int32) : Int32
      code = args.sum(Bytes[]) { |slot| load_slot(slot) }
      code = store_slot(dst, code + call(import_index(name))) + jump(after)
      charge(cost.builtin, block(code))
    end

    private def compile_expr(i : Int32, dst : Int32, after : Int32, ctx : ResumeCtx) : Int32
      n = @program[i]
      case n.rule
      when :lex
        name = @program.value(n)
        case n.type
        when Type::Number
          charge(cost.fetch, block(store_slot(dst, const(name.to_i32)) + jump(after)))
        when Type::Identifier
          if !ctx.vars.has_key?(name) && !@globals.includes?(name) && @resume_entries.has_key?(name)
            charge(cost.call, user_call(name, [] of Int32, dst, after))
          else
            charge(cost.fetch, block(store_slot(dst, variable(name, ctx)) + jump(after)))
          end
        when Type::ZeroArgMethod
          builtin_call(name, [] of Int32, dst, after)
        when Type::String
          raise Unsupported.new("strings are not supported in WASM")
        else
          raise Unsupported.new("#{n.type} is not a value")
        end
      when :literal
        value = @program.type(@program.arg(i, 0)) == Type::TrueKeyword ? 1 : 0
        charge(cost.fetch, block(store_slot(dst, const(value)) + jump(after)))
      when :paren
        compile_expr(@program.arg(i, 1), dst, after, ctx)
      when :neg
        inner = ctx.temp
        calc = block(store_slot(dst, const(0) + load_slot(inner) + op(Opcodes::I32_sub)) + jump(charge(cost.operator, after)))
        compile_expr(@program.arg(i, 1), inner, calc, ctx)
      when :mul, :add, :cmp, :eq, :and, :or
        left = ctx.temp
        right = ctx.temp
        value = binary(@program.type(@program.arg(i, 1)), load_slot(left), load_slot(right))
        calc = block(store_slot(dst, value) + jump(charge(cost.operator, after)))
        compile_expr(@program.arg(i, 0), left, compile_expr(@program.arg(i, 2), right, calc, ctx), ctx)
      when :assign
        name = @program.lexeme(@program.arg(i, 0))
        action = block(assign_code(name, load_slot(dst), ctx) + jump(after))
        compile_expr(@program.arg(i, 2), dst, charge(cost.store, action), ctx)
      when :opassign
        name = @program.lexeme(@program.arg(i, 0))
        opt = case @program.type(@program.arg(i, 1))
              when Type::AddAssign then Type::AddOperator
              when Type::SubAssign then Type::SubOperator
              when Type::MulAssign then Type::MulOperator
              else                      Type::ModOperator
              end
        rhs = ctx.temp
        calc = block(store_slot(dst, binary(opt, variable(name, ctx), load_slot(rhs))) +
                     jump(charge(cost.fetch + cost.operator + cost.store,
                       block(assign_code(name, load_slot(dst), ctx) + jump(after)))))
        compile_expr(@program.arg(i, 2), rhs, calc, ctx)
      when :call0
        builtin_call(@program.lexeme(i), [] of Int32, dst, after)
      when :call1, :command1, :call2, :command2, :call
        kids = @program.children(i)
        user = n.rule == :call
        name = @program.lexeme(kids[0])
        nodes = kids[(user ? 2 : 1)..].reject { |k| @program.type(k).in?(Type::OpenParen, Type::CloseParen, Type::Comma) }
        slots = nodes.map { ctx.temp }
        entry = if user
                  charge(cost.call, user_call(name, slots, dst, after))
                else
                  builtin_call(name, slots, dst, after)
                end
        nodes.reverse_each.with_index do |node, rev|
          entry = compile_expr(node, slots[slots.size - rev - 1], entry, ctx)
        end
        entry
      else
        raise Unsupported.new("expression #{n.rule} is not supported in WASM")
      end
    end

    private def compile_body(stmts : Array(Int32), after : Int32, ctx : ResumeCtx, loop_exit : Int32 = -1) : Int32
      entry = after
      stmts.reverse_each { |stmt| entry = compile_stmt(stmt, entry, ctx, loop_exit) }
      entry
    end

    private def seed_locals(nodes : Array(Int32), ctx : ResumeCtx) : Nil
      nodes.each { |node| seed_local(node, ctx) }
    end

    private def seed_local(node : Int32, ctx : ResumeCtx) : Nil
      if @program[node].rule.in?(:assign, :opassign)
        name = @program.lexeme(@program.arg(node, 0))
        unless @resume_globals.includes?(name) || (ctx.top_level && @resume_constants.includes?(name)) || ctx.vars.has_key?(name)
          ctx.vars[name] = ctx.temp
          ctx.constant_flags[name] = ctx.temp if @resume_constants.includes?(name)
        end
      end
      @program.children(node).each { |kid| seed_local(kid, ctx) }
    end

    private def branches(stmt : Int32) : Array({Int32?, Array(Int32)})
      out = [] of {Int32?, Array(Int32)}
      @program.children(stmt).each do |k|
        case @program.type(k)
        when Type::IfHead, Type::ElsifHead, Type::WhenHead
          out << {@program.arg(k, 1), [] of Int32}
        when Type::ElseKeyword
          out << {nil, [] of Int32}
        when Type::Statement
          out.last[1] << k
        end
      end
      out
    end

    private def compile_choices(choices : Array({Int32?, Array(Int32)}), after : Int32, ctx : ResumeCtx,
                                loop_exit : Int32, subject : Int32 = -1) : Int32
      entry = after
      choices.reverse_each do |cond, stmts|
        yes = compile_body(stmts, after, ctx, loop_exit)
        if cond.nil?
          entry = yes
        else
          value = ctx.temp
          test = subject < 0 ? load_slot(value) : load_slot(value) + load_slot(subject) + op(Opcodes::I32_eq)
          choice = block(test + op(Opcodes::If) + Bytes[BlockVoid] + jump(yes) +
                         op(Opcodes::Else) + jump(entry) + op(Opcodes::End))
          entry = compile_expr(cond, value, charge(cost.branch, choice), ctx)
        end
      end
      entry
    end

    private def compile_stmt(stmt : Int32, after : Int32, ctx : ResumeCtx, loop_exit : Int32) : Int32
      case @program[stmt].rule
      when :exprstmt
        compile_expr(@program.arg(stmt, 0), SLOT_VALUE, charge(cost.statement, after), ctx)
      when :return
        kids = @program.children(stmt)
        finish = charge(cost.branch, @resume_return_pc)
        kids.size > 2 ? compile_expr(kids[1], SLOT_VALUE, finish, ctx) : block(store_slot(SLOT_VALUE, const(0)) + jump(finish))
      when :break
        raise Unsupported.new("break outside of a loop") if loop_exit < 0
        charge(cost.branch, loop_exit)
      when :if
        entry = compile_choices(branches(stmt), after, ctx, loop_exit)
        block(store_slot(SLOT_VALUE, const(0)) + jump(entry))
      when :while, :until
        cond_pc = reserve
        exit_pc = block(store_slot(SLOT_VALUE, const(0)) + jump(after))
        body = compile_body(body_of(stmt), cond_pc, ctx, exit_pc)
        value = ctx.temp
        while_true = @program[stmt].rule == :while
        test = load_slot(value)
        test += op(Opcodes::I32_eqz) unless while_true
        choice = block(test + op(Opcodes::If) + Bytes[BlockVoid] + jump(body) +
                       op(Opcodes::Else) + jump(exit_pc) + op(Opcodes::End))
        @resume_blocks[cond_pc] = jump(compile_expr(@program.arg(@program.arg(stmt, 0), 1), value,
          charge(cost.branch, choice), ctx))
        cond_pc
      when :case
        subject = ctx.temp
        entry = compile_choices(branches(stmt), after, ctx, loop_exit, subject)
        start = compile_expr(@program.arg(@program.children(stmt)[0], 1), subject, entry, ctx)
        block(store_slot(SLOT_VALUE, const(0)) + jump(start))
      when :global
        kids = @program.children(stmt)
        name = @program.lexeme(kids[2])
        raise Unsupported.new("unknown global #{name}") unless @globals.includes?(name)
        slot = ctx.temp
        finish = block(store_slot(SLOT_VALUE, const(0)) + jump(after))
        action = block(assign_code(name, load_slot(slot), ctx) + jump(finish))
        compile_expr(kids[4], slot, action, ctx)
      else
        raise Unsupported.new("statement #{@program[stmt].rule} is not supported in WASM")
      end
    end

    private def resumable_wasm : Bytes
      @resume_blocks = [] of Bytes
      @resume_entries = {} of String => Int32
      @resume_function_ids = {} of String => Int32
      @resume_globals = Set(String).new
      @resume_constants = Set(String).new
      @program.children(@program.root).each do |stmt|
        case @program[stmt].rule
        when :global
          @resume_globals << @program.lexeme(@program.children(stmt)[2])
        when :exprstmt
          expr = @program.arg(stmt, 0)
          @resume_constants << @program.lexeme(@program.arg(expr, 0)) if @program[expr].rule == :assign
        end
      end
      @functions.each_with_index do |name, i|
        @resume_entries[name] = reserve
        @resume_function_ids[name] = i + 1
      end
      main_entry = reserve
      @resume_main_pc = main_entry
      init_entry = reserve
      @resume_return_pc = reserve
      @functions.each do |name|
        stmt = @program.children(@program.root).find! do |s|
          @program[s].rule == :def && @program.lexeme(@program.children(@program.arg(s, 0))[1]) == name
        end
        ctx = ResumeCtx.new
        head = @program.arg(stmt, 0)
        @program.children(head).select { |k| @program.type(k) == Type::Identifier }[1..].each do |k|
          ctx.vars[@program.lexeme(k)] = ctx.temp
        end
        seed_locals(body_of(stmt), ctx)
        body = compile_body(body_of(stmt), @resume_return_pc, ctx)
        reset = ctx.constant_flags.values.sum(Bytes[]) { |flag| store_slot(flag, const(0)) }
        @resume_blocks[@resume_entries[name]] = reset + store_slot(SLOT_VALUE, const(0)) + jump(body)
      end
      main_stmts = [] of Int32
      init_stmts = [] of Int32
      @program.children(@program.root).each do |stmt|
        case @program[stmt].rule
        when :main then main_stmts = body_of(stmt)
        when :def
        else init_stmts << stmt
        end
      end
      main_ctx = ResumeCtx.new
      seed_locals(main_stmts, main_ctx)
      main_body = compile_body(main_stmts, @resume_return_pc, main_ctx)
      reset = main_ctx.constant_flags.values.sum(Bytes[]) { |flag| store_slot(flag, const(0)) }
      @resume_blocks[main_entry] = reset + store_slot(SLOT_VALUE, const(0)) + jump(main_body)
      init_ctx = ResumeCtx.new(top_level: true)
      seed_locals(init_stmts, init_ctx)
      init_finish = block(const(1) + rs(init_g) + jump(main_entry))
      init_body = compile_body(init_stmts, init_finish, init_ctx)
      @resume_blocks[init_entry] = store_slot(SLOT_VALUE, const(0)) + jump(init_body)
      @resume_blocks[@resume_return_pc] = return_from_frame(main_entry)
      resume_module(init_entry)
    end

    private def return_from_frame(main_entry : Int32) : Bytes
      code = rg(depth_g) + op(Opcodes::I32_eqz) + op(Opcodes::If) + Bytes[BlockVoid]
      code += jump(main_entry) + const(1) + op(Opcodes::Return)
      code += op(Opcodes::End)
      code += load_slot(SLOT_VALUE) + local_set(2)
      code += rg(depth_g) + const(1) + op(Opcodes::I32_sub) + rs(depth_g) + frame_pointer
      code += local_get(0) + load_slot(SLOT_DEST) + const(4) + op(Opcodes::I32_mul) + op(Opcodes::I32_add)
      code += local_get(2) + op(Opcodes::I32_store) + Bytes[2, 0]
      code
    end

    private def resume_module(init_entry : Int32) : Bytes
      # Locals: frame base, saved PC, return value. br_table selects one
      # block; the selected block runs and branches back to the dispatch loop.
      code = rg(init_g) + op(Opcodes::I32_eqz) + op(Opcodes::If) + Bytes[BlockVoid]
      code += frame_pointer + jump(init_entry)
      code += const(1) + rs(init_g) # initialization is never repeated
      code += op(Opcodes::End)
      code += rg(remain_g) + op(Opcodes::If) + Bytes[BlockVoid]
      code += rg(remain_g) + const(1) + op(Opcodes::I32_sub) + rs(remain_g)
      code += const(0) + op(Opcodes::Return) + op(Opcodes::End)
      code += op(Opcodes::Loop) + Bytes[BlockVoid] + frame_pointer
      code += load_slot(SLOT_PC) + local_set(1)
      count = @resume_blocks.size
      count.times { code += op(Opcodes::Block) + Bytes[BlockVoid] }
      code += local_get(1) + Bytes[0x0e] + unsignedLEB128(count)
      count.times { |i| code += unsignedLEB128(i) }
      code += unsignedLEB128(count)
      @resume_blocks.each_with_index do |body, i|
        code += op(Opcodes::End) + body + op(Opcodes::Br) + unsignedLEB128(count - i - 1)
      end
      code += op(Opcodes::End) # loop
      code += const(2) + op(Opcodes::End)
      body = locals_decl(4) + code
      types = createSection(Section::Type, unsignedLEB128(4) +
                                           Bytes[FunctionType, 0, 0, FunctionType, 0, 1, Valtype::I32,
                                             FunctionType, 1, Valtype::I32, 1, Valtype::I32,
                                             FunctionType, 2, Valtype::I32, Valtype::I32, 1, Valtype::I32])
      func_types = [1]
      func_types += [3, 3] if @uses_division
      funcs = createSection(Section::Func, unsignedLEB128(func_types.size) + Bytes.new(func_types.map(&.to_u8).to_unsafe, func_types.size).dup)
      memory = createSection(Section::Memory, Bytes[1, 0, 7])
      globals = unsignedLEB128(@globals.size + 4)
      (@globals.size + 4).times { globals += Bytes[Valtype::I32.value, 1] + const(0) + op(Opcodes::End) }
      exports = Bytes[3] + encodeString("step") + Bytes[0] + unsignedLEB128(@imports.size) +
                encodeString("memory") + Bytes[2, 0] + encodeString("error_code") + Bytes[3] + unsignedLEB128(error_g)
      MagicModuleHeader + ModuleVersion + types + importSection + funcs + memory +
        createSection(Section::Global, globals) + createSection(Section::Export, exports) +
        createSection(Section::Code, unsignedLEB128(func_types.size) + encodeVector(body) +
                                     (@uses_division ? encodeVector(floordiv_body) + encodeVector(floormod_body) : Bytes[]))
    end
  end
end
