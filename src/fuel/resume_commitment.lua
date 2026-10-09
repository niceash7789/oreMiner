-- Computes the fuel needed to travel home, resume to the checkpoint, and
-- perform one bounded work step while retaining the configured reserve.
local Commitment = {}

function Commitment.targetFuel(homeRouteMoves, reserve, workStepMoves)
    workStepMoves = workStepMoves or 1
    if type(homeRouteMoves) ~= "number" or homeRouteMoves < 0
        or homeRouteMoves ~= math.floor(homeRouteMoves)
        or type(reserve) ~= "number" or reserve < 0 or reserve ~= math.floor(reserve)
        or type(workStepMoves) ~= "number" or workStepMoves < 1
        or workStepMoves ~= math.floor(workStepMoves) then
        return nil, "INVALID_RESUME_COMMITMENT"
    end
    return (homeRouteMoves * 2) + reserve + workStepMoves
end

-- Resume has two possibly different legs: checkpoint -> origin, then origin
-- -> checkpoint. Keep the estimate explicit so stair replay cannot be hidden
-- by a zero-length checkpoint-to-target graph path.
function Commitment.targetFuelForTrips(homeMoves, resumeMoves, reserve, workStepMoves)
    workStepMoves = workStepMoves or 1
    if type(homeMoves) ~= "number" or homeMoves < 0 or homeMoves ~= math.floor(homeMoves)
        or type(resumeMoves) ~= "number" or resumeMoves < 0 or resumeMoves ~= math.floor(resumeMoves)
        or type(reserve) ~= "number" or reserve < 0 or reserve ~= math.floor(reserve)
        or type(workStepMoves) ~= "number" or workStepMoves < 1
        or workStepMoves ~= math.floor(workStepMoves) then
        return nil, "INVALID_RESUME_COMMITMENT"
    end
    return homeMoves + resumeMoves + reserve + workStepMoves
end

return Commitment
