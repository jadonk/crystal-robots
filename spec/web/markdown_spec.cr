require "../spec_helper"

alias Markdown = CrystalRobots::Web::Markdown

describe Markdown do
  it "fences plain text with three backticks" do
    Markdown.fence("puts 1\n").should eq "```\nputs 1\n\n```\n"
  end

  it "sizes the fence longer than any run of backticks already in the text" do
    text = "```crystal\nnice try\n```\n"
    fenced = Markdown.fence(text)
    fenced.should start_with "````\n"
    fenced.should end_with "````\n"
  end

  it "escapes markdown syntax characters in prose" do
    Markdown.escape("a *b* [c](d) `e`").should eq "a \\*b\\* \\[c\\]\\(d\\) \\`e\\`"
  end
end
