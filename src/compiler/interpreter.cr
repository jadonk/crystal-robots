module CrystalRobots::Compiler
  class Interpreter
    @@puts_out = Array(String).new

    def self.execute(p : Program)
      retval = Nil
      if p.size > 2
        i = p.size - 2
        j = 0
        while true
          r = executeStatement(p, i, j)
          # puts "#{p[i][j].type.value.chr} -> ret: #{retval}, i: #{r[:i]}, j: #{r[:j]}, exit: #{r[:exit]}}"
          retval = r[:ret]
          if r[:exit]
            break
          end
          i = r[:i]
          j = r[:j]
        end
      end
      retval
    end

    def self.executeStatement(p : Program, i, j)
      stmt = p[i][j]
      stmt_t = stmt.type
      retval = 0_i32
      do_exit = true
      case stmt_t
      when Type::Expression
        cmd = p[i - 1][stmt.index[0]]
        larg = p[i - 1][stmt.index[1]]
        rarg = p[i - 1][stmt.index[2]]
        retval = expression(cmd.type, larg.value, rarg.value)
        j += 2
      when Type::OneArgStatement
        cmd = p[i - 1][stmt.index[0]]
        arg = p[i - 1][stmt.index[1]]
        # puts "calling #{cmd.value}(#{arg.value})"
        retval = oneArgCall(cmd.value, arg.value)
        j += 1
      end
      if j < p[i].size
        do_exit = false
      end
      {"i": i, "j": j, "ret": retval, "exit": do_exit}
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
