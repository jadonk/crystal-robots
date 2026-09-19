require "../spec_helper"

# fossil-skin/mainmenu is not Crystal code: it is Fossil's own top-nav
# menu file for the skin this repository's server deploys, one line
# per entry (NAME URL CAPABILITY-EXPR {CSS-CLASSES}, brace-grouped
# fields kept together the way Fossil itself splits them). There is
# nothing here for `crystal spec` to run; this spec instead pins the
# one line crystal-robots actually depends on, so a future edit to
# the shared skin cannot silently point "Run" somewhere else or drop
# it from the menu without a spec failure.
private def mainmenu_fields(line : String) : Array(String)
  fields = [] of String
  line.scan(/\{[^}]*\}|\S+/) { |m| fields << m[0] }
  fields
end

describe "fossil-skin/mainmenu" do
  lines = File.read_lines("fossil-skin/mainmenu").reject(&.blank?)

  it "gives every entry a name, a link, a capability expression and a class list" do
    lines.each do |line|
      mainmenu_fields(line).size.should eq 4
    end
  end

  it "links the Run entry to this app's extroot path with host or admin capability" do
    run_line = lines.find { |line| mainmenu_fields(line)[0] == "Run" }
    run_line.should_not be_nil
    fields = mainmenu_fields(run_line.not_nil!)
    fields[1].should eq "/ext/crystal-robots"
    fields[2].should eq "{h z}"
  end
end
