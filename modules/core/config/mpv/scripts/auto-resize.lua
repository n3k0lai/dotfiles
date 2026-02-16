-- Auto-resize window to remove letterboxing
-- This script adjusts the MPV window height to match the video aspect ratio
-- based on the current window width

local function resize_to_aspect()
    local width = mp.get_property_number("width")
    local height = mp.get_property_number("height")
    local win_w = mp.get_property_number("osd-width")
    local win_h = mp.get_property_number("osd-height")
    
    if not width or not height or not win_w or width == 0 or height == 0 then
        return
    end
    
    -- Calculate video aspect ratio
    local video_aspect = width / height
    
    -- Calculate new window height based on current width
    local new_height = math.floor(win_w / video_aspect)
    
    -- Resize window to remove letterboxing
    mp.set_property("geometry", string.format("%dx%d", win_w, new_height))
end

-- Trigger resize when video loads
mp.register_event("file-loaded", function()
    mp.add_timeout(0.1, resize_to_aspect)
end)

-- Also trigger on window resize
mp.observe_property("osd-width", "number", function()
    mp.add_timeout(0.1, resize_to_aspect)
end)
