require "../battle/field"

# A static Pikchr diagram of a battlefield: a square for the field's
# boundary, one dot per robot at its final position (gray once dead),
# labeled with its name. Fossil renders a fenced ```pikchr block itself
# (https://fossil-scm.org/home/doc/trunk/www/pikchr.md), same as any
# other Markdown fence -- this only builds the diagram's source text.
module CrystalRobots::Web::Pikchr
  SIZE = 4.0 # inches

  def self.field(field : Battle::Field) : String
    max = (Battle::MAX_X * Battle::CLICK).to_f
    String.build do |io|
      io << "box wid #{SIZE} ht #{SIZE} with .sw at (0,0) fill white\n"
      field.robots.each do |r|
        x = (r.x.to_f / max * SIZE).round(2)
        y = (r.y.to_f / max * SIZE).round(2)
        color = r.alive? ? "blue" : "gray"
        label = r.name.gsub('"', '\'')
        suffix = r.alive? ? "" : " (dead)"
        io << %(dot at (#{x},#{y}) color #{color} "#{label}#{suffix}" above\n)
      end
    end
  end
end
