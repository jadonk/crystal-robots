# Turret

Stays put and spins a fine scanner. When it sees something it fires twice,
once at the coarse bearing and once after a one-degree scan. It only moves
when hit, and then just far enough to spoil the shooter's aim.

The opposite of `dodger`: all cannon, almost no drive. Good for testing a
robot that is supposed to find and hit a stationary target.

```crystal
# turret
# spin the scanner, fire twice, move only when hit

global(d, 0)
global(a, 0)

# burn cycles so the drive has time to move us
def wait(n)
  i = 0
  while i < n
    i += 1
  end
end

main("Turret") do
  while true
    r = scan(a, 5)
    if r > 0 && r <= 700
      cannon(a, r)
      r = scan(a, 1)
      if r > 0
        cannon(a, r)
      end
    else
      a += 10
      a %= 360
    end
    if damage != d
      d = damage
      drive(a + 180, 100)
      wait(40)
      drive(a, 0)
    end
  end
end
```
