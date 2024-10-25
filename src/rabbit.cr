# rabbit
# rabbit runs around the field, randomly
# and never fires;  use as a target

require "robot"

rabbit = Robot.new("Rabbit")

rabbit.main do |r|
  while true
    go(r,rand(1000),rand(1000))   # go somewhere on the field
  end
end

# go - go to the point specified
def go(r,dest_x,dest_y)
  course = plot_course(r,dest_x,dest_y)
  r.drive(course,25)
  while distance(r.loc_x(),r.loc_y(),dest_x,dest_y) > 50
    # continue while distance is greater than 50
  end
  r.drive(course,0)
  while r.speed() > 0
    # continue while speed is greater than 0
  end
end

# distance formula
def distance(x1, y1, x2, y2)
  x = x1 - x2
  y = y1 - y2
  sqrt((x*x)+(y*y))
end

# plot_course - figure out which heading to go
def plot_course(r, xx, yy)
  scale = 100000 # scale for trig functions
  curx = r.loc_x()
  cury = r.loc_y()
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
