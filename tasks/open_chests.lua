-- Import necessary modules
local utils = require "core.utils"
local settings = require "core.settings"
local enums = require "data.enums"
local tracker = require "core.tracker"

-- Function to get the Aether Bomb actor
local function get_aether_bomb()
    for _, actor in pairs(actors_manager:get_all_actors()) do
        local name = actor:get_skin_name()
        if name == "BurningAether" or name == "S05_Reputation_Experience_PowerUp_Actor" then
            return actor
        end
    end
    return nil
end

-- Function to open a chest
local function open_chest(chest)
    if chest then
        console.print(chest:get_skin_name() .. " found, interacting")
        if utils.distance_to(chest) > 2 then
            pathfinder.request_move(chest:get_position())
            return false
        else
            local success = interact_object(chest)
            console.print("Chest interaction result: " .. tostring(success))
            return success
        end
    end
    return false
end

-- Function to handle opening a specific type of chest
local function handle_chest_opening(chest_type)
    local chest_id = enums.chest_types[chest_type]
    local chest = utils.get_chest(chest_id)
    if chest then
        if tracker.check_time("peasant_chest_opening_time", 1) then
            console.print(string.format("Attempting to open chest of type %s (ID: %s)", chest_type, chest_id))
            local success = open_chest(chest)
            if success then
                console.print("Chest opened successfully.")
                if chest_type == "GOLD" then
                    tracker.gold_chest_successfully_opened = true
                    tracker.gold_chest_opened = true
                end
            else
                console.print("Error opening the chest.")
            end
        end
    else
        console.print("Chest not found.")
    end
end

-- Task to open chests
local open_chests_task = {
    name = "Open Chests",
    shouldExecute = function()
        return utils.player_in_zone("S05_BSK_Prototype02") and utils.get_stash() ~= nil 
               and not (tracker.gold_chest_opened and tracker.finished_chest_looting)
    end,

    Execute = function()
        local current_time = get_time_since_inject()

        -- Debug output for tracking
        console.print(string.format("Execute called at %.2f, tracker.ga_chest_open_time: %.2f, tracker.ga_chest_opened: %s", 
                                    current_time, tracker.ga_chest_open_time or 0, tostring(tracker.ga_chest_opened)))
        console.print(string.format("Current settings: always_open_ga_chest: %s, selected_chest_type: %s, chest_opening_time: %d", 
                                    tostring(settings.always_open_ga_chest), tostring(settings.selected_chest_type), settings.chest_opening_time))

        -- Handle Aether Bomb
        local aether_bomb = get_aether_bomb()
        if aether_bomb then
            console.print("Aether bomb found, moving to it")
            if utils.distance_to(aether_bomb) > 2 then
                pathfinder.request_move(aether_bomb:get_position())
            else
                interact_object(aether_bomb)
            end
            return
        end

        -- Handle GA Chest
        if settings.always_open_ga_chest and not tracker.ga_chest_opened then
            if tracker.ga_chest_open_time == 0 or (current_time - tracker.ga_chest_open_time > 5) then
                local ga_chest = utils.get_chest("BSK_UniqueOpChest_GreaterAffix")
                if ga_chest then
                    local success = open_chest(ga_chest)
                    if success then
                        tracker.ga_chest_open_time = current_time
                        console.print(string.format("GA chest opened at %.2f. Waiting 5 seconds to loot.", tracker.ga_chest_open_time))
                    end
                else
                    console.print("GA chest not found.")
                end
            else
                console.print(string.format("Waiting for cooldown. Time since last opening: %.2f", current_time - tracker.ga_chest_open_time))
            end
            return
        end

        -- Handle Peasant Chest
        if tracker.peasant_chest_open_time == 0 then
            tracker.peasant_chest_open_time = current_time
        end

        if current_time - tracker.peasant_chest_open_time <= settings.chest_opening_time then
            local chest_type_map = {"GEAR", "MATERIALS", "GOLD"}
            local selected_chest_type = chest_type_map[settings.selected_chest_type + 1]
            handle_chest_opening(selected_chest_type)
        else
            console.print("Chest opening time exceeded. Stopping attempts.")
            tracker.peasant_chest_opening_stopped = true

            -- Handle Gold Chest if necessary
            if selected_chest_type ~= "GOLD" and not tracker.gold_chest_successfully_opened then
                console.print("Selected chest type is not Gold. Attempting to open Gold chest for 100 seconds.")
                if tracker.gold_chest_open_time == 0 then
                    tracker.gold_chest_open_time = current_time
                end

                if current_time - tracker.gold_chest_open_time <= 100 then
                    handle_chest_opening("GOLD")
                else
                    console.print("Gold chest opening time exceeded. Stopping attempts.")
                    tracker.gold_chest_opened = true
                end
            end
        end

        -- Final cooldown and finish
        console.print(string.format("Execute ended at %.2f, tracker.gold_chest_opened: %s", 
                                    current_time, tostring(tracker.gold_chest_opened)))
        
        if tracker.ga_chest_opened and (tracker.peasant_chest_opening_stopped or tracker.gold_chest_successfully_opened) then
            if not tracker.finished_looting_start_time then
                tracker.finished_looting_start_time = current_time
                console.print(string.format("All chests opened. Starting 5-second cooldown at %.2f", tracker.finished_looting_start_time))
            elseif current_time - tracker.finished_looting_start_time > 5 then
                tracker.finished_chest_looting = true
                console.print(string.format("5-second cooldown completed. All looting operations finished at %.2f", current_time))
            else
                console.print(string.format("Waiting for 5-second cooldown. Elapsed time: %.2f", current_time - tracker.finished_looting_start_time))
            end
        end
    end
}

return open_chests_task