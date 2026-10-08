local Status = {}

function Status.phase(name, current, total, detail)
    local line = string.format("[%s] %d/%d %s", name, current, total, detail)
    return line:sub(1, 32)
end

function Status.branchComplete(current, total, blocks, fuel)
    local line = string.format("[DONE] pair %d/%d B:%d F:%s", current, total, blocks, tostring(fuel))
    return line:sub(1, 32)
end

return Status
