module CrystalRobots::Compiler
  class Interpreter
    @@puts_out = Array(String).new

    def self.execute(p : Program)
      p.start
      retval = Nil
      while true
        r = executeStatement(p)
        # puts "#{p.node.type.value.chr} -> ret: #{retval}, i: #{r[:pc]}, exit: #{r[:exit]}}"
        retval = r[:ret]
        if r[:exit]
          break
        end
        p.jump(r[:pc])
      end
      retval
    end

    def self.executeStatement(p : Program)
      stmt = p.node
      stmt_t = stmt.type
      pc = p.pc
      retval = 0_i32
      do_exit = true
      case stmt_t
      when Type::Expression
        cmd = p.arg(1)
        larg = p.arg(0)
        rarg = p.arg(2)
        retval = expression(cmd.type, larg.value, rarg.value)
        pc = pc.inc(3)
      when Type::OneArgStatement
        cmd = p.arg(0)
        arg = p.arg(1)
        # puts "calling #{cmd.value}(#{arg.value})"
        retval = oneArgCall(cmd.value, arg.value)
        pc = pc.inc(2)
      end
      if p.test_pc(pc)
        do_exit = false
      end
      {"pc": pc, "ret": retval, "exit": do_exit}
    end

    def self.expression(op, l, r)
      case op
      when Type::AddOperator
        l.to_i32 + r.to_i32
      when Type::SubOperator
        l.to_i32 - r.to_i32
      when Type::MulOperator
        l.to_i32 * r.to_i32
      when Type::FloorDivOperator
        l.to_i32 // r.to_i32
      when Type::EqOperator
        l.to_i32 == r.to_i32 ? 1_i32 : 0_i32
      when Type::GtOperator
        l.to_i32 > r.to_i32 ? 1_i32 : 0_i32
      when Type::LtOperator
        l.to_i32 < r.to_i32 ? 1_i32 : 0_i32
      when Type::AndOperator
        l.to_i32 & r.to_i32
      when Type::OrOperator
        l.to_i32 | r.to_i32
      when Type::XorOperator
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
