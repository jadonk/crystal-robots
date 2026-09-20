require "./field"
require "html"

# The whole-match SVG replay: one renderer, shared by the served `/battle`
# page (`src/web/cgi.cr`'s `svg_animation`, now a thin wrapper over this)
# and the browser build's `crd_battle_run` (`src/browser.cr`) -- the same
# picture wherever the match ran, from the same `Battle::Field`, and only
# one place that needs to draw it.
#
# Maintainer correction on Phase 5b-2 (2026-09-20): the browser page does
# not get its own canvas/JS renderer. `crd_battle_run` returns this SVG
# string alongside the standings; the per-cycle frame log itself stays
# internal to Crystal. Extracted from `cgi.cr` verbatim, which is why the
# comments below still say "Fossil": the SVG itself has no idea which
# server (or none) is serving it.
module CrystalRobots::Battle
  ROBOT_COLORS = ["0x4C97FF", "0xFF8C1A", "0x59C059", "0xFFAB19"]

  # Replay pace in CROBOTS cycles per second (see `svg_animation`'s `cps`).
  # At 300 a motion update lands every 50 ms: a robot at full speed
  # crosses the field in about seven seconds and a missile covers its
  # 700 m range in under a second, the feel of the original curses
  # display.
  ANIM_CPS = 300

  # The whole match as one SVG with native (SMIL) animation: no script,
  # so it works under Fossil's content security policy (and needs no
  # script-src allowance on a static page either). Positions are
  # keyframes at each recorded frame, interpolated linearly in between;
  # everything else (scan, cannon, missiles) switches discretely. Fossil
  # passes raw HTML blocks through.
  def self.svg_animation(field : Field, cps : Int32 = ANIM_CPS) : String
    frames = field.frames
    total = Math.max(1_i64, frames.last.cycle)
    # screen time is proportional to cycles, so the pace is a fixed number
    # of CROBOTS cycles per second however many frames were recorded
    key_times = frames.map { |f| (f.cycle.to_f / total).round(5) }.join(';')
    dur = "#{(total.to_f / cps).round(3)}s"
    String.build do |svg|
      svg << %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="-30 -30 1060 1060" width="520" height="520" role="img" aria-label="battle replay">\n)
      svg << %(<rect x="0" y="0" width="1000" height="1000" fill="#f4f4f0" stroke="#888" stroke-width="3"/>\n)
      field.robots.each_with_index do |robot, i|
        color = "#" + ROBOT_COLORS[i % ROBOT_COLORS.size][2..]
        xs = frames.map { |f| f.robots[i].x // CLICK }
        ys = frames.map { |f| 1000 - f.robots[i].y // CLICK }
        alive = frames.map { |f| f.robots[i].active ? "1" : "0.3" }
        # the trail is drawn as far as the robot has come: a dashed stroke
        # whose visible length follows the path length at each frame
        lengths = [0.0]
        xs.each_index { |k| next if k == 0; lengths << lengths[k - 1] + Math.hypot(xs[k] - xs[k - 1], ys[k] - ys[k - 1]) }
        total_len = Math.max(1.0, lengths.last)
        svg << %(<polyline fill="none" stroke="#{color}" stroke-opacity="0.35" stroke-width="3" stroke-dasharray="#{total_len.round(1)}" points=")
        xs.each_with_index { |x, k| svg << x << ',' << ys[k] << ' ' }
        svg << %(">\n)
        svg << animate("stroke-dashoffset", lengths.map { |l| (total_len - l).round(1) }.join(';'), key_times, dur, "linear")
        svg << "</polyline>\n"
        # the robot: one group translated along the path; inside it the
        # body, the nose (drive heading), the scanner sweep and the cannon
        # barrel rotate about the centre. Screen y points down, so a
        # heading of h degrees is a rotation of -h.
        svg << %(<g>\n)
        svg << animate_transform("translate", xs.each_with_index.map { |x, k| "#{x} #{ys[k]}" }.join(';'), key_times, dur, "linear")
        svg << animate("opacity", alive.join(';'), key_times, dur, "discrete")
        scans = frames.map { |f| -f.robots[i].scan }
        svg << %(<line x1="0" y1="0" x2="160" y2="0" stroke="#{color}" stroke-opacity="0.45" stroke-width="2" stroke-dasharray="6 6">\n)
        svg << animate_transform("rotate", scans.join(';'), key_times, dur, "discrete")
        svg << "</line>\n"
        svg << %(<circle r="14" fill="#{color}" stroke="#000" stroke-width="2"/>\n)
        headings = unwrap(frames.map { |f| -f.robots[i].heading })
        svg << %(<line x1="0" y1="0" x2="30" y2="0" stroke="#000" stroke-width="4" stroke-linecap="round">\n)
        svg << animate_transform("rotate", headings.join(';'), key_times, dur, "linear")
        svg << "</line>\n"
        cannons = frames.map { |f| -f.robots[i].cannon }
        shown = frames.map { |f| f.robots[i].fired ? "1" : "0" }
        svg << %(<line x1="0" y1="0" x2="26" y2="0" stroke="#d00" stroke-width="6" stroke-linecap="butt">\n)
        svg << animate_transform("rotate", cannons.join(';'), key_times, dur, "discrete")
        svg << animate("opacity", shown.join(';'), key_times, dur, "discrete")
        svg << "</line>\n"
        svg << %(<text y="-24" font-size="30" font-family="sans-serif" text-anchor="middle" fill="#222">#{HTML.escape(robot.name)}</text>\n)
        svg << "</g>\n"
      end
      field.robots.each_index do |owner|
        MIS_ROBOT.times do |slot|
          xs = [] of Int32
          ys = [] of Int32
          rs = [] of Int32
          ops = [] of String
          last_x = 0
          last_y = 0
          frames.each do |f|
            m = f.missiles.find { |st| st.owner == owner && st.slot == slot }
            if m
              last_x = m.x // CLICK
              last_y = 1000 - m.y // CLICK
              rs << (m.exploding ? 40 : 7)
              ops << (m.exploding ? "0.25" : "1")
            else
              rs << 0
              ops << "0"
            end
            xs << last_x
            ys << last_y
          end
          next if rs.all?(&.zero?)
          svg << %(<circle r="0" fill="#d00" stroke="#d00" stroke-width="2">\n)
          svg << animate("cx", xs.join(';'), key_times, dur, "discrete")
          svg << animate("cy", ys.join(';'), key_times, dur, "discrete")
          svg << animate("r", rs.join(';'), key_times, dur, "discrete")
          svg << animate("fill-opacity", ops.join(';'), key_times, dur, "discrete")
          svg << "</circle>\n"
        end
      end
      svg << "</svg>"
    end
  end

  private def self.animate(attr : String, values : String, key_times : String, dur : String, mode : String) : String
    %(<animate attributeName="#{attr}" values="#{values}" keyTimes="#{key_times}" dur="#{dur}" calcMode="#{mode}" repeatCount="indefinite"/>\n)
  end

  private def self.animate_transform(type : String, values : String, key_times : String, dur : String, mode : String) : String
    %(<animateTransform attributeName="transform" type="#{type}" values="#{values}" keyTimes="#{key_times}" dur="#{dur}" calcMode="#{mode}" repeatCount="indefinite"/>\n)
  end

  # Angles for linear interpolation: each step takes the short way round,
  # so a turn from 350 to 10 does not spin backwards through 180.
  def self.unwrap(angles : Array(Int32)) : Array(Int32)
    out_angles = [] of Int32
    running = 0
    angles.each_with_index do |a, k|
      if k == 0
        running = a
      else
        d = (a - angles[k - 1]) % 360 # floored: 0..359
        running += d > 180 ? d - 360 : d
      end
      out_angles << running
    end
    out_angles
  end
end
