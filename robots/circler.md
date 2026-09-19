# Circler

Patrols a square around the middle of the field and fires at anything its
sweeping scanner finds on the way. Never stops moving, so it is a hard
target for corner snipers, and it is always within missile range of the
center.

Borrows `plot_course` and `distance` from the `rabbit` example, which are
the standard CROBOTS way to steer toward a point, and stays under half
speed so each corner turn takes without stopping.

```crystal
# circler
# square patrol around the middle, shooting at whatever the sweep finds

global(leg, 0)
global(course, 0)

def target_x
  if leg == 0 || leg == 3
    300
  else
    700
  end
end

def target_y
  if leg < 2
    300
  else
    700
  end
end

# distance formula
def distance(x1, y1, x2, y2)
  x = x1 - x2
  y = y1 - y2
  sqrt((x * x) + (y * y))
end

# plot_course - figure out which heading to go
def plot_course(xx, yy)
  scale = 100000
  curx = loc_x
  cury = loc_y
  x = curx - xx
  y = cury - yy
  if x == 0
    if yy > cury
      d = 90
    else
      d = 270
    end
  else
    if yy < cury
      if xx > curx
        d = 360 + atan((scale * y) / x)
      else
        d = 180 + atan((scale * y) / x)
      end
    else
      if xx > curx
        d = atan((scale * y) / x)
      else
        d = 180 + atan((scale * y) / x)
      end
    end
  end
  d
end

# one full sweep, firing at anything in missile range
def look
  a = 0
  while a < 360
    r = scan(a, 10)
    if r > 0 && r <= 700
      cannon(a, r)
    end
    a += 20
  end
end

main("Circler") do
  while true
    course = plot_course(target_x, target_y)
    drive(course, 45) # under half speed, so the next turn is allowed
    while distance(loc_x, loc_y, target_x, target_y) > 60
      look
    end
    leg += 1
    leg %= 4
  end
end
```
