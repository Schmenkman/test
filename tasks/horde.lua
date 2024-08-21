local utils      = require "core.utils"
local enums      = require "data.enums"
local settings   = require "core.settings"
local navigation = require "core.navigation"
local tracker    = require "core.tracker"
local explorer   = require "core.explorer"

if explorer and explorer.clear_path_and_target then
    console.print("Explorer module loaded successfully and clear_path_and_target is available")
else
    console.print("Error: Explorer module or clear_path_and_target method is missing")
end

local bomber = {
    enabled = false,
    is_task_running = false,
    bomber_task_running = false
}

local horde_center_position    = vec3:new(9.204102, 8.915039, 0.000000)
local horde_boss_room_position = vec3:new(-36.17675, -36.3222, 2.200)

local circle_data = {
    radius = 12,
    steps = 6,
    delay = 0.01,
    current_step = 1,
    last_action_time = 0,
    height_offset = 1
}

local function get_current_time()
    return get_time_since_inject()
end

local function get_player_pos()
    return get_player_position()
end

local function move_to_position(pos)
    if utils.distance_to(pos) > 2 then
        pathfinder.force_move_raw(pos)
    end
end

function bomber:check_and_handle_stuck()
    if explorer.check_if_stuck() then
        console.print("Player is stuck. Moving to unstuck target.")
        pathfinder.force_move_raw(horde_center_position)
        return true
    end
    return false
end

function bomber:all_waves_cleared()
    local actors = actors_manager:get_all_actors()
    local waves_cleared = true

    for _, actor in pairs(actors) do
        if actor:get_skin_name() == "BSK_MapIcon_LockedDoor" then
            -- Es gibt möglicherweise noch Gegner in der Welle, daher setzen wir waves_cleared auf false
            waves_cleared = false
        end
    end

    -- Prüfen, ob noch Gegner vorhanden sind, die bekämpft werden müssen
    local remaining_enemies = false
    for _, actor in pairs(actors) do
        if not evade.is_dangerous_position(actor:get_position()) and target_selector.is_valid_enemy(actor) then
            remaining_enemies = true
            break
        end
    end

    -- Wenn noch Gegner vorhanden sind, geben wir false zurück
    return waves_cleared and not remaining_enemies
end
function bomber:shoot_in_circle()
    local current_time = get_current_time()
    if current_time - circle_data.last_action_time >= circle_data.delay then
        local player_pos = get_player_pos()
        local angle = (circle_data.current_step / circle_data.steps) * (2 * math.pi)

        local x = player_pos:x() + circle_data.radius * math.cos(angle)
        local z = player_pos:z() + circle_data.radius * math.sin(angle)
        local y = player_pos:y() + circle_data.height_offset * math.sin(angle)

        pathfinder.force_move_raw(vec3:new(x, y, z))
        circle_data.last_action_time = current_time
        circle_data.current_step = (circle_data.current_step % circle_data.steps) + 1
    end
end

function bomber:use_all_spells()
    local spells = ids.spells.sorcerer
    if not (utils.player_has_aura(spells.ice_armor) or utils.player_has_aura(spells.flame_shield)) then
        if utility.is_spell_ready(spells.flame_shield) then
            cast_spell.self(spells.flame_shield, 0)
            return
        elseif utility.is_spell_ready(spells.ice_armor) then
            cast_spell.self(spells.ice_armor, 0)
            return
        end
    end

    for _, spell in ipairs({spells.ice_blade, spells.lightning_spear, spells.unstable_currents}) do
        if utility.is_spell_ready(spell) then
            cast_spell.self(spell, 0)
            return
        end
    end
end

local last_move_time = 0
local move_timeout = 5

function bomber:bomb_to(pos)
    local current_time = os.time()
    if current_time - last_move_time > move_timeout then
        console.print("Move timeout reached. Clearing path and target.")
        explorer:set_custom_target(pos)
        explorer:clear_path_and_target()
        last_move_time = current_time
    end

    explorer:set_custom_target(pos)
    explorer:move_to_target()
    last_move_time = current_time
end

function bomber:get_target()
    local actors = actors_manager:get_all_actors()
    for _, actor in pairs(actors) do
        local name = actor:get_skin_name()
        local health = actor:get_current_health()
        local pos = actor:get_position()
        local is_special = actor:is_boss() or actor:is_champion() or actor:is_elite()

        if not evade.is_dangerous_position(pos) then
            if name:match("Soulspire") and health > 20 then return actor end
            if name == "BurningAether" then return actor end
            if (name:match("Mass") or name:match("Zombie")) and health > 1 then return actor end
            if name == "MarkerLocation_BSK_Occupied" then return actor end
            if is_special then return actor end
            if target_selector.is_valid_enemy(actor) then return actor end
        end
    end
end

local pylons = {
    "SkulkingHellborne",
    "SurgingHellborne",
    "RagingHellfire",
    "MeteoricHellborne",
    "EmpoweredHellborne",
    "InvigoratingHellborne",
    "BlisteringHordes",
    "SurgingElites",
    "ThrivingMasses",
    "GestatingMasses",
    "EmpoweredMasses",
    "EmpoweredElites",
    "IncreasedEvadeCooldown",
    "IncreasedPotionCooldown",
    "EmpoweredCouncil",
    "ReduceAllResistance",
    "DeadlySpires",
    "UnstoppableElites",
    "CorruptingSpires",
    "UnstableFiends",
    "AetherRush",
    "EnergizingMasses",
    "GreedySpires",
    "InfernalLords",
    "InfernalStalker",
}

function bomber:get_pylons()
    -- Überprüfen, ob `pylons` korrekt definiert ist
    if not pylons or #pylons == 0 then
        console.print("Error: `pylons` is not defined or empty.")
        return nil
    end

    local actors = actors_manager:get_all_actors()
    local highest_priority_actor = nil
    local highest_priority = #pylons + 1 -- Priorität höher als jede mögliche Pylon-Priorität

    -- Erstellen einer Tabelle zur Speicherung der Priorität jedes Pylons
    local pylon_priority = {}
    for i, pylon in ipairs(pylons) do
        pylon_priority[pylon] = i -- Priorität basierend auf der Reihenfolge in der Pylons-Tabelle zuweisen
    end

    -- Durchlaufe alle Schauspieler und bestimme den Pylon mit der höchsten Priorität
    for _, actor in pairs(actors) do
        local name = actor:get_skin_name()
        if name:match("BSK_Pyl") then
            for pylon, priority in pairs(pylon_priority) do
                if name:match(pylon) and priority < highest_priority then
                    highest_priority = priority
                    highest_priority_actor = actor
                end
            end
        end
    end

    return highest_priority_actor
end


function bomber:get_locked_door()
    local actors = actors_manager:get_all_actors()
    local is_locked, in_wave = false, false
    local door_actor = nil

    for _, actor in pairs(actors) do
        local name = actor:get_skin_name()
        if name == "BSK_MapIcon_LockedDoor" then is_locked = true end
        if name == "Hell_Fort_BSK_Door_A_01_Dyn" then door_actor = actor end
        if name == "DGN_Standard_Door_Lock_Sigil_Ancients_Zak_Evil" then in_wave = true end
    end

    return not in_wave and is_locked and door_actor
end

local buffs_gathered = {}

function bomber:gather_buffs()
    local local_player = get_local_player()
    local buffs = local_player:get_buffs()
    for _, buff in pairs(buffs) do
        local buff_id = buff.name_hash
        if not buffs_gathered[buff_id] then
            buffs_gathered[buff_id] = true
            console.print("Got Buff: " .. buff:name() .. ", ID: " .. buff.name_hash)
        end
    end
end

function bomber:get_aether_actor()
    local actors = actors_manager:get_all_actors()
    for _, actor in pairs(actors) do
        local name = actor:get_skin_name()
        if name == "BurningAether" or name == "S05_Reputation_Experience_PowerUp_Actor" then
            return actor
        end
    end
end

function bomber:main_pulse()
    if get_local_player():is_dead() then
        revive_at_checkpoint()
        return
    end

    if bomber:check_and_handle_stuck() then
        return
    end

    local world_name = get_current_world():get_name()
    if world_name == "Limbo" or world_name:match("Sanctuary") then
        return
    end

    local pylon = bomber:get_pylons()
    if pylon then
        local aether_actor = bomber:get_aether_actor()
        if aether_actor then
            bomber:bomb_to(aether_actor:get_position())
        else
            move_to_position(pylon:get_position())
            interact_object(pylon)
        end
        return
    end

    local locked_door = bomber:get_locked_door()
    if locked_door then
        if tracker.finished_chest_looting then
            tracker.reset_chest_trackers()
        end
        if utils.distance_to(locked_door) > 2 then
            bomber:bomb_to(locked_door:get_position())
        else
            interact_object(locked_door)
        end
        return
    end

    local target = bomber:get_target()
    if target then
        if utils.distance_to(target) > 1.5 then
            bomber:bomb_to(target:get_position())
        else
            bomber:shoot_in_circle()
        end
        return
    else
        if bomber:all_waves_cleared() then
            local aether = bomber:get_aether_actor()
            if aether then
                bomber:bomb_to(aether:get_position())
                return
            end

            if get_player_pos():dist_to(horde_boss_room_position) > 2 then
                bomber:bomb_to(horde_boss_room_position)
            else
                bomber:shoot_in_circle()
            end
        else
            if get_player_pos():dist_to_ignore_z(horde_center_position) > 2 then
                bomber:bomb_to(horde_center_position)
            else
                bomber:shoot_in_circle()
            end
        end
    end
end

local task = {
    name = "Infernal Horde",
    shouldExecute = function()
        return utils.player_in_zone("S05_BSK_Prototype02")
    end,
    
    Execute = function()
        tracker.horde_opened = false
        bomber:main_pulse()
    end
}

return task

