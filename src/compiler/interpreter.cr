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
      case stmt_t
      when Type::OneArgStatement
        cmd = p[i-1][stmt.index[0]]
        arg = p[i-1][stmt.index[1]]
        puts "calling #{cmd.value}(#{arg.value})"
      end
      {"i": 0, "j": 0, "ret": "success", "exit": true}
    end
  end
end
