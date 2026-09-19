# Hunter

Sweeps the field with a wide scan, narrows the scan on whatever it finds,
closes to firing range and keeps shooting while it moves. When it takes
damage it sidesteps for a moment before resuming the hunt.

Inspired by the "seek and destroy" entries from the CROBOTS contests: a
coarse sweep to find a target cheaply, a fine sweep to aim, and a drive
speed that depends on how far away the target is. It never exceeds half
speed, so it can always change heading.

```crystal
# hunter
# wide sweep to find, narrow sweep to aim, close in and keep firing

global(angle, 0)
global(last_damage, 0)

# swing 20 degrees at a time until something is in range
def sweep
  range = scan(angle, 10)
  while range == 0
    angle += 20
    angle %= 360
    range = scan(angle, 10)
  end
  range
end

# narrow the scan to a few degrees around the target
def refine
  best = 0
  offset = -8
  while offset <= 8
    d = scan(angle + offset, 2)
    if d > 0
      angle += offset
      best = d
      offset = 99
    end
    offset += 4
  end
  angle %= 360
  best
end

# drive toward the target, faster when it is far, and shoot
def hunt(range)
  if range > 700
    drive(angle, 45)
  elsif range > 300
    drive(angle, 30)
  else
    drive(angle, 0)
  end
  cannon(angle, range)
end

# burn a few cycles so a manoeuvre has time to happen
def wait(n)
  i = 0
  while i < n
    i += 1
  end
end

# sidestep when hit
def evade
  if damage != last_damage
    last_damage = damage
    drive(angle + 90, 45)
    wait(30)
  end
end

main("Hunter") do
  angle = rand(360)
  while true
    range = sweep
    shots = 0
    while range > 0 && shots < 6
      range = refine
      if range > 0
        hunt(range)
        shots += 1
      end
      evade
    end
    drive(angle, 0)
  end
end
```
