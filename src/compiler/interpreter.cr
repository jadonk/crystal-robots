module CrystalRobots::Compiler
  class Interpreter
    def self.execute(p : Program)
      retval = Nil
      if p.size > 2
        while true
          i = p.size - 2
          j = 0
          r = executeStatement(p, i, j)
          puts "#{p[i][j].type.value.chr} -> #{r[:ret]}"
          i = r[:i]
          j = r[:j]
          if r[:exit]
            retval = r[:ret]
            break
          end
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
      when Type::OneArgStatement
        cmd = p[i - 1][stmt.index[0]]
        arg = p[i - 1][stmt.index[1]]
        puts "calling #{cmd.value}(#{arg.value})"
        retval = oneArgCall(cmd.value, arg.value)
        j += 1
        if j < p[i].size
          do_exit = false
        end
      end
      {"i": i, "j": j, "ret": retval, "exit": do_exit}
    end

    def self.oneArgCall(name, arg0)
      case name
      when "puts"
        r = puts arg0
        if r.nil?
          r = 0_i32
        else
          r = r.to_i32
        end
      end
    end
  end
end
