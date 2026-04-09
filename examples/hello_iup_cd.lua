-- examples/hello_iup_cd.lua
-- Minimal test: open a window, draw a line, keep it open.
-- Run this FIRST to verify IUP+CD are installed correctly.
--
-- Expected: a window appears with a red diagonal line on black background.
-- Close the window to exit.
--
-- If this fails, check your IUP/CD installation:
--   https://sourceforge.net/projects/iup/files/
--
-- Usage: lua5.4 examples/hello_iup_cd.lua

require("iuplua")
require("cdlua")
require("iupluacd")

-- Try context plus for alpha/anti-aliasing (not fatal if missing)
pcall(function()
    require("cdluacontextplus")
    cd.UseContextPlus(1)
    print("Context Plus: enabled (alpha + anti-aliasing)")
end)

local cv_canvas = nil

local cnv = iup.canvas{
    bgcolor = "0 0 0",
    rastersize = "600x400",
}

function cnv:map_cb()
    local cv = cd.CreateCanvas(cd.IUP, self)
    cv_canvas = cd.CreateCanvas(cd.DBUFFER, cv)
end

function cnv:action()
    if not cv_canvas then return end
    cv_canvas:Activate()
    cv_canvas:Background(cd.EncodeColor(0, 0, 0))
    cv_canvas:Clear()

    -- Draw a red line
    cv_canvas:SetForeground(cd.EncodeColor(255, 0, 0))
    cv_canvas:LineWidth(3)
    cv_canvas:Line(50, 50, 550, 350)

    -- Draw green text
    cv_canvas:SetForeground(cd.EncodeColor(0, 255, 0))
    cv_canvas:Font("Helvetica", cd.PLAIN, 18)
    cv_canvas:Text(50, 370, "IUP + CD works! Close this window to exit.")

    -- Draw a blue circle
    cv_canvas:SetForeground(cd.EncodeColor(0, 100, 255))
    cv_canvas:LineWidth(2)
    cv_canvas:Arc(300, 200, 100, 100, 0, 360)

    cv_canvas:Flush()
end

local dlg = iup.dialog{
    cnv;
    title = "IUP + CD Hello World",
}

dlg:showxy(iup.CENTER, iup.CENTER)
cnv.rastersize = nil  -- allow user resize

print("IUP version: " .. iup.Version())
print("CD version:  " .. cd.Version())
print("Window open. Close it to exit.")

iup.MainLoop()
iup.Close()

print("Done.")
