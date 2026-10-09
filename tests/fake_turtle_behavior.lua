local FakeTurtle = require("tests.fake_turtle")

local turtle = FakeTurtle.new({ x = 0, y = 0, z = 0, facing = 0 }, {
    forward = { false, true },
    turn_right = { true, false },
})

assert(turtle:move("forward") == false)
assert(turtle.pose.z == 0, "failed configured movement must not change pose")
assert(turtle:move("forward") == true)
assert(turtle.pose.z == -1, "successful configured movement changes pose")
assert(turtle:turn("right") == true and turtle.pose.facing == 1)
assert(turtle:turn("right") == false and turtle.pose.facing == 1,
    "failed configured turn must not change facing")
assert(turtle:callCount("forward") == 2 and turtle:callCount("turn_right") == 2)

turtle:setOutcomes("up", { true })
assert(turtle:move("up") == true and turtle.pose.y == 1)

print("fake turtle behavior checks passed")
