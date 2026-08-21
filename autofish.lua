--!nocheck
-- Standalone Auto Fishing entry point.
local source = "https://raw.githubusercontent.com/amarnazhan27-gif/IDHscrip/main/NazhanHub.lua"
loadstring(game:HttpGet(source))()
task.wait(0.5)
local env = (getgenv and getgenv()) or shared
assert(env.IDHHub, "IDH Hub gagal dimuat")
env.IDHHub.setFishing(true, false)
