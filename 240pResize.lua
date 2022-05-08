-- Created by D.J. Rideout using https://obsproject.com/wiki/Scripting-Tutorial-Halftone-Filter as a reference

local obs = obslua

-- Keys for parameters for the filter
local SETTING_WIDTH = 'width'
local SETTING_HEIGHT = 'height'

-- Strings to display in the filter config
local TEXT_WIDTH = 'Width'
local TEXT_HEIGHT = 'Height'

function script_description()
    return [[240pResize
    Resize filter for original resolution 240p-ish sources, based on the Interpolation (Sharp) polyphase filter from MiSTer.]]
end

-- Definition of the global variable containing the source_info structure
local source_info = {}

source_info.id = 'filter-240p-resize'           -- Unique string identifier of the source type
source_info.type = obs.OBS_SOURCE_TYPE_FILTER   -- INPUT or FILTER or TRANSITION
source_info.output_flags = obs.OBS_SOURCE_VIDEO -- Combination of VIDEO/AUDIO/ASYNC/etc

-- Returns the name displayed in the list of filters
source_info.get_name = function()
    return "240pResize"
end

source_info.create = function(settings, source)
    -- Initializes the custom data table
    local data = {}
    data.source = source   -- Keeps a reference to this filter as a source object
    data.source_width = 1  -- Dummy value during initialization phase
    data.source_height = 1 -- Dummy value during initialization phase
    data.target_width = 1  -- Dummy value during initialization phase
    data.target_height = 1 -- Dummy value during initialization phase

    -- Compiles the effect
    obs.obs_enter_graphics()
    local effect_file_path = script_path() .. 'filter-240p-resize.effect.hlsl'
    data.effect = obs.gs_effect_create_from_file(effect_file_path, nil)
    obs.obs_leave_graphics()

    -- Calls the destroy function if the effect was not compiled properly
    if data.effect == nil then
        obs.blog(obs.LOG_ERROR, "Effect compilation failed for " .. effect_file_path)
        source_info.destroy(data)
        return nil
    end

    -- Retrieves the shader uniform variables
    data.params = {}
    data.params.source_width = obs.gs_effect_get_param_by_name(data.effect, "source_width")
    data.params.source_height = obs.gs_effect_get_param_by_name(data.effect, "source_height")
    data.params.target_width = obs.gs_effect_get_param_by_name(data.effect, "target_width")
    data.params.target_height = obs.gs_effect_get_param_by_name(data.effect, "target_height")

    -- Update the filter to use the existing parameter values set
    source_info.update(data, settings)

    return data
end

-- Destroys and release resources linked to the custom data
source_info.destroy = function(data)
    if data.effect ~= nil then
        obs.obs_enter_graphics()
        obs.gs_effect_destroy(data.effect)
        data.effect = nil
        obs.obs_leave_graphics()
    end
end

-- Define properties to display in the filter config
source_info.get_properties = function()
    local props = obs.obs_properties_create()
    obs.obs_properties_add_int(props, SETTING_WIDTH, TEXT_WIDTH, 0, 10000, 1)
    obs.obs_properties_add_int(props, SETTING_HEIGHT, TEXT_HEIGHT, 0, 10000, 1)
    return props
end

-- Define default values for the filter properties
source_info.get_defaults = function(settings)
    obs.obs_data_set_default_int(settings, SETTING_WIDTH, 0)
    obs.obs_data_set_default_int(settings, SETTING_HEIGHT, 0)
end

-- Grab the parameter values from the settings and assign them to the filter data
source_info.update = function(data, settings)
    data.target_width = obs.obs_data_get_double(settings, SETTING_WIDTH)
    data.target_height = obs.obs_data_get_double(settings, SETTING_HEIGHT)
end

-- Returns the width of the source
source_info.get_width = function(data)
    return data.target_width
end

-- Returns the height of the source
source_info.get_height = function(data)
    return data.target_height
end

-- Called when rendering the source with the graphics subsystem
source_info.video_render = function(data)
    local parent = obs.obs_filter_get_target(data.source)
    data.source_width = obs.obs_source_get_base_width(parent)
    data.source_height = obs.obs_source_get_base_height(parent)

    obs.obs_source_process_filter_begin(data.source, obs.GS_RGBA, obs.OBS_NO_DIRECT_RENDERING)

    -- Effect parameters initialization goes here
    obs.gs_effect_set_int(data.params.source_width, data.source_width)
    obs.gs_effect_set_int(data.params.source_height, data.source_height)
    obs.gs_effect_set_int(data.params.target_width, data.target_width)
    obs.gs_effect_set_int(data.params.target_height, data.target_height)

    obs.obs_source_process_filter_end(data.source, data.effect, data.target_width, data.target_height)
end

-- Called on script startup
function script_load(settings)
    obs.obs_register_source(source_info)
end
