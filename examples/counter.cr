# counter
# scan in a counter-clockwise direction (increasing degrees)
# moves when hit

main("Counter") do
  res = 1
  d = damage
  angle = rand(360)
  while true
    while ((range = scan(angle, res)) > 0)
      if (range > 700) # out of range, head toward it
        drive(angle, 50)
        i = 1
        while (i < 50)
          i += 1 # use a counter to limit move time
        end
        drive(angle, 0)
        if (d != damage)
          d = damage
          run
        end
        angle -= 3
      else
        cannon(angle, range)
        while (cannon(angle, range) == 0)
        end
        if (d != damage)
          d = damage
          run
        end
        angle -= 15
      end
    end
    if (d != damage)
      d = damage
      run
    end
    angle += res
    angle %= 360
  end
end

global(last_dir, 0)

# run moves around the center of the field
def run
  i = 0
  x = loc_x
  y = loc_y

  if (last_dir == 0)
    if (y > 512)
      last_dir = 1
      drive(270, 100)
      while (y - 100 < loc_y && i < 100)
        i += 1
      end
      drive(270, 0)
    else
      last_dir = 1
      drive(90, 100)
      while (y + 100 > loc_y && i < 100)
        i += 1
      end
      drive(90, 0)
    end
  else
    if (x > 512)
      last_dir = 0
      drive(180, 100)
      while (x - 100 < loc_x && i < 100)
        i += 1
      end
      drive(180, 0)
    else
      last_dir = 0
      drive(0, 100)
      while (x + 100 > loc_x && i < 100)
        i += 1
      end
      drive(0, 0)
    end
  end
end # end of counter.cr
