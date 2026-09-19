require "../battle/field"
require "../tournament/tournament"

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

  private def self.safe(text : String) : String
    text.gsub('"', '\'')
  end

  # A schematic tournament ladder: pools left to right in one row, each
  # completed bracket round in its own row below, the champion (once
  # known) at the bottom. Rows sit at a fixed gap rather than hugging
  # their own content, so a round with more matches than the one above
  # it never overlaps that row.
  def self.ladder(pools : Array(Tournament::PoolResult), rounds : Array(Tournament::Round), champion : String?) : String
    String.build do |io|
      io << "boxwid = 1.3in; boxht = 0.35in\n"
      pools.each_with_index do |pool, i|
        name = "PL#{i}"
        top = pool.standings.first?
        label = "Pool #{('A'.ord + i).chr}"
        if i == 0
          io << %(#{name}: box "#{label}" bold fill lightblue\n)
        else
          io << %(#{name}: box "#{label}" bold fill lightblue with .w at PL#{i - 1}.e + (0.3in,0)\n)
        end
        io << %(text "#{top ? "#{safe(top.name)} #{top.points}pt" : "-"}" small with .n at #{name}.s\n)
      end
      rounds.each_with_index do |round, ri|
        gap = (ri + 1) * 1.0
        round.matches.each_with_index do |m, mi|
          name = "RD#{ri}_#{mi}"
          versus = "#{safe(m.entrants[0] || "bye")} v #{safe(m.entrants[1] || "bye")}"
          if mi == 0
            io << %(#{name}: box "#{round.label}" bold fill khaki with .n at PL0.s - (0,#{gap}in)\n)
          else
            io << %(#{name}: box "#{round.label}" bold fill khaki with .w at RD#{ri}_#{mi - 1}.e + (0.3in,0)\n)
          end
          io << %(text "#{versus}" small with .n at #{name}.s\n)
          io << %(text "winner: #{safe(m.winner)}" small with .n at last.s\n)
        end
      end
      if champion
        gap = (rounds.size + 1) * 1.0
        io << %(CH: box "Champion" bold fill gold with .n at PL0.s - (0,#{gap}in)\n)
        io << %(text "#{safe(champion)}" bold with .n at CH.s\n)
      end
      # Each fight's winner flows down into the next round's slot (match
      # `mi` of round `ri` feeds match `mi // 2` of round `ri + 1`, the
      # same pairing Tournament.play_bracket_round used to build it), and
      # the final's winner flows into the champion box.
      rounds.each_with_index do |round, ri|
        if rounds[ri + 1]?
          round.matches.each_index { |mi| io << "arrow from RD#{ri}_#{mi}.s to RD#{ri + 1}_#{mi // 2}.n\n" }
        elsif champion
          io << "arrow from RD#{ri}_0.s to CH.n\n"
        end
      end
    end
  end

  def self.trophy(champion : String) : String
    String.build do |io|
      io << "CUP: ellipse wid 1.1in ht 0.6in fill gold\n"
      io << "STEM: box wid 0.16in ht 0.35in fill gold with .n at CUP.s\n"
      io << "box wid 0.7in ht 0.12in fill gold with .n at STEM.s\n"
      io << %(text "#{safe(champion)}" big bold at CUP.n + (0,0.35in)\n)
    end
  end
end
