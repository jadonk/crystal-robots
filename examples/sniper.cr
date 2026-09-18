# sniper
# strategy: since a scan of the entire battlefield can be done in 90
# degrees from a corner, sniper can scan the field quickly.

# global variables, that can be used by any function
global(corner, 1) # current corner 1, 2, 3 or 4
global(sc, 0)     # current scan start
global(d, 0)      # last damage check

# Corner constants n : x, y, and starting scan direction
C1X = 10; C1Y = 10; S1  =  0
C2X = 10; C2Y = 990; S2  = 270
C3X = 990; C3Y = 990; S3  = 180
C4X = 990; C4Y = 10; S4 = 90

main("Sniper") do
  closest = 9999 # check for targets in range
  range = 0      # range to target
  dir = 0        # scan direction
  new_corner     # start at a random corner
  d = damage     # get current damage
  dir = sc       # starting scan direction

  while true               # loop is executed forever
    while dir < sc + 90    # scan through 90 degree range
      range = scan(dir, 1) # look at a direction
      if range <= 700 && range > 0
        while range > 0        # keep firing while in range
          closest = range      # set closest flag
          cannon(dir, range)   # fire!
          range = scan(dir, 1) # check target again
          if d + 15 > damage   # sustained several hits,
            range = 0          # goto new corner
          end
        end
        dir -= 10 # back up scan, in case
      end

      dir += 2       # increment scan
      if d != damage # check for damage incurred
        new_corner   # we're hit, move now
        d = damage
        dir = sc
      end
    end

    if closest == 9999 # check for any targets in range
      new_corner       # nothing, move to new corner
      d = damage
      dir = sc
    else # targets in range, resume
      dir = sc
    end
    closest = 9999
  end
end # end of main

# new corner method to move to a different corner
def new_corner
  newc = rand(4)            # pick a random corner
  if newc == corner         # but make it different than the
    corner = (newc % 4) + 1 # current corner
  else
    corner = newc
  end
  case corner # set new x,y and scan start
  when 1
    x = C1X
    y = C1Y
    sc = S1
  when 2
    x = C2X
    y = C2Y
    sc = S2
  when 3
    x = C3X
    y = C3Y
    sc = S3
  else
    x = C4X
    y = C4Y
    sc = S4
  end

  # find the heading we need to get to the desired corner
  angle = plot_course(x, y)

  # start drive train, full speed
  drive(angle, 100)

  # keep traveling until we are within 100 meters
  # speed is checked in case we run into wall, other robot
  # not terribly great, since were are doing nothing while moving

  until (distance(loc_x, loc_y, x, y) <= 100) || (speed == 0)
    # wait until we are within 100m or we stop
  end

  # cut speed, and creep the rest of the way

  drive(angle, 20)
  until (distance(loc_x, loc_y, x, y) <= 10) || (speed == 0)
    # wait until distance is within 10m or we stop
  end

  # stop drive, should coast in the rest of the way
  drive(angle, 0)
end # end of new_corner

# classical pythagorean distance formula
def distance(x1, y1, x2, y2)
  x = x1 - x2
  y = y1 - y2
  sqrt((x*x) + (y*y))
end

# plot course function, return degree heading to
# reach destination x, y; uses `atan` trig function
def plot_course(xx, yy)
  scale = 100000 # scale for trig functions
  curx = loc_x   # get current location
  cury = loc_y
  x = curx - xx
  y = cury - yy

  # atan only returns -90 to +90, so figure out how to use
  # the `atan` value

  if x == 0 # x is zero, we either move due north or south
    if yy > cury
      d = 90 # north
    else
      d = 270 # south
    end
  else
    if yy < cury
      if xx > curx
        d = 360 + atan((scale * y) / x) # south-east, quadrant 4
      else
        d = 180 + atan((scale * y) / x) # south-west, quadrant 3
      end
    else
      if xx > curx
        d = atan((scale * y) / x) # north-east, quadrant 1
      else
        d = 180 + atan((scale * y) / x) # north-west, quadrant 2
      end
    end
  end
  d
end # end of plot_course
