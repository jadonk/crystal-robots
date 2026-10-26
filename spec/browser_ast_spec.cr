require "./spec_helper"
require "../src/browser"

private def native_ast(source : String) : JSON::Any
  ptr = CrystalRobots::Browser.alloc(source.bytesize)
  ptr.copy_from(source.to_unsafe, source.bytesize)
  CrystalRobots::Browser.ast
  JSON.parse(String.new(Bytes.new(CrystalRobots::Browser.ast_result_ptr, CrystalRobots::Browser.ast_result_len)))
end

describe "CrystalRobots::Browser.ast" do
  it "returns a source-linked tree of typed nodes" do
    report = native_ast("puts 19\n")
    report["error"].raw.should be_nil
    root = report["root"]
    root["type"].as_s.should eq "Program"
    root["line"].as_i.should eq 1
    root["col"].as_i.should eq 1
    root["children"].as_a.should_not be_empty
    root["children"][0]["children"].as_a.should_not be_empty
  end

  it "returns a parse error as data, then still parses the next source" do
    failed = native_ast("puts {{{")
    failed["root"].raw.should be_nil
    failed["error"]["message"].as_s.should contain "Unexpected character"
    failed["error"]["line"].as_i.should eq 1
    native_ast("puts 1")["error"].raw.should be_nil
  end
end
