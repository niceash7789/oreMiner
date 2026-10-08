local Reporting = {}

function Reporting.log(sink, ...)
    if type(sink) ~= "function" then return false end
    local ok = pcall(sink, ...)
    return ok
end

return Reporting
