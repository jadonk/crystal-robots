# ## Parser
#
# Let's see if the doc tool allows more sophisticated markdown here
#
# I ultimately want to end up with an array of statments. Statements will typically have
# arguments at previous levels.
#
# https://en.wikipedia.org/wiki/Abstract_syntax_tree
#
# ```
# bottom (0): [[ type : Type, value : String, line, column, [..args..]], ...]
#        (1): [[ type : Type, .., [index0_in_0, index1_in_0, ...]], ...]
#    top (n): [[ type : Type = Statement, .., [..args..]], ...]
# ```
module CrystalRobots::Compiler
  class Parser
    def self.parser(tokens)
    end
  end
end
