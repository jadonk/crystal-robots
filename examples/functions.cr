global(total, 0)

def add(a, b)
sum = a + b
total = total + sum
sum
end

main("Adder") do
puts add(2, 3)
puts add(10, 20)
puts total
end
