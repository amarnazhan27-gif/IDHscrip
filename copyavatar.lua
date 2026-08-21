-- Standalone Copy Avatar entry point.
local source = "https://raw.githubusercontent.com/amarnazhan27-gif/IDHscrip/main/NazhanHub.lua"
loadstring(game:HttpGet(source))()
task.wait(0.5)
local env = (getgenv and getgenv()) or shared
assert(env.IDHHub, "IDH Hub gagal dimuat")

-- Contoh:
-- local ok, message = env.IDHHub.copyAvatar("NamaPlayer")
-- print(ok, message)
return env.IDHHub.copyAvatar
