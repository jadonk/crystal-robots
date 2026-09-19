require "../spec_helper"

alias RobotAPI = CrystalRobots::Web::RobotAPI

describe RobotAPI do
  it "documents exactly the builtins the interpreter actually dispatches, no more and no less" do
    RobotAPI::ENTRIES.keys.sort.should eq CrystalRobots::Compiler::Interpreter::BUILTIN_NAMES.sort
  end

  it "every name in BUILTIN_NAMES is a real, callable builtin, not just a documentation entry" do
    # `puts` itself is exercised by every line here (it is how each
    # result gets observed at all), so there is no separate line for
    # it: 14 lines cover the other 14 names in BUILTIN_NAMES.
    source = <<-CR
      puts damage
      puts speed
      puts loc_x
      puts loc_y
      puts sleep
      puts rand(5)
      puts sqrt(16)
      puts sin(30)
      puts cos(30)
      puts tan(30)
      puts atan(1)
      puts scan(1, 2)
      puts cannon(1, 2)
      puts drive(1, 2)
      CR
    interpret_puts(source).size.should eq CrystalRobots::Compiler::Interpreter::BUILTIN_NAMES.size - 1
  end

  describe ".panel" do
    panel = RobotAPI.panel("/ext/crystal-robots/docs")

    it "renders every group heading and one entry per builtin, with a cost and an example" do
      RobotAPI::GROUPS.each { |g| panel.should contain g }
      RobotAPI::ENTRIES.each_value do |e|
        panel.should contain e.signature
        panel.should contain e.example
      end
      panel.should contain "Costs #{CrystalRobots::Compiler::Interpreter::Costs.new.builtin} cycles"
    end

    it "links back to the docs page and has no script element, for Fossil's content security policy" do
      panel.should contain %(href="/ext/crystal-robots/docs")
      panel.should_not contain "<script"
    end
  end
end
