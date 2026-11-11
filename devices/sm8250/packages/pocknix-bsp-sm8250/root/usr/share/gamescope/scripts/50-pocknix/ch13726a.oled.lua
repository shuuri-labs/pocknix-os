-- No EDID, so this matches on the board id pocknix-steam passes as GAMESCOPE_INTERNAL_DEVICE_ID.
-- Nominal Display P3, unmeasured: without it gamescope assumes sRGB and Steam vibrance oversaturates.
gamescope.config.known_displays.pocknix_ch13726a_oled = {
    pretty_name = "CH13726A internal OLED",
    colorimetry = {
        r = { x = 0.6800, y = 0.3200 },
        g = { x = 0.2650, y = 0.6900 },
        b = { x = 0.1500, y = 0.0600 },
        w = { x = 0.3127, y = 0.3290 },
    },
    matches = function(display)
        if (display.device_id == "rp5" or display.device_id == "rpflip2") and display.internal and not display.has_edid then
            return 6000
        end
        return -1
    end,
}
