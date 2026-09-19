require "../spec_helper"

alias PikchrDiagram = CrystalRobots::Web::Pikchr

describe PikchrDiagram do
  it "draws a box for the field and one dot per robot, colored by whether it is alive" do
    field = CrystalRobots::Battle::Field.new(["Alice", "Bob"], seed: 1)
    field.robots[1].status = :dead
    diagram = PikchrDiagram.field(field)
    diagram.should contain "box wid"
    diagram.should contain %("Alice")
    diagram.should contain %("Bob (dead)")
    diagram.should contain "color blue"
    diagram.should contain "color gray"
  end

  it "quotes a robot name containing a double quote safely" do
    field = CrystalRobots::Battle::Field.new([%(Weird"Name)], seed: 1)
    diagram = PikchrDiagram.field(field)
    diagram.should_not contain %("Weird"Name")
    diagram.should contain "Weird'Name"
  end
end
