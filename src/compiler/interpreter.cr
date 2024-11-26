module CrystalRobots::Compiler
  class Interpreter
    @@puts_out = Array(String).new

    def self.execute(p : Program)
      Log.d("executing #{p.to_s}")
      p.start
      retval = Nil
      while true
        r = executeStatement(p)
        Log.d "#{p.node.type.value.chr} -> ret: #{retval}, i: #{r[:pc]}, exit: #{r[:exit]}"
        retval = r[:ret]
        if r[:exit]
          break
        end
        p.jump(r[:pc])
      end
      retval
    end

    def self.executeStatement(p : Program)
      stmt = p.node.not_nil!
      stmt_t = stmt.type.not_nil!
      pc = p.pc
      retval = 0_i32
      do_exit = true
      case stmt_t
      when Type::Expression
        cmd = p.arg(1)
        larg_val = get_val(p, 0)
        rarg_val = get_val(p, 2)
        Log.d "evaluating #{larg_val} #{cmd.value} #{rarg_val}"
        retval = expression(cmd, larg_val, rarg_val)
        Log.d "result #{larg_val} #{cmd.value} #{rarg_val} -> #{retval}"
        pc = pc.inc(1)
      when Type::OneArgStatement
        cmd = p.arg(0)
        arg_val = get_val(p, 1)
        Log.d "calling #{cmd.value}(#{arg_val})"
        retval = oneArgCall(cmd.value, arg_val)
        pc = pc.inc(1)
      end
      if p.test_pc(pc)
        do_exit = false
      end
      {"pc": pc, "ret": retval, "exit": do_exit}
    end

    def self.get_val(p, n)
      case p.arg(n).type
      when Type::Number
        p.arg(n).value
      when Type::String
        p.arg(n).value
      when Type::Expression
        call(p, n)
      end
    end

    def self.call(p, n)
      p.call(n)
      r = executeStatement(p)
      p.return
      r[:ret]
    end

    def self.expression(op, l, r)
      if l.nil? || r.nil?
        raise "Argument was nil: '#{l}' '#{op.value}' '#{r}'"
      end
      case op.value
      when "+"
        l.to_i32 + r.to_i32
      when "-"
        l.to_i32 - r.to_i32
      when "*"
        l.to_i32 * r.to_i32
      when "//"
        l.to_i32 // r.to_i32
      when "=="
        l.to_i32 == r.to_i32 ? 1_i32 : 0_i32
      when ">"
        l.to_i32 > r.to_i32 ? 1_i32 : 0_i32
      when "<"
        l.to_i32 < r.to_i32 ? 1_i32 : 0_i32
      when "&"
        l.to_i32 & r.to_i32
      when "|"
        l.to_i32 | r.to_i32
      when "^"
        l.to_i32 ^ r.to_i32
      else
        raise "Invalid operator: #{op}"
      end
    end

    def self.oneArgCall(name, arg0)
      case name
      when "puts"
        i_puts arg0
      else
        raise "unknown method: #{name}"
      end
    end

    def self.i_puts(x)
      @@puts_out << "#{x}"
      0_i32
    end

    def self.puts_clear
      @@puts_out = Array(String).new
    end

    def self.puts_out
      @@puts_out.join("\n")
    end
  end
end
