# rook.r  -  scans the battlefield like a rook, i.e., only 0,90,180,270
# move horizontally only, but looks horz and vertically

# global variables
global(d, 0)
global(course, 0)
global(boundary, 955)

main("Rook") do
  # move to center of board
  if loc_y < 500
    drive(90, 70)                             # start moving down
    until (loc_y - 500 >= 20) || (speed == 0) # stop near center
      # continue until near halfway top to bottom
    end
  else
    drive(270, 70)                            # start moving up
    until (loc_y - 500 <= 20) || (speed == 0) # stop near center
      # continue until near halfway top to bottom
    end
  end
  drive(0, 0)

  drive(course, 30)

  # main loop
  while true
    # look all directions
    look(0)
    look(90)
    look(180)
    look(270)

    # if near end of battlefield, change directions
    if course == 0
      if loc_x > boundary || speed == 0
        change
      end
    else
      if loc_x < boundary || speed == 0
        change
      end
    end
  end
end

# look somewhere, and fire cannon repeatedly at in-range target
def look(deg)
  while true
    range = scan(deg, 2)
    if range <= 0 || range > 700
      break
    end
    drive(course, 0)
    cannon(deg, range)
    if d + 20 != damage
      d = damage
      change
    end
  end
end

def change
  if course == 0
    boundary = 5
    course = 180
  else
    boundary = 995
    course = 0
  end
  drive(course, 30)
end
