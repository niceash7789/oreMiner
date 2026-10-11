-- Tests validate the tracked example while exposing it under the same module
-- name used by the installed runtime.
local chunk, loadError = loadfile("config.example.lua")
assert(chunk, loadError)
local config = chunk()
package.loaded["config"] = config
return config

