# Wallhugger

Runs the perimeter at full speed and scans across the field toward the
middle as it goes. Like the `rook` example it only ever travels along the
axes, and like every CROBOTS robot it has to slow below half speed before a
turn will take, so it brakes at each corner.

```crystal
# wallhugger
# perimeter runner: east, north, west, south, scanning inward

global(side, 0)

def next_heading
  if side == 0
    0
  elsif side == 1
    90
  elsif side == 2
    180
  else
    270
  end
end

# 1 when the wall ahead is close
def at_wall
  h = next_heading
  if h == 0
    loc_x > 940
  elsif h == 90
    loc_y > 940
  elsif h == 180
    loc_x < 60
  else
    loc_y < 60
  end
end

# a heading change only takes at 50 percent speed or less: stop, wait,
# then drive off on the new heading
def turn_to(h)
  drive(h, 0)
  while speed > 40
    scan_inward
  end
  drive(h, 100)
end

# scan a 120 degree fan toward the middle of the field
def scan_inward
  center = next_heading + 90
  a = center - 60
  while a <= center + 60
    r = scan(a, 10)
    if r > 0 && r <= 700
      cannon(a, r)
    end
    a += 15
  end
end

main("Wallhugger") do
  # get onto the bottom wall first, so the first leg runs east with the
  # field to the north
  drive(270, 100)
  while loc_y > 60
    scan_inward
  end
  while true
    turn_to(next_heading)
    while at_wall == 0
      scan_inward
    end
    side += 1
    side %= 4
  end
end
```
