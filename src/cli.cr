require "option_parser"
require "./version"
require "./compiler/program"
require "./compiler/parser"
require "./compiler/checker"
require "./compiler/interpreter"
require "./compiler/wasm_emitter"
require "./compiler/disassembler"

module CrystalRobots::CLI
  private def self.parsed_program(file : String) : Compiler::Program
    Compiler::Parser.new(File.read(file)).program
  rescue e : Compiler::Parser::Error
    abort e.message
  end

  # Parses and checks `file`, printing every issue and exiting nonzero if
  # the checker finds any -- the gate `-c` and `-i` both run through
  # before compiling or interpreting a program that does not mean
  # anything.
  private def self.checked_program(file : String) : Compiler::Program
    program = parsed_program(file)
    issues = Compiler::Checker.check(program)
    unless issues.empty?
      issues.each { |issue| STDERR.puts issue.to_s }
      exit 1
    end
    program
  end

  def self.run(argv : Array(String)) : Nil
    mode = :help
    output = nil
    parser = OptionParser.new do |p|
      p.banner = "Usage: crystal-robots [options] FILE"
      p.on("-v", "--version", "Print the version") { puts "crystal-robots #{VERSION}"; exit }
      p.on("-t", "--trace", "Print the parser's derivation, one line per pass") { mode = :trace }
      p.on("-k", "--check", "Run the checker and print any issues found") { mode = :check }
      p.on("-c", "--compile", "Compile to a WebAssembly module (needs -o)") { mode = :compile }
      p.on("-d", "--disassemble", "Compile and print a readable instruction dump") { mode = :disassemble }
      p.on("-i", "--interpret", "Run in the reference interpreter") { mode = :interpret }
      p.on("-o FILE", "--output=FILE", "Where -c writes the WebAssembly module") { |f| output = f }
      p.on("-h", "--help", "Show this help") { puts p; exit }
    end
    parser.parse(argv)
    file = argv.first?

    case mode
    when :trace
      print parsed_program(file || abort "usage: crystal-robots -t FILE").derivation
    when :check
      issues = Compiler::Checker.check(parsed_program(file || abort "usage: crystal-robots -k FILE"))
      issues.each { |issue| puts issue.to_s }
      puts "no issues found" if issues.empty?
    when :compile
      program = checked_program(file || abort "usage: crystal-robots -c FILE -o OUT")
      out_file = output
      abort("usage: crystal-robots -c FILE -o OUT") unless out_file
      File.write(out_file, Compiler::WASM_Emitter.new(program).to_wasm)
    when :disassemble
      program = checked_program(file || abort "usage: crystal-robots -d FILE")
      print Compiler::Disassembler.disassemble(Compiler::WASM_Emitter.new(program).to_wasm)
    when :interpret
      program = checked_program(file || abort "usage: crystal-robots -i FILE")
      Compiler::Interpreter.execute(program, Compiler::ConsoleHost.new)
    else
      puts "crystal-robots #{VERSION}: nothing to do yet, see --help"
    end
  end
end

CrystalRobots::CLI.run(ARGV)
