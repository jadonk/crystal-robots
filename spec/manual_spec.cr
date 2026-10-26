require "./spec_helper"
require "html"

describe "public manual examples" do
  html = File.read("site/manual/index.html")
  blocks = html.scan(/<pre><code class="language-crystal-robots"(.*?)>(.*?)<\/code><\/pre>/m)

  it "contains complete robot examples" do
    blocks.size.should be >= 3
  end

  blocks.each_with_index do |block, index|
    next if block[1].includes?("data-fragment")

    it "parses and checks example #{index + 1}" do
      source = HTML.unescape(block[2])
      program = C::Program.new(source)
      C::Parser.try_parse(program).should be_nil
      C::Checker.check(program).should be_empty
    end
  end
end
