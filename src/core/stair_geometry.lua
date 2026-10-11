local StairGeometry = {
    MIN_STEPS = 4,
    MAX_STEPS = 64,
}

function StairGeometry.stepsForFloor(interval, firstFloorDepthOffset, floor)
    if type(interval) ~= "number" or interval ~= math.floor(interval)
        or interval < StairGeometry.MIN_STEPS or interval > StairGeometry.MAX_STEPS
        or type(firstFloorDepthOffset) ~= "number"
        or firstFloorDepthOffset ~= math.floor(firstFloorDepthOffset)
        or firstFloorDepthOffset < 0
        or interval + firstFloorDepthOffset > StairGeometry.MAX_STEPS
        or type(floor) ~= "number" or floor ~= math.floor(floor) or floor < 1 then
        return nil
    end
    return interval + (floor == 1 and firstFloorDepthOffset or 0)
end

return StairGeometry
