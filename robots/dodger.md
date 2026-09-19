# Dodger

Never sits still. It picks a new random heading after every scan sweep,
fires at the first thing it sees, and turns away from the walls before it
hits them. Being hard to hit is its whole strategy.

```crystal
# dodger
# random headings, a quick sweep between turns, and wall avoidance

global(heading, 0)

# bounce the heading off a wall that is getting close
def clamp_heading
  x = loc_x
  y = loc_y
  if x < 100 && heading > 90 && heading < 270
    heading = 360 - heading
  end
  if x > 900 && (heading < 90 || heading > 270)
    heading = 180 - heading
  end
  if y < 100 && heading > 180
    heading = 360 - heading
  end
  if y > 900 && heading < 180
    heading = 360 - heading
  end
  heading %= 360
end

# coarse sweep, then a fine shot at anything found
def sweep_and_fire
  a = 0
  while a < 360
    r = scan(a, 10)
    if r > 0
      cannon(a, r)
      r = scan(a, 2)
      if r > 0
        cannon(a, r)
      end
    end
    a += 20
  end
end

main("Dodger") do
  heading = rand(360)
  while true
    clamp_heading
    drive(heading, 45) # under half speed, so every new heading takes
    sweep_and_fire
    heading += rand(90) - 45
    if speed == 0
      heading = rand(360)
    end
  end
end
```
