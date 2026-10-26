require "./spec_helper"
require "json"

describe "site/robots.json" do
  wasm32_it "bundles the five documented robots with their code and first-paragraph descriptions" do
    catalog = JSON.parse(File.read("site/robots.json")).as_a
    catalog.size.should eq 10
    %w(hunter circler dodger wallhugger turret).each do |name|
      robot = catalog.find { |entry| entry["name"].as_s == name }.not_nil!
      markdown = File.read("robots/#{name}.md")
      code = markdown.match(/```(?:crystal)?\s*\n(.*?)\n```/m).not_nil![1]
      description = markdown.split(/\n\s*\n/)[1].lines.map(&.strip).join(" ")
      robot["source"].as_s.should eq "#{code}\n"
      robot["origin"].as_s.should eq "robot"
      robot["description"].as_s.should eq description
    end
    catalog.first(5).each do |robot|
      robot["origin"].as_s.should eq "example"
      robot["description"].as_s.should_not be_empty
    end
  end
end
