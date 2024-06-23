if UnitClassBase( 'player' ) ~= 'DEATHKNIGHT' then return end

local addon, ns = ...
local Hekili = _G[ addon ]
local class, state = Hekili.Class, Hekili.State

local roundUp = ns.roundUp
local strformat = string.format

local spec = Hekili:NewSpecialization( 6 )

-- TODO
--- Unholy Presence reduces global cooldown by .5 seconds. (Unsure how to do this)
--- Deathstrike healing calculation

spec:RegisterResource( Enum.PowerType.RunicPower )

local death_rune_tracker = { 0, 0, 0, 0, 0, 0}
spec:RegisterStateExpr("get_death_rune_tracker", function()
    return death_rune_tracker
end)

spec:RegisterStateTable( "death_runes", setmetatable( {
    state = {},

    reset = function()
        for i = 1, 6 do
            local start, duration, ready = GetRuneCooldown( i )
            local type = GetRuneType( i )
            local expiry = ready and 0 or start + duration
            state.death_runes.state[i] = {
                type = type,
                start = start,
                duration = duration,
                ready = ready,
                expiry = expiry
            }
        end
    end,

    spend = function(neededRunes)
        local usedRunes, err = state.death_runes.getRunesForRequirement(neededRunes)
        if not usedRunes then
            --print("Error:", err)
            return
        end

        local runeMapping = {
            blood = {1, 2},
            unholy = {3, 4},
            frost = {5, 6}
        }

        for _, runeIndex in ipairs(usedRunes) do
            local rune = state.death_runes.state[runeIndex]
            rune.ready = false

            -- Determine other rune in the group
            local otherRuneIndex
            for type, runes in pairs(runeMapping) do
                if runes[1] == runeIndex then
                    otherRuneIndex = runes[2]
                    break
                elseif runes[2] == runeIndex then
                    otherRuneIndex = runes[1]
                    break
                end
            end

            local otherRune = state.death_runes.state[otherRuneIndex]
            local expiryTime = (otherRune.expiry > 0 and otherRune.expiry or state.query_time) + rune.duration
            rune.expiry = expiryTime
        end
    end,

    getActiveDeathRunes = function()
        local activeRunes = {}
        local state_array = state.death_runes.state
        for i = 1, #state_array do
            if state_array[i].type == 4 and state_array[i].expiry < state.query_time then
                table.insert(activeRunes, i)
            end
        end
        return activeRunes
    end,

    getLeftmostActiveDeathRune = function()
        local activeRunes = state.death_runes.getActiveDeathRunes()
        return #activeRunes > 0 and activeRunes[1] or nil
    end,

    getActiveRunes = function()
        local activeRunes = {}
        local state_array = state.death_runes.state
        for i = 1, #state_array do
            if state_array[i].expiry < state.query_time then
                table.insert(activeRunes, i)
            end
        end
        return activeRunes
    end,

    getRunesForRequirement = function(neededRunes)
        local bloodNeeded, frostNeeded, unholyNeeded = unpack(neededRunes)
        local runeMapping = {
            blood = {1, 2},
            unholy = {3, 4},
            frost = {5, 6},
            any = {1, 2, 3, 4, 5, 6}
        }
        
        local activeRunes = state.death_runes.getActiveRunes()
        local usedRunes = {}
        local usedDeathRunes = {}

        local function useRunes(runetype, needed)
            local runes = runeMapping[runetype]
            for _, runeIndex in ipairs(runes) do
                if needed == 0 then break end
                if state.death_runes.state[runeIndex].expiry < state.query_time and state.death_runes.state[runeIndex].type ~= 4 then
                    table.insert(usedRunes, runeIndex)
                    needed = needed - 1
                end
            end
            return needed
        end

        -- Use specific runes first
        bloodNeeded = useRunes("blood", bloodNeeded)
        frostNeeded = useRunes("frost", frostNeeded)
        unholyNeeded = useRunes("unholy", unholyNeeded)

        -- Use death runes if needed
        for _, runeIndex in ipairs(activeRunes) do
            if bloodNeeded == 0 and frostNeeded == 0 and unholyNeeded == 0 then break end
            if state.death_runes.state[runeIndex].type == 4 and not usedDeathRunes[runeIndex] then
                if bloodNeeded > 0 then
                    table.insert(usedRunes, runeIndex)
                    bloodNeeded = bloodNeeded - 1
                elseif frostNeeded > 0 then
                    table.insert(usedRunes, runeIndex)
                    frostNeeded = frostNeeded - 1
                elseif unholyNeeded > 0 then
                    table.insert(usedRunes, runeIndex)
                    unholyNeeded = unholyNeeded - 1
                end
                usedDeathRunes[runeIndex] = true
            end
        end

        --if bloodNeeded > 0 or frostNeeded > 0 or unholyNeeded > 0 then
        --    return false, "Not enough active runes to fulfill the requirements"
        --end

        return usedRunes
    end,

},{
    __index = function( t, k )
        local countDeathRunes = function()
            local state_array = t.state
            local count = 0
            for i = 1, #state_array do
                if state_array[i].type == 4 and state_array[i].expiry < state.query_time then
                    count = count + 1
                end
            end
            return count
        end
        local runeMapping = {
            blood = {1, 2},
            unholy = {3, 4},
            frost = {5, 6},
            any = {1, 2, 3, 4, 5, 6}
        }
        -- Function to access the mappings
        local function getRuneSet(runeType)
            return runeMapping[runeType]
        end

        local countDRForType = function(type)
            local state_array = t.state
            local count = 0
            local runes = getRuneSet(type)
            if runes then
                for _, rune in ipairs(runes) do
                    if state_array[rune].type == 4 and state_array[rune].expiry < state.query_time then
                        count = count + 1
                    end
                end
            else
                print("Invalid rune type:", type)
            end
            return count
        end

        if k == "state" then 
            return t.state
        elseif k == "actual" then
            return countDRForType("any")
        elseif k == "current" then
            return countDRForType("any")
        elseif k == "current_frost" then
            return countDRForType("frost")
        elseif k == "current_blood" then
            return countDRForType("blood")
        elseif k == "current_unholy" then
            return countDRForType("unholy")
        elseif k == "current_non_frost" then
            return countDRForType("blood") + countDRForType("unholy")
        elseif k == "current_non_blood" then
            return countDRForType("frost") + countDRForType("unholy")
        elseif k == "current_non_unholy" then
            return countDRForType("blood") + countDRForType("frost")
        elseif k == "cooldown" then
            return t.state[1].duration
        elseif k == "active_death_runes" then
            return t.getActiveDeathRunes()
        elseif k == "leftmost_active_death_rune" then
            return t.getLeftmostActiveDeathRune()
        elseif k == "active_runes" then
            return t.getActiveRunes()
        elseif k == "runes_for_requirement" then
            return t.getRunesForRequirement
        end
    end
} ) )

spec:RegisterResource( Enum.PowerType.RuneBlood, {
    rune_regen = {
        last = function ()
            return state.query_time
        end,

        interval = function( time, val )
            local r = state.blood_runes

            if val == 2 then return -1 end
            return r.expiry[ val + 1 ] - time
        end,

        stop = function( x )
            return x == 2
        end,

        value = 1
    },
}, setmetatable( {
    expiry = { 0, 0 },
    cooldown = 10,
    regen = 0,
    max = 2,
    forecast = {},
    fcount = 0,
    times = {},
    values = {},
    resource = "blood_runes",

    reset = function()

        local t = state.blood_runes

        for i = 1, 2 do
            local start, duration, ready = GetRuneCooldown( i );

            start = start or 0
            duration = duration or ( 10 * state.haste )

            t.expiry[ i ] = ready and 0 or start + duration
            t.cooldown = duration
        end

        table.sort( t.expiry )

        t.actual = nil
    end,

    gain = function( amount )
        local t = state.blood_runes

        for i = 1, amount do
            t.expiry[ 3 - i ] = 0
        end
        table.sort( t.expiry )

        t.actual = nil
    end,

    spend = function( amount )
        local t = state.blood_runes

        for i = 1, amount do
            t.expiry[ 1 ] = ( t.expiry[ 2 ] > 0 and t.expiry[ 2 ] or state.query_time ) + t.cooldown
            table.sort( t.expiry )
        end

        t.actual = nil
    end,

    timeTo = function( x )
        return state:TimeToResource( state.blood_runes, x )
    end,
}, {
    __index = function( t, k, v )
        if k == "actual" then
            local amount = 0

            for i = 1, 2 do
                if t.expiry[ i ] <= state.query_time then
                    amount = amount + 1
                end
            end
            return amount

        elseif k == "current" then
            -- If this is a modeled resource, use our lookup system.
            if t.forecast and t.fcount > 0 then
                local q = state.query_time
                local index, slice

                if t.values[ q ] then return t.values[ q ] end

                for i = 1, t.fcount do
                    local v = t.forecast[ i ]
                    if v.t <= q then
                        index = i
                        slice = v
                    else
                        break
                    end
                end

                -- We have a slice.
                if index and slice then
                    t.values[ q ] = max( 0, min( t.max, slice.v ) )
                    return t.values[ q ]
                end
            end

            return t.actual

        elseif k == "deficit" then
            return t.max - t.current

        elseif k == "time_to_next" then
            return t[ "time_to_" .. t.current + 1 ]

        elseif k == "time_to_max" then
            return t.current == 2 and 0 or max( 0, t.expiry[2] - state.query_time )

        elseif k == "add" then
            return t.gain

        elseif k == "regen" then
            return 0

        else
            local amount = k:match( "time_to_(%d+)" )
            amount = amount and tonumber( amount )

            if amount then return state:TimeToResource( t, amount ) end
        end
    end
} ) )

spec:RegisterResource( Enum.PowerType.RuneFrost, {
    rune_regen = {
        last = function ()
            return state.query_time
        end,

        interval = function( time, val )
            local r = state.frost_runes

            if val == 2 then return -1 end
            return r.expiry[ val + 1 ] - time
        end,

        stop = function( x )
            return x == 2
        end,

        value = 1
    },
}, setmetatable( {
    expiry = { 0, 0 },
    cooldown = 10,
    regen = 0,
    max = 2,
    forecast = {},
    fcount = 0,
    times = {},
    values = {},
    resource = "frost_runes",

    reset = function()
        local t = state.frost_runes

        for i = 5, 6 do
            local start, duration, ready = GetRuneCooldown( i )

            start = start or 0
            duration = duration or ( 10 * state.haste )

            t.expiry[ i - 4 ] = ready and 0 or start + duration
            t.cooldown = duration
        end

        table.sort( t.expiry )

        t.actual = nil
    end,

    gain = function( amount )
        local t = state.frost_runes

        amount = min( 2, amount )

        for i = 1, amount do
            t.expiry[ i ] = 0
        end
        table.sort( t.expiry )

        t.actual = nil
    end,

    spend = function( amount )
        local t = state.frost_runes

        amount = min( 2, amount )

        for i = 1, amount do
            t.expiry[ 1 ] = ( t.expiry[ 2 ] > 0 and t.expiry[ 2 ] or state.query_time ) + t.cooldown
            table.sort( t.expiry )
        end

        t.actual = nil
    end,

    timeTo = function( x )
        return state:TimeToResource( state.frost_runes, x )
    end,
}, {
    __index = function( t, k, v )
        if k == "actual" then
            local amount = 0

            for i = 1, 2 do
                if t.expiry[ i ] <= state.query_time then
                    amount = amount + 1
                end
            end

            return amount

        elseif k == "current" then
            -- If this is a modeled resource, use our lookup system.
            if t.forecast and t.fcount > 0 then
                local q = state.query_time
                local index, slice

                if t.values[ q ] then return t.values[ q ] end

                for i = 1, t.fcount do
                    local v = t.forecast[ i ]
                    if v.t <= q then
                        index = i
                        slice = v
                    else
                        break
                    end
                end

                -- We have a slice.
                if index and slice then
                    t.values[ q ] = max( 0, min( t.max, slice.v ) )
                    return t.values[ q ]
                end
            end

            return t.actual

        elseif k == "deficit" then
            return t.max - t.current

        elseif k == "time_to_next" then
            return t[ "time_to_" .. t.current + 1 ]

        elseif k == "time_to_max" then
            return t.current == 2 and 0 or max( 0, t.expiry[ 2 ] - state.query_time )

        elseif k == "add" then
            return t.gain

        elseif k == "regen" then
            return 0

        else
            local amount = k:match( "time_to_(%d+)" )
            amount = amount and tonumber( amount )

            if amount then return state:TimeToResource( t, amount ) end
        end
    end
} ) )

spec:RegisterResource( Enum.PowerType.RuneUnholy, {
    rune_regen = {
        last = function ()
            return state.query_time
        end,

        interval = function( time, val )
            local r = state.unholy_runes

            if val == 2 then return -1 end
            return r.expiry[ val + 1 ] - time
        end,

        stop = function( x )
            return x == 2
        end,

        value = 1
    },
}, setmetatable( {
    expiry = { 0, 0 },
    cooldown = 10,
    regen = 0,
    max = 2,
    forecast = {},
    fcount = 0,
    times = {},
    values = {},
    resource = "unholy_runes",

    reset = function()
        local t = state.unholy_runes

        for i = 3, 4 do
            local start, duration, ready = GetRuneCooldown( i )

            start = start or 0
            duration = duration or ( 10 * state.haste )

            t.expiry[ i - 2 ] = ready and 0 or start + duration
            t.cooldown = duration
        end

        table.sort( t.expiry )

        t.actual = nil
    end,

    gain = function( amount )
        local t = state.unholy_runes

        amount = min( amount, 2 )

        for i = 1, amount do
            t.expiry[ i ] = 0
        end
        table.sort( t.expiry )

        t.actual = nil
    end,

    spend = function( amount )
        local t = state.unholy_runes

        amount = min( 2, amount )

        for i = 1, amount do
            t.expiry[ 1 ] = ( t.expiry[ 2 ] > 0 and t.expiry[ 2 ] or state.query_time ) + t.cooldown
            table.sort( t.expiry )
        end

        t.actual = nil
    end,

    timeTo = function( x )
        return state:TimeToResource( state.unholy_runes, x )
    end,
}, {
    __index = function( t, k, v )
        if k == "actual" then
            local amount = 0

            for i = 1, 2 do
                if t.expiry[ i ] <= state.query_time then
                    amount = amount + 1
                end
            end

            return amount

        elseif k == "current" then
            -- If this is a modeled resource, use our lookup system.
            if t.forecast and t.fcount > 0 then
                local q = state.query_time
                local index, slice

                if t.values[ q ] then return t.values[ q ] end

                for i = 1, t.fcount do
                    local v = t.forecast[ i ]
                    if v.t <= q then
                        index = i
                        slice = v
                    else
                        break
                    end
                end

                -- We have a slice.
                if index and slice then
                    t.values[ q ] = max( 0, min( t.max, slice.v ) )
                    return t.values[ q ]
                end
            end

            return t.actual

        elseif k == "deficit" then
            return t.max - t.current

        elseif k == "time_to_next" then
            return t[ "time_to_" .. t.current + 1 ]

        elseif k == "time_to_max" then
            return t.current == 2 and 0 or max( 0, t.expiry[2] - state.query_time )

        elseif k == "add" then
            return t.gain

        elseif k == "regen" then
            return 0

        else
            local amount = k:match( "time_to_(%d+)" )
            amount = amount and tonumber( amount )

            if amount then return state:TimeToResource( t, amount ) end
        end
    end
} ) )

-- butchery talent should generate 1 RP every 5/2.5 seconds depending on rank.
-- scent_of_blood should generate 10 RP on next attack.


-- Talents
spec:RegisterTalents( {
    abominations_might         = { 10281, 2, 53137, 53138                      },
    annihilation               = { 2048 , 3, 51468, 51472, 51473               },
    anti_magic_zone            = { 2221 , 1, 51052                             },
    blade_barrier              = { 2017 , 3, 49182, 49500, 49501               },
    bladed_armor               = { 1938 , 3, 48978, 49390, 49391               },
    blood_caked_blade          = { 5457 , 3, 49219, 49627, 49628               },
    blood_of_the_north         = { 10183, 3, 54639, 54638, 54637               },
    blood_parasite             = { 1960 , 2, 49027, 49542                      },
    blood_rites                = { 10305, 3, 49467, 50033, 50034               },
    bone_shield                = { 6703 , 1, 49222                             },
    brittle_bones              = { 1980 , 2, 81327, 81328                      },
    butchery                   = { 5372 , 2, 48979, 49483                      },
    chilblains                 = { 2260 , 2, 50040, 50041                      },
    chill_of_the_grave         = { 1981 , 2, 49149, 50115                      },
    contagion                  = { 12119, 2, 91316, 91319                      },
    crimson_scourge            = { 10289, 2, 81135, 81136                      },
    dancing_rune_weapon        = { 5426 , 1, 49028                             },
    dark_transformation        = { 2085 , 1, 63560                             },
    death_advance              = { 15322, 2, 96269, 96270                      },
    desecration                = { 5467 , 2, 55666, 55667                      },
    ebon_plaguebringer         = { 5489 , 2, 51099, 51160                      },
    endless_winter             = { 1971 , 2, 49137, 49657                      },
    epidemic                   = { 1963 , 3, 49036, 49562, 81334               },
    frost_strike               = { 10189, 1, 49143                             },
    hand_of_doom               = { 11270, 2, 85793, 85794                      },
    heart_strike               = { 10303, 1, 55050                             },
    howling_blast              = { 1989 , 1, 49184                             },
    hungering_cold             = { 1999 , 1, 49203                             },
    icy_reach                  = { 10147, 2, 55061, 55062                      },
    icy_talons                 = { 10153, 5, 50880, 50884, 50885, 50886, 50887 },
    improved_blood_presence    = { 5410 , 2, 50365, 50371                      },
    improved_blood_tap         = { 12223, 2, 94553, 94555                      },
    improved_death_strike      = { 5412 , 3, 62905, 62908, 81138               },
    improved_frost_presence    = { 2029 , 2, 50384, 50385                      },
    improved_icy_talons        = { 2223 , 1, 55610                             },
    improved_unholy_presence   = { 2013 , 2, 50391, 50392                      },
    killing_machine            = { 2044 , 3, 51123, 51127, 51128               },
    lichborne                  = { 2215 , 1, 49039                             },
    magic_suppression          = { 5469 , 3, 49224, 49610, 49611               },
    mangle                     = { 5499 , 1, 33917                             },
    master_of_ghouls           = { 10233, 1, 52143                             },
    merciless_combat           = { 1993 , 2, 49024, 49538                      },
    might_of_the_frozen_wastes = { 7571 , 3, 81330, 81332, 81333               },
    morbidity                  = { 5443 , 3, 48963, 49564, 49565               },
    nerves_of_cold_steel       = { 2022 , 3, 49226, 50137, 50138               },
    on_a_pale_horse            = { 11275, 1, 51986                             },
    pillar_of_frost            = { 1979 , 1, 51271                             },
    rage_of_rivendare          = { 5435 , 3, 51745, 51746, 91323               },
    reaping                    = { 10245, 3, 49208, 56834, 56835               },
    resilient_infection        = { 7572 , 2, 81338, 81339                      },
    rime                       = { 1992 , 3, 49188, 56822, 59057               },
    rune_tap                   = { 5384 , 1, 48982                             },
    runic_corruption           = { 5451 , 2, 51459, 51462                      },
    runic_power_mastery        = { 2031 , 3, 49455, 50147, 91145               },
    sanguine_fortitude         = { 10299, 2, 81125, 81127                      },
    scarlet_fever              = { 10285, 2, 81131, 81132                      },
    scent_of_blood             = { 5380 , 3, 49004, 49508, 49509               },
    scourge_strike             = { 10251, 1, 55090                             },
    shadow_infusion            = { 5447 , 3, 48965, 49571, 49572               },
    sudden_doom                = { 5414 , 3, 49018, 49529, 49530               },
    summon_gargoyle            = { 5495 , 1, 49206                             },
    threat_of_thassarian       = { 2284 , 3, 65661, 66191, 66192               },
    toughness                  = { 5431 , 3, 49042, 49786, 49787               },
    unholy_blight              = { 5461 , 1, 49194                             },
    unholy_command             = { 5445 , 2, 49588, 49589                      },
    unholy_frenzy              = { 5408 , 1, 49016                             },
    vampiric_blood             = { 5416 , 1, 55233                             },
    vengeance                  = { 93099, 1, 93099                             }, -- This is not a valid talentId, same for Paladin
    veteran_of_the_third_war   = { 10309, 3, 49006, 49526, 50029               },
    virulence                  = { 1932 , 3, 48962, 49567, 49568               },
    will_of_the_necropolis     = { 1959 , 3, 52284, 81163, 81164               },
} )


-- Glyphs
-- Unused note means it is unused by hekili, not that it unused by players.
spec:RegisterGlyphs( {
    [58623] = "antimagic_shell",
    [59332] = "blood_boil", 
    [58640] = "blood_tap",
    [58673] = "bone_shield", -- 15% movement speed
    [58620] = "chains_of_ice",
    [63330] = "dancing_rune_weapon", -- threat improvement
    [96279] = "dark_succor", 
    [58629] = "death_and_decay", 
    [63333] = "death_coil",
    [60200] = "death_gate", -- death gate cooldown
    [62259] = "death_grip",
    [59336] = "death_strike", -- Increases damage based on RP.
    [58677] = "deaths_embrace",
    [58647] = "frost_strike",
    [58616] = "heart_strike", -- damage of heart_strike by 30%.
    [58680] = "horn_of_winter",
    [63335] = "howling_blast",
    [63331] = "hungering_cold",
    [58631] = "icy_touch", -- damage buff
    [58671] = "obliterate", -- damage buff
    [59307] = "path_of_frost", -- fall damaged
    [58657] = "pestilence",
    [58635] = "pillar_of_frost", -- cc immune, str pct
    [58669] = "rune_strike", -- damage buff, un
    [59327] = "rune_tap", -- %5 health to party
    [58618] = "strangulate",
    [58676] = "vampiric_blood"
} )

-- Auras
spec:RegisterAuras( {
    -- Spell damage reduced by $s1%.  Immune to magic debuffs.
    antimagic_shell = {
        id = 48707,
        duration = function() return glyph.antimagic_shell.enabled and 7 or 5 end,
        max_stack = 1,
    },
    antimagic_zone = { -- TODO: Check Aura (https://wowhead.com/wotlk/spell=51052)
        id = 51052,
        duration = 10,
        max_stack = 1,
    },
    army_of_the_dead = { -- TODO: Check Aura (https://wowhead.com/wotlk/spell=42651)
        id = 42651,
        duration = 40,
        max_stack = 1,
        copy = { 42651, 42650 },
    },
    -- $s1% less damage taken.
    blade_barrier = {
        id = 64859,
        duration = 10,
        max_stack = 1,
        copy = { 51789, 64855, 64856, 64858, 64859 },
    },
    -- Deals Shadow damage over $d.
    blood_plague = {
        id = 55078,
        duration = function () return 15 + ( 3 * talent.epidemic.rank ) end,
        tick_time = 3,
        max_stack = 1,
    },
    -- Stamina increased by 8%. Armor contribution from cloth, leather, mail and plate items increased by 55%. Damage taken reduced by 8%.
    blood_presence = {
        id = 48263,
        duration = 3600,
        max_stack = 1,
    },
    -- When you deal damage with Death Strike while in Blood Presence, you gain a percentage of your health gained as a physical absorption shield. Absorbs %d Physical damage.
    blood_shield = {
        id = 77535,
        duration = 10,
        max_stack = 1,
    },
    -- Blood Rune converted to a Death Rune.
    blood_tap = {
        id = 45529,
        duration = 20,
        max_stack = 1,
    },
    bloodworm = { -- TODO: Check Aura (https://wowhead.com/wotlk/spell=50452)
        id = 50452,
        duration = 20,
        max_stack = 1,
    },
    -- Physical damage increased by $s1%.
    bloody_vengeance = {
        id = 50449,
        duration = 30,
        max_stack = 3,
        copy = { 50449, 50448, 50447 },
    },
    -- Damage reduced by $s1%.
    bone_shield = {
        id = 49222,
        duration = 300,
        max_stack = 6,
    },
    -- Slowed by frozen chains.
    chains_of_ice = {
        id = 45524,
        duration = 10,
        max_stack = 1,
    },
    -- proc for blood boil
    crimson_scourge = {
        id = 81141,
        duration = 10,
        max_stack = 1,
    },
    -- Increases disease damage taken.
    crypt_fever = {
        id = 50508,
        duration = 15,
        max_stack = 1,
        copy = { 50509, 50510 }
    },
    -- You have recently summoned a rune weapon.
    dancing_rune_weapon = {
        id = 81256,
        duration = 12,
        max_stack = 1,
    },
    -- Taunted.
    dark_command = {
        id = 56222,
        duration = 3,
        max_stack = 1,
    },
    --Transformed into an undead monstrosity. Damage dealt increased by 60%.
    dark_transformation = {
        id = 63560,
        duration = 30,
        max_stack = 1,
        generate = function ( t )
            local name, _, count, _, duration, expires, caster = FindUnitBuffByID( "pet", 63560 )

            if name then
                t.name = name
                t.count = 1
                t.expires = expires
                t.applied = expires - duration
                t.caster = caster
                return
            end

            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end,
    },
    -- $s1 Shadow damage inflicted every sec
    death_and_decay = {
        id = 49938,
        duration = function() return glyph.death_and_decay.enabled and 15 or 10 end,
        tick_time = 1,
        max_stack = 1,
        copy = { 43265, 49936, 49937, 49938 },
    },
    death_gate = { -- TODO: Check Aura (https://wowhead.com/wotlk/spell=50977)
        id = 50977,
        duration = 60,
        max_stack = 1,
    },
    -- Taunted.
    death_grip = {
        id = 49575,
        duration = 3,
        max_stack = 1
    },
    -- Standing upon unholy ground.   Movement speed is reduced by $s1%.
    desecration = {
        id = 68766,
        duration = 20,
        max_stack = 1,
        copy = { 68766, 55741 },
    },
    -- Crypt Fever, improved by Ebon Plaguebringer.
    ebon_plague = {
        id = 51735,
        duration = 15,
        max_stack = 1,
        copy = { 51726, 51734 }
    },
    -- Your next Howling Blast will consume no runes.
    freezing_fog = {
        id = 59052,
        duration = 15,
        max_stack = 1,
        copy = "rime"
    },
    -- Deals Frost damage over $d.  Reduces melee and ranged attack speed.
    frost_fever = {
        id = 55095,
        duration = function () return 21 + ( 4 * talent.epidemic.rank ) end,
        tick_time = 3,
        max_stack = 1,
    },
    -- Damage increased by 10%. Runic Power generation increased by 10%.
    frost_presence = {
        id = 48266,
        duration = 3600,
        max_stack = 1,
    },
    -- Stunned.
    glyph_of_death_grip = {
        id = 58628,
        duration = 1,
        max_stack = 1,
    },
    -- Snare.
    glyph_of_heart_strike = {
        id = 58617,
        duration = 10,
        max_stack = 1,
    },
    horn_of_winter = {
        id = 57330,
        duration = function() return  glyph.horn_of_winter.enabled and 180 or 120 end,
        max_stack = 1,
    },
    -- Damage taken reduced.  Immune to Stun effects.
    icebound_fortitude = {
        id = 48792,
        duration = function () return 12 + ( 3 * talent.guile_of_gorefiend.rank ) end,
        max_stack = 1,
    },
    -- Movement speed reduced by $s1%.
    icy_clutch = {
        id = 50436,
        duration = 10,
        max_stack = 1,
        copy = { 50436, 50435, 50434 },
    },
    -- Your next Icy Touch, Howling Blast or Frost Strike will be a critical strike.
    killing_machine = {
        id = 51124,
        duration = 30,
        max_stack = 1,
    },
    -- Immune to Charm, Fear and Sleep.  Undead.
    lichborne = {
        id = 49039,
        duration = 10,  
        max_stack = 1,
    },

    mind_freeze = { -- TODO: Check Aura (https://wowhead.com/wotlk/spell=47528)
        id = 47528,
        duration = 4,
        max_stack = 1,
    },
    -- Grants the ability to walk across water.
    path_of_frost = {
        id = 3714,
        duration = 600,
        max_stack = 1,
    },
    -- Strength increased by 20%. Immune to movement from external sources.
    pillar_of_frost = {
        id = 51271,
        duration = 20,
        max_stack = 1,
    },
    -- Any presence is applied.
    presence = {
        alias = { "blood_presence", "frost_presence", "unholy_presence" },
        aliasMode = "first",
        aliasType = "buff",
    },
    raise_dead = {
        duration = function () return  talent.master_of_ghouls.enabled and 3600 or 60  end,
        max_stack = 1,
        generate = function( t )
            local up, name, start, duration, texture = GetTotemInfo( 1 )
            if up then
                t.count = 1
                t.expires = start + duration
                t.applied = start
                t.caster = "player"
                return
            end

            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end,
    },
    rune_strike_usable = {
        duration = 5,
        max_stack = 1,
    },
    -- Successful attacks generate runic power.
    scent_of_blood = {
        id = 50421,
        duration = 20,
        max_stack = 3,
    },
    -- Grants your successful Death Coils a chance to empower your active Ghoul, increasing its damage dealt by 6% for 30 sec.  Stacks up to 5 times.
    shadow_infusion = {
        id = 91342,
        duration = 30,
        max_stack = 5,
        generate = function ( t )
            local name, _, count, _, duration, expires, caster = FindUnitBuffByID( "pet", 91342 )

            if name then
                t.name = name
                t.count = count
                t.expires = expires
                t.applied = expires - duration
                t.caster = caster
                return
            end

            t.count = 0
            t.expires = 0
            t.applied = 0
            t.caster = "nobody"
        end,
    },
    -- Silenced.
    strangulate = {
        id = 47476,
        duration = 5,
        max_stack = 1,
    },
    -- Runic Power is being fed to the Gargoyle.
    summon_gargoyle = {
        id = 61777,
        duration = 30,
        max_stack = 1,
        copy = { 61777, 50514, 49206 },
    },
    -- Your next Death Coil consumes no runic power.
    sudden_doom = {
        id = 81340,
        duration = 10,
        max_stack = 1,
    },
    -- Armor increased by $s1%.  Strength increased by $s2%.
    unbreakable_armor = {
        id = 51271,
        duration = 20,
        max_stack = 1,
    },
    unholy_blight = {
        id = 49222,
        duration = 10,
        max_stack = 1,
    },
    -- Enraged.  Physical damage increased by $s1%.  Health equal to $s2% of maximum health lost every sec.
    unholy_frenzy = {
        id = 49016,
        duration = 30,
        max_stack = 1,
    },
    -- Strength increased by 15%.
    unholy_strength = {
        id = 53365,
        duration = 15,
        max_stack = 1,
    },
    -- Attack speed and rune regeneration increased 10%. Movement speed increased by 15%. Global cooldown reduced by 0.5 sec.
    unholy_presence = {
        id = 48265,
        duration = 3600,
        max_stack = 1,
    },
    -- Healing improved by $s1%  Maximum health increased by $s2%
    vampiric_blood = {
        id = 55233,
        duration = function() return glyph.vampiric_blood.enabled and 40 or 25 end,
        max_stack = 1,
    },
    -- Increases attack power by $s1%.
    vengeance = {
        id = 76691,
        duration = 3600,
        max_stack = 1
    },

    will_of_the_necropolis = {
        id = 96171,
        copy = {52284, 81163, 96171},
        max_stack = 1,
        duration = 8,
    }

    -- -- Death Runes
    -- death_rune_1 = {
    --     duration = 30,
    --     max_stack = 1,
    -- },
    -- death_rune_2 = {
    --     duration = 30,
    --     max_stack = 1,
    -- },
    -- death_rune_3 = {
    --     duration = 30,
    --     max_stack = 1,
    -- },
    -- death_rune_4 = {
    --     duration = 30,
    --     max_stack = 1,
    -- },
    -- death_rune_5 = {
    --     duration = 30,
    --     max_stack = 1,
    -- },
    -- death_rune_6 = {
    --     duration = 30,
    --     max_stack = 1,
    -- }
} )

local GetRuneType, IsCurrentSpell = _G.GetRuneType, _G.IsCurrentSpell

spec:RegisterPet( "ghoul", 26125, "raise_dead", 3600)

spec:RegisterHook( "reset_precast", function ()
    death_runes.reset()
end )


-- Abilities
spec:RegisterAbilities( {
    -- Surrounds the Death Knight in an Anti-Magic Shell, absorbing 75% of the damage dealt by harmful spells (up to a maximum of 50% of the Death Knight's health) and preventing application of harmful magical effects.  Damage absorbed by Anti-Magic Shell energizes the Death Knight with additional runic power.  Lasts 5 sec.
    antimagic_shell = {
        id = 48707,
        cast = 0,
        cooldown = 45,
        gcd = "off",

        spend = 20,
        spendType = "runic_power",

        startsCombat = false,
        texture = 136120,

        toggle = "defensives",

        handler = function ()
            applyBuff( "antimagic_shell" )
        end,
    },


    -- Places a large, stationary Anti-Magic Zone that reduces spell damage done to party or raid members inside it by 75%.  The Anti-Magic Zone lasts for 10 sec or until it absorbs 14308 spell damage.
    antimagic_zone = {
        id = 51052,
        cast = 0,
        cooldown = 120,
        gcd = "off",

        spend_runes = {0,0,1},

        talent = "antimagic_zone",
        startsCombat = false,
        texture = 237510,

        toggle = "defensives",

        handler = function ()
            applyBuff( "antimagic_zone" )
        end,
    },


    -- Summons an entire legion of Ghouls to fight for the Death Knight.  The Ghouls will swarm the area, taunting and fighting anything they can.  While channelling Army of the Dead, the Death Knight takes less damage equal to her Dodge plus Parry chance.
    army_of_the_dead = {
        id = 42650,
        cast = 4,
        cooldown = 600,
        gcd = "spell",

        spend_runes = {1,1,1},

        gain = 30,
        gainType = "runic_power",

        startsCombat = true,
        texture = 237511,

        toggle = "cooldowns",

        start = function ()
            gain( 30, "runic_power" )
            applyBuff( "army_of_the_dead" )
        end,
    },


    -- Boils the blood of all enemies within 10 yards, dealing 180 to 220 Shadow damage.  Deals additional damage to targets infected with Blood Plague or Frost Fever.
    blood_boil = {
        id = 48721,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend_runes = function ()
            return buff.crimson_scourge.up and {0,0,0} or {1,0,0}
        end,

        gain = 10,
        gainType = "runic_power",

        startsCombat = true,
        texture = 237513,

        handler = function ()
            removeBuff( "crimson_scourge" )
        end,

        copy = { 49939, 49940, 49941 }
    },


    -- You assume the presence of Blood, increasing Stamina by 8%, armor contribution from cloth, leather, mail and plate items by 55%, and reducing damage taken by 8%.  Increases threat generated.  Only one Presence may be active at a time, and assuming a new Presence will consume any stored Runic Power.
    blood_presence = {
        id = 48263,
        cast = 0,
        cooldown = 1,
        gcd = "off",

        startsCombat = false,
        texture = 135770,

        nobuff = "blood_presence",

        handler = function ()
            removeBuff( "presence" )
            applyBuff( "blood_presence" )
        end,
    },


    -- Instantly strike the enemy, causing 40% weapon damage plus 306, total damage increased by 12.5% for each of your diseases on the target.
    blood_strike = {
        id = 45902,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend_runes = {1,0,0},

        gain = 10,
        gainType = "runic_power",

        startsCombat = true,
        texture = 135772,

        copy = { 49926, 49927, 49928, 49929, 49930 }
    },


    -- Immediately activates a Blood Rune and converts it into a Death Rune for the next 20 sec.  Death Runes count as a Blood, Frost or Unholy Rune.
    blood_tap = {
        id = 45529,
        cast = 0,
        cooldown = function() return  60 - (15 * talent.improved_blood_tap.rank) end,
        gcd = "off",

        spend = function() return glyph.improved_blood_tap.enabled and 0 or (0.06 * health.max) end, -- technically 6% of base health
        spendType = "health",

        startsCombat = true,
        texture = 237515,

        handler = function ()
            -- gain( 1, "blood_runes" ) -- TODO we actually gain a death rune
            -- I believe the precast check will catch this.
            applyBuff( "blood_tap" )
        end,
    },


    -- The Death Knight is surrounded by 3 whirling bones.  While at least 1 bone remains, she takes 20% less damage from all sources and deals 2% more damage with all attacks, spells and abilities.  Each damaging attack that lands consumes 1 bone.  Lasts 5 min.
    bone_shield = {
        id = 49222,
        cast = 0,
        cooldown = 60,
        gcd = "spell",

        spend_runes = {0,0,1},

        gain = 10,
        gainType = "runic_power",

        talent = "bone_shield",
        startsCombat = false,
        texture = 458717,

        toggle = "cooldowns",

        handler = function ()
            applyBuff( "bone_shield")
        end,
    },


    -- Shackles the target with frozen chains, reducing their movement by 95%, and infects them with Frost Fever.  The target regains 10% of their movement each second for 10 sec.
    chains_of_ice = {
        id = 45524,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend_runes = {0,1,0},

        gain = function() return 10 + ( 2.5 * talent.chill_of_the_grave.rank ) end,
        gainType = "runic_power",

        startsCombat = true,
        texture = 135834,

        handler = function ()
            applyDebuff( "target", "frost_fever" )
            applyDebuff( "target", "chains_of_ice" )
        end,
    },

    -- Summons a second rune weapon that fights on its own for 12 sec, doing the same attacks as the Death Knight but for 50% reduced damage.
    dancing_rune_weapon = {
        id = 49028,
        cast = 0,
        cooldown = 90,
        gcd = "spell",

        spend = 60,
        spendType = "runic_power",

        talent = "dancing_rune_weapon",
        startsCombat = false,
        texture = 135277,

        toggle = "cooldowns",

        handler = function ()
            applyBuff( "dancing_rune_weapon" )
        end,
    },


    -- Commands the target to attack you, but has no effect if the target is already attacking you.
    dark_command = {
        id = 56222,
        cast = 0,
        cooldown = 8,
        gcd = "off",

        startsCombat = true,
        texture = 136088,

        handler = function ()
            applyDebuff( "target", "dark_command" )
        end,
    },

    --Consume 5 charges of Shadow Infusion on your Ghoul to transform it into a powerful undead monstrosity for 30 sec.  The Ghoul's abilities are empowered and take on new functions while the transformation is active.
    dark_transformation = {
        id = 63560,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend_runes = {0,0,1},

        talent = "dark_transformation",

        startsCombat = false,
        texture = 342913,
        usable = function()
            if pet.ghoul.down then return false, "requires a living ghoul" end
            if buff.shadow_infusion.stacks < 5 then return false, "requires five stacks of shadow_infusion" end 
            return true 
        end,

        handler = function()
            applyBuff("dark_transformation")
            removeBuff("shadow_infusion")
        end,

    },

    -- Corrupts the ground targeted by the Death Knight, causing 62 Shadow damage every sec that targets remain in the area for 10 sec.  This ability produces a high amount of threat.
    death_and_decay = {
        id = 43265,
        cast = 0,
        cooldown = 30,
        gcd = "spell",

        spend_runes = {0,0,1},

        gain = 10,
        gainType = "runic_power",

        startsCombat = false,
        texture = 136144,

        handler = function ()
            applyBuff( "death_and_decay" )
        end,

        copy = { 49936, 49937, 49938 }
    },


    -- Fire a blast of unholy energy, causing 443 Shadow damage to an enemy target or healing 665 damage from a friendly Undead target.
    death_coil = {
        id = 47541,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function() return buff.sudden_doom.up and 0 or 40 end,
        spendType = "runic_power",

        startsCombat = true,
        texture = 136145,

        handler = function ()
            if talent.unholy_blight.enabled then applyDebuff( "target", "unholy_blight" ) end
            if talent.shadow_infusion.rank == 3 then addStack( "shadow_infusion" ) end
            removeBuff("sudden_doom")
        end,

        copy = { 49892, 49893, 49894, 49895 }
    },


    -- Opens a gate which the Death Knight can use to return to Ebon Hold.
    death_gate = {
        id = 50977,
        cast = 10,
        cooldown = 60,
        gcd = "spell",

        spend_runes = {0,0,1},

        startsCombat = false,
        texture = 135766,

        toggle = "cooldowns",

        handler = function ()
        end,
    },


    -- Harness the unholy energy that surrounds and binds all matter, drawing the target toward the death knight and forcing the enemy to attack the death knight for 3 sec.
    death_grip = {
        id = 49576,
        cast = 0,
        cooldown = function () return 35 - ( 5 * talent.unholy_command.rank ) end,
        gcd = "off",

        startsCombat = true,
        texture = 237532,

        toggle = "interrupts",

        handler = function ()
            applyDebuff( "target", "death_grip" )
        end,
    },


    -- Sacrifices an undead minion, healing the Death Knight for 40% of her maximum health.  This heal cannot be a critical.
    death_pact = {
        id = 48743,
        cast = 0,
        cooldown = 120,
        gcd = "spell",

        spend = 40,
        spendType = "runic_power",

        startsCombat = false,
        texture = 136146,

        toggle = "cooldowns",
        usable = function () return buff.raise_dead.up or pet.up end,

        handler = function ()
            dismissPet( "ghoul" )
            removeBuff("raise_dead")
            gain( 0.4 * health.max, "health" )
        end,
    },

    -- TODO this changed in cata. now heals based on % of damage lost
    death_strike = {
        id = 49998,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend_runes = {0,1,1},

        gain = 20,
        gainType = "runic_power",

        startsCombat = true,
        texture = 237517,

        healing = function()
            -- TODO needs damage taken code?
            local base = ( 0.07) * health.max
            local amt = base * ( 1 + (.15 * talent.improved_death_strike.rank ))
            return amt
        end,

        handler = function ()
            health.current = min( health.max, health.current + action.death_strike.healing )
            if buff.blood_presence.up then applyBuff("blood_shield") end
        end,
        copy = { 49999, 45463, 49923, 49924 }
    },



    -- Empower your rune weapon, immediately activating all your runes and generating 25 runic power.
    empower_rune_weapon = {
        id = 47568,
        cast = 0,
        cooldown = 300,
        gcd = "off",

        spend = -25,
        spendType = "runic_power",

        startsCombat = false,
        texture = 135372,

        toggle = "cooldowns",

        handler = function ()
            gain( 2, "blood_runes" )
            gain( 2, "frost_runes" )
            gain( 2, "unholy_runes" )
        end,
    },
    --An instant attack that deals 150% weapon damage plus 560 and increases the duration of your Blood Plague, Frost Fever, and Chains of Ice effects on the target by up to 6 sec.
    festering_strike = {
        id = 85948,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend_runes = {0,1,1},

        startsCombat = true,
        texture = 135371,

        handler = function ()
            if dot.frost_fever.ticking then
                applyDebuff( "target", "frost_fever" )
            end
            if dot.blood_plague.ticking then
                applyDebuff( "target", "blood_plague" )
            end
        end,

    },

    -- Strengthens you with the presence of Frost, increasing damage by 10% and increasing Runic Power generation by 10%.  Only one Presence may be active at a time, and assuming a new Presence will consume any stored Runic Power.
    frost_presence = {
        id = 48266,
        cast = 0,
        cooldown = 1,
        gcd = "off",

        startsCombat = false,
        texture = 135773,

        nobuff = "frost_presence",

        handler = function ()
            removeBuff( "presence" )
            applyBuff( "frost_presence" )
        end,
    },


    -- Instantly strike the enemy, causing 55% weapon damage plus 48 as Frost damage.
    frost_strike = {
        id = 49143,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function() return glyph.frost_strike.enabled and 32 or 40 end,
        spendType = "runic_power",

        talent = "frost_strike",
        startsCombat = true,
        texture = 237520,

        handler = function ()
            removeStack( "killing_machine" )
        end,
    },


    -- Instantly strike the target and his nearest ally, causing 50% weapon damage plus 125 on the primary target, and 25% weapon damage plus 63 on the secondary target.  Each target takes 10% additional damage for each of your diseases active on that target.
    heart_strike = {
        id = 55050,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend_runes = {1,0,0},
        gain = 10,
        gainType = "runic_power",

        talent = "heart_strike",
        startsCombat = true,
        texture = 135675,

        handler = function ()
            if glyph.heart_strike.enabled then applyDebuff( "target", "glyph_of_heart_strike" ) end
        end,
    },


    -- The Death Knight blows the Horn of Winter, which generates 10 runic power and increases total Strength and Agility of all party or raid members within 30 yards by 155.  Lasts 2 min.
    horn_of_winter = {
        id = 57330,
        cast = 0,
        cooldown = 20,
        gcd = "spell",

        spend = -10,
        spendType = "runic_power",

        startsCombat = false,
        texture = 134228,

        handler = function ()
            applyBuff( "horn_of_winter" )
        end,
    },


    -- Blast the target with a frigid wind dealing 198 to 214 Frost damage to all enemies within 10 yards.
    howling_blast = {
        id = 49184,
        cast = 0,
        cooldown = 8,
        gcd = "spell",

        spend_runes = function()
            if buff.freezing_fog.up then return {0,0,0} end
            return {0,1,0}
        end,

        gain = function() return 15 + ( 2.5 * talent.chill_of_the_grave.rank ) end,
        gainType = "runic_power",

        talent = "howling_blast",
        startsCombat = true,
        texture = 135833,

        handler = function ()
            removeBuff( "freezing_fog" )
            removeStack( "killing_machine" )

            if glyph.howling_blast.enabled then
                applyDebuff( "target", "frost_fever" )
                active_dot.frost_fever = active_enemies
            end
        end,
    },


    -- Purges the earth around the Death Knight of all heat.  Enemies within 10 yards are trapped in ice, preventing them from performing any action for 10 sec and infecting them with Frost Fever.  Enemies are considered Frozen, but any damage other than diseases will break the ice.
    hungering_cold = {
        id = 49203,
        cast = 0,
        cooldown = 60,
        gcd = "spell",

        spend = function() return glyph.hungering_cold.enabled and 0 or 40 end,
        spendType = "runic_power",

        talent = "hungering_cold",
        startsCombat = true,
        texture = 135152,

        toggle = "cooldowns",

        handler = function ()
            applyDebuff( "frost_fever" )
            active_dot.frost_fever = active_enemies
        end,
    },


    -- The Death Knight freezes her blood to become immune to Stun effects and reduce all damage taken by 30% plus additional damage reduction based on Defense for 12 sec.
    icebound_fortitude = {
        id = 48792,
        cast = 0,
        cooldown = 180,
        gcd = "off",


        startsCombat = false,
        texture = 237525,

        toggle = "defensives",

        handler = function ()
            applyBuff( "icebound_fortitude" )
        end,
    },


    -- Chills the target for 227 to 245 Frost damage and  infects them with Frost Fever, a disease that deals periodic damage and reduces melee and ranged attack speed by 14% for 15 sec.  Very high threat when in Frost Presence.
    icy_touch = {
        id = 45477,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend_runes = {0,1,0},

        gain = function() return 10 + ( 2.5 * talent.chill_of_the_grave.rank ) end,
        gainType = "runic_power",

        startsCombat = true,
        texture = 237526,

        handler = function ()
            removeStack( "killing_machine" )
            applyDebuff( "frost_fever" )
        end,

        copy = { 49896, 49903, 49904, 49909 }
    },


    -- Draw upon unholy energy to become undead for 10 sec.  While undead, you are immune to Charm, Fear and Sleep effects.
    lichborne = {
        id = 49039,
        cast = 0,
        cooldown = 120,
        gcd = "off",


        talent = "lichborne",
        startsCombat = true,
        texture = 136187,

        toggle = "defensives",

        handler = function ()
            applyBuff( "lichborne" )
        end,
    },



    -- Smash the target's mind with cold, interrupting spellcasting and preventing any spell in that school from being cast for 4 sec.
    mind_freeze = {
        id = 47528,
        cast = 0,
        cooldown = 10,
        gcd = "off",

        spend = function () return 20 - ( 10 * talent.endless_winter.rank ) end,
        spendType = "runic_power",

        startsCombat = true,
        texture = 237527,

        timeToReady = state.timeToInterrupt,
        debuff = "casting",

        toggle = "interrupts",

        handler = function ()
            interrupt()
        end,
    },

    -- A vicious strike that deals 100% weapon damage and absorbs the next (0.70 * Attack power) healing received by the target.
    necrotic_strike = {
        id = 73975,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend_runes = {0,0,1},

        gain = 10,
        gainType = "runic_power",

        startsCombat = true,
        texture = 132481,

        handler = function ()
            -- TODO:
        end,
    },


    -- A brutal instant attack that deals 80% weapon damage plus 467, total damage increased 12.5% per each of your diseases on the target, but consumes the diseases.
    obliterate = {
        id = 49020,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend_runes = {0,1,1},

        gain = function() return 15 + ( 2.5 * talent.chill_of_the_grave.rank ) end,
        gainType = "runic_power",

        startsCombat = true,
        texture = 135771,

        handler = function ()
            if talent.annihilation.rank < 3 then
                removeDebuff( "target", "frost_fever" )
                removeDebuff( "target", "blood_plague" )
                removeDebuff( "target", "crypt_fever" )
            end
        end,

        copy = { 51423, 51424, 51425 }
    },

    outbreak = {
        id = 77575,
        cast = 0,
        cooldown = function() return spec.blood and 30 or 60 end,
        gcd = "spell",

        startsCombat = true,
        texture = 348565,

        handler = function ()
            applyDebuff("target", "frost_fever" )
            applyDebuff("target", "blood_plague")
        end,
    },


    -- The Death Knight's freezing aura creates ice beneath her feet, allowing her and her party or raid to walk on water for 10 min.  Works while mounted.  Any damage will cancel the effect.
    path_of_frost = {
        id = 3714,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend_runes = {0,1,0},

        startsCombat = false,
        texture = 237528,

        handler = function ()
            applyBuff( "path_of_frost" )
        end,
    },


    -- Spreads existing Blood Plague and Frost Fever infections from your target to all other enemies within 10 yards.
    pestilence = {
        id = 50842,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend_runes = {1,0,0},

        gain = 10,
        gainType = "runic_power",

        startsCombat = true,
        texture = 136182,

        handler = function ()
            if dot.frost_fever.ticking then
                active_dot.frost_fever = active_enemies
                if glyph.disease.enabled then applyDebuff( "target", "frost_fever" ) end
            end
            if dot.blood_plague.ticking then
                active_dot.blood_plague = active_enemies
                if glyph.disease.enabled then applyDebuff( "target", "blood_plague" ) end
            end
        end,
    },

    --Calls upon the power of Frost to increase the Death Knight's Strength by 20%.  Icy crystals hang heavy upon the Death Knight's body, providing immunity against external movement such as knockbacks.  Lasts 20 sec.
    pillar_of_frost = {
        id = 51271,
        cast = 0,
        cooldown = 60,
        gcd = "off",

        spend_runes = {0,1,0},

        gain = 10,
        gainType = "runic_power",

        talent = "pillar_of_frost",

        startsCombat = true,
        texture = 458718,

        handler = function()
            applyBuff("pillar_of_frost")
        end,

    },


    -- A vicious strike that deals 50% weapon damage plus 189 and infects the target with Blood Plague, a disease dealing Shadow damage over time.
    plague_strike = {
        id = 45462,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend_runes = {0,0,1},

        gain = 10,
        gainType = "runic_power",

        startsCombat = true,
        texture = 237519,

        handler = function ()
            applyDebuff( "target", "blood_plague" )
        end,

        copy = { 49917, 49918, 49919, 49920, 49921 }
    },


    -- Raises the corpse of a raid or party member to fight by your side.  The player will have control over the Ghoul for 5 min.
    raise_ally = {
        id = 61999,
        cast = 0,
        cooldown = 600,
        gcd = "spell",

        startsCombat = false,
        texture = 136143,

        handler = function ()
        end,
    },


    -- Raises a Ghoul to fight by your side.  If no humanoid corpse that yields experience or honor is available, you must supply Corpse Dust to complete the spell.  You can have a maximum of one Ghoul at a time.  Lasts 1 min.
    raise_dead = {
        id = 46584,
        cast = 0,
        cooldown = function() return 180 - ( talent.master_of_ghouls.enabled and 60 or 0 ) end,
        gcd = "spell",

        essential = true,

        startsCombat = false,
        texture = 136119,

        toggle = function()
            if talent.master_of_ghouls.enabled then return end
            return "cooldowns"
        end,

        usable = function() return not pet.up, "cannot have a pet" end,

        handler = function ()
            if talent.master_of_ghouls.enabled then
                summonPet( "ghoul" )
            else
                removeBuff( "raise_dead" )
                summonTotem( "raise_dead" )
                applyBuff( "raise_dead" )
            end
        end,
    },


    rune_strike = {
        id = 56815,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 30,
        spendType = "runic_power",

        startsCombat = true,
        texture = 237518,
    },


    -- Converts 1 Blood Rune into 10% of your maximum health.
    rune_tap = {
        id = 48982,
        cast = 0,
        cooldown = 30,
        gcd = "off",

        spend_runes = {1,0,0},

        talent = "rune_tap",
        startsCombat = true,
        texture = 237529,

        toggle = "cooldowns",

        handler = function ()
            gain((0.1  * health.max), "health" )
        end,
    },


    -- An unholy strike that deals 70% of weapon damage as Physical damage plus 380.  In addition, for each of your diseases on your target, you deal an additional 12% of the Physical damage done as Shadow damage.
    scourge_strike = {
        id = 55090,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend_runes = {0,0,1},

        gain = 20,
        gainType = "runic_power",

        talent = "scourge_strike",

        startsCombat = true,
        texture = 237530,

        handler = function ()
            -- TODO: talent.desecration effect?
        end,
    },


    -- Strangulates an enemy, silencing them for 5 sec.  Non-player victim spellcasting is also interrupted for 3 sec.
    strangulate = {
        id = 47476,
        cast = 0,
        cooldown = function() return  120 - (30 * talent.hand_of_doom.rank) end,
        gcd = "spell",

        spend_runes = {1,0,0},

        gain = 1,
        gainType = "runic_power",

        startsCombat = true,
        texture = 136214,

        toggle = "interrupts",

        timeToReady = state.timeToInterrupt,

        handler = function ()
            interrupt()
        end,
    },


    -- A Gargoyle flies into the area and bombards the target with Nature damage modified by the Death Knight's attack power.  Persists for 30 sec.
    summon_gargoyle = {
        id = 49206,
        cast = 0,
        cooldown = 180,
        gcd = "spell",

        spend = 60,
        spendType = "runic_power",

        talent = "summon_gargoyle",
        startsCombat = false,
        texture = 132182,

        toggle = "cooldowns",

        handler = function ()
            summonPet( "gargoyle" )
            applyBuff( "summon_gargoyle" )
        end,
    },


    -- Induces a friendly unit into a killing frenzy for 30 sec.  The target is Enraged, which increases their physical damage by 20%, but causes them to lose health equal to 1% of their maximum health every second.
    unholy_frenzy = {
        id = 49016,
        cast = 0,
        cooldown = 180,
        gcd = "off",

        talent = "unholy_frenzy",
        startsCombat = false,
        texture = 136224,

        toggle = "cooldowns",

        handler = function ()
            applyBuff( "unholy_frenzy" )
        end,
    },


    -- You are infused with unholy fury, increasing attack speed and rune regeneration by 10%, and movement speed by 15%, and reducing the global cooldown on your abilities by 0.5 sec.  Only one Presence may be active at a time, and assuming a new Presence will consume any stored Runic Power.
    unholy_presence = {
        id = 48265,
        cast = 0,
        cooldown = 1,
        gcd = "off",

        startsCombat = false,
        texture = 135775,

        nobuff = "unholy_presence",

        handler = function ()
            removeBuff( "presence" )
            applyBuff( "unholy_presence" )
        end,
    },


    -- Temporarily grants the Death Knight 15% of maximum health and increases the amount of health generated through spells and effects by 35% for 10 sec.  After the effect expires, the health is lost.
    vampiric_blood = {
        id = 55233,
        cast = 0,
        cooldown = 60,
        gcd = "off",

        talent = "vampiric_blood",
        startsCombat = false,
        texture = 136168,

        toggle = "defensives",

        handler = function ()
            applyBuff( "vampiric_blood" )
            if not ( glyph.vampiric_blood.enabled ) then
                health.max = health.max * 1.15
            end
        end,
    },
} )

spec:RegisterOptions( {
    enabled = true,

    aoe = 2,

    gcd = 47541,

    nameplates = true,
    nameplateRange = 8,

    damage = true,
    damageExpiration = 6,

    package = "Blood",
    usePackSelector = true,
} )


spec:RegisterPack( "Blood", 20240620, [[Hekili:nVvBVTnos4FlflUGMT58f70SBlqCbAVUfB7HRTyD3TFZs0s02cvwuqIQ5YHa9B)MziLmPePStID6HfBtSf5mpZ7dhQmF88VmFwmtYN)XjNp55N)ltoF04lM8YlF58zYBY5ZNLZI(gBf8lzSnW)(MuHig)2BsfSyC3LIQIi4jFv81zjBkNpBrvsQ89zZx4KYpF(mwLCTOy(Szv58ISQsypRtIJ5QTWlJMp7lRtkRdZlsefjYBQdXpTGvYJRdfz1HY186qndhnFwAsPSeXctWHF8rsQ4zSfP845VrrZIKCzIiB(S3YzY11HSmGwVLhXaQ)3Rd)ZwAhjePXIRHFBPOOo81F63QdJzBiDalsrJyKgbajcIrkmxcczhE2SurLCrbN9ToO4155PaNrouWxwWlbi9j9sbXDzDiPPRd)CkBvfxTY3vikLWp4FNdFIvaFnBbWaqHiQd5)N8KcaKatK8IegYXfvlxoAbsPGCIqJk4ByjzG68QP1HJRdV9wq8uRBjs(GLi17SmuaVWJaMZlLjP8m0hWsebvka)2NQKQfcu53rqqtrhXLeozs03sYwDMEjP8Ys02ZqpGcAvag(o8tEgFtcVuVTKSL8ijGstvHqAjFAsxhEci(WZS0rMp8PnCjOdjQdFM1JmPaO2AFwl2(56Wj1HNI6YN7rxUMZkKbLYIKV1vB(w(swvQ2u)746QdNrlSVJQsvdbjfnAYlvoql5xJaxdjt9txWIM9lrOEPhOQe3fIKuxMDT18nWJ7dMncY4s2XlDyerK(plGqBmCCweKFbfj0fvLiOkFiK)kIOOBn5uhPiuqPIoJGnds1V4rQub2onaKCPtE0O4rjdSzP43HiJjvOFbpvCnGJZ)BQpRvhqAoEASAPzczJOBknkQnkpsQTbNRKLNOfhLAVKiKww(vpYss0nbsrv0A3PESJbVobLH3hbp4l4EuYwI0aSTrfuWiLcwYavQe3DkyNtjZi5mAAIhdIqjpsKfB5X9evGNVGsfPHVAdhKIG4eozAhFokYVWxUik6ZT9tl2DYZOK7MpzAxFeKDVjDgu4F5Wv3mst0XBLqh6GTvsSCm9egaSey8(YZ)OkJ3HLRGyZcMK4ArvwseuzxajI2Yp4B5MSBWc4uG4Vlka1RaStFnjtIEW21UrOGvWKW)Rnyy8JrQwGabILbxtBN4A3s4956FWs0zb61SaYWYQnBWVLbY8ArvQw(zXXjiryWx82ppZqSrYbTqansjH)dyiPi3zlmew(3jOb8DfC()TrrtIsrvo0mulp2allyjTkxTP4n197QkUPb)OURatwG6BMucTeQnHq9XcwuckzSfjPuVA0E(uru5PDRwSeOPRwj6dIz3KXYPFb6bmBvzdsYS1MdalE2QKmoVG86wLk(owBa6dbclLgaRuXOGsfFCvCUp6GW4nLipgTA0zyVijzFJllp12NyltQagq7XvbvhfzyzreSvXsFLZYr66O50KSiOHrQ11CwbAWq5d71IIU712QIWbu421ezhQyyseh6UeDFefYezvSZsIVxVkWLPzz7SW4fyHrscAAyPGhxPzR)IHxC(q1780PnbY))U1AFLZwiW0I6CZoIufuQ2MMk6wZILcsC8nU6YOTBITmq3mr3Ilnq57SnGkijkyH6aG9rZFPxrR6DFAoQRxCZ6j332svf8ioibXd3OKZcvwvyKSCNz1PWSVWYvy(RubDXsDzJpYJke5Iu6iOT9G200kja8nCOEDg28KgZMiL00yxcy5gGKbzTuuR07vVRb18nu6mRawhcWVTrN1ZoHX(ya0hd2UR2gpiY)zxDNEc1CQcXJmBCyKA77SY6mOhmSHtmqJoeJIwypvyiPXPhqGz1DL9HhUXYChO(9aKk748cJvJqiqnIdCiciO9DG37Xze0zxqL)FMTwG9HIM0MdSUSkn9SDzRo7UEucvohIpJIQkk4zWYMshcfZmvraX)ZVhNezSVZ1A2FN3aqtfMzBI2keiRmAVhp5CtzLwFaT8TYYRMQwhISHpgRNedADDBMbOrOsi4oLRTON1yo12gTLVGehc0FNLKI88UgO9uWPWJ5B8omFTfEqVuNp(09lOTBBb70t3rdk3VtB4Rc)Dij(aXs)kfljVw0ciZyXwtwZuNYCVo4mDqXCjw0Y4Ow0kgkJ5luzmvUDoJ9oXPTtv3LwJYH2Bpd3T5YS)ZzzGPPm2xxdkbjh(4aUpFMfPtZBD8kYY1TfmLHCV6SCpkkV98xgnL1o(i3DFoXxhgdm7o1jwTNzhvwBx(GhexWhSV2eFTNCKMW0(nLicz(M6(XEqq75WCimo4PD9o7eVdhzYUpF6ry4it29XwpYdhjhofGyZcMZXJyN9dwAPVlKOXSRxcM4yPqfnHexNSjRSs1Mj3vt)xVMNTDdLsiWUSxYfBOmIMiGJbWCVoR3LBhR4buaA1WbTJSuDQkFDcZk2CtZHAidLdG)AyngNMs5DmEFXp5P0KVt5bHP7OSI6t3Alll4RG04oLf10t92I6w3TD5BFXoa)(6P7aJx4AcrEIk3Ra)Xny946NmEO5iLlA6gOlEzyl(4NheOndHe4BoMdguE4fjkkLEXcLXakwuI8sDb0xcjINDnRiJMZ3S3dNzwv78IARtCwoQ(diDfltsHmi)0p1MZGkW(VYswTww)b8R3EH067IU(d0doQjAQ)GcTLJAL9Nn9FyNT5SKLt9LeYcJh9SkEq72KDN1ZcofWHbg)HKaXnS7MVZb2hBH9JqAd3iBB2lhy6cti9yKIWngTtF5s3zIZhAQb3yqrsF8g4(pHwlvlzTqzWBAPLpa1nURfhzcoe3OIj32ENkMm7iFZjMaOZDNyII97gsmjw7DKysMd8nHyYph3fIjNpW3QHjN7FTky66TN28QPxyLe5GC3fMaO5Isq2oW9yC10X3ER)7V4k74172Lry5hBumaq0tCCZeMm6r4EgmrN9fF01szxQ6iCrcMqPz8xTv39EPcMG6OE5aMWZXLv0xDDYtuBWXqh1G(WDDaD0DMxiWz4O(NYeuONAtn3iWRSCR)romFR0vgQleZoMo80j3ERRPcJFVTr42BFIRr433v(Uos(EERBbSJj0)QP0w6vO8rAE79RLQJTEQlL7ypkxkhzVrOnD8P72t3Ld2DBg6(8qgiP0pYbJ7lzMP35lo)ehdSC6Kt8oOYPU8H23jC33jahDEBg2(Z72HT7rBa29n34O1BbB)XzF1L2H(2nw8OorAtSBoQCc93td(dCoZ2nLPhLn1cIVxmrl2(GgGSjVTgwDl)D(YbQaG)x4o35Fh(8F71SHTmFwhKZ75DVVJa2siADP3E(mSPaLwG12c3D7f5F7zdHoaAJLAFD(TnZ4EpSVI(Dz)rPF8FKV49DfWT)jcqIO7GRt850FYt1nO1zJpZ4Rn33v29Z9Zto1vyZH5vOVRK2nZMnuGEVgSu1H9LKVl2SlV1PPxOqX(xW7W(6V7oACRo8U076dTIWd497URySxvuoP)B69RgF(HSoZbuI2)6udkwpKxr9H8v2zXrf1992O3L0hP6NnjkEKQH2img3Uf93r3NY0)T8vh(03WLStNpRmNhHxIdE3jZ)F]] )

spec:RegisterPack( "Frost", 20240619.2, [[Hekili:1M1wVTTnu4FlbfiVSopBNM0lR2pu0nSMI2uuLIGHHkjAjAlIitkisvppeOF77COKSKOiTDU0xsC4LZ9Z3HFo(t8V23lMOO(FE64PVy8ftE9OjVC6zV41(EQTzuFVms0TKvWh4K1Wp)ZCHuHRUnvqIXBlff5rWo3iUXJTw67TOGLQ(a3FHDj)k4kz0i)pFHVxcloMwDsQmY376eMSmmlNjYzQTLH4FTGiPXLHcEzOkHwgwRNr(EPmPsQDa6ssrQc(4N1oeLtwKsJ9FNVxeiiAoJaMvQqehKxWPYrrf55uUQmCwz44YWtldxI(LZDl4jI0T2223JePycoO01zIn0C9Hc2qjzWIkW5DBqflxoQwYsfiYvQKrfzTsmJLMsYdeld0whkTZE4sRY)xwKVff0lUVcshh07zyw9nzH(3Gco)(QGwHi3YjzsAGeke4RKO0UWP0uK8vu1ifBnnqjcIzqjYBHmZzTYRk3cQIDlff2lFmctSifpnwydI6vpgrLi2KcoyWIusv291gsR5G5egeoIPqdNUrjNLvTXxXnkdXDkdJe8ygUo008RxF17V6nLHKyyJpSoJOyuEeCuXYYW)wuOsG9GZrsbZLd7(dypLOm0m2BM3gM8Blm2xrJHCX8n4Wtg7WJRkwvKmdh(D46GLsY66VDTsiwOsm7uXa)KkJPdkqtUb2zEz45JoxBsMiiwRI6BvD3cblIP5G5rZvegGAbkJfbOAi6GlRwFMa9rAT65OvpUYQmHr2vowOwKtj3Ayr)bxwGbAO2aQqaeumxNdghEVFq7Q6tGZiuJQ8HL0FawGIfDR(Y3Dxzy9(vbUSuYQcAZb0wMjKK9Q7(M3FvTxz47Wnld3WWcYVc5de9xenOSBzoL(FO0wkw1u7ycH9qumdAh0J0GFHUE1ihUqD)IuA7XeXBhMOoMzVYPnp9f9Pkd9QRIq7Oqp5Rk48nDZLUAsNm5XOtO7gAU6HnDBjX9pGBQ21mHFpIEIVj1YUo424vv(YUwJUqwcEFNRBBJJwfDF7KXhZeCRWchy(UU)t7)MtmSmmWvE9QDh5bNthMoFm5sZrwhrU0mjMqHC1hHjbAv(jsucJx356YI1DX3wDLG1v3OPr21yVerohN0SHXvynGJi8FbhRAW2n6dwBcPBiBTAkNupsQV4RnMPMtK6P03x9qtuNDXr2Zi9PUgNCFNP)iNeRTfZHi29TEzB3VIAQjWVRiv)SJZ0lksxq67dcTgOXe)SQiT7q4DZafAKhrASyd3cytFyj9nwtvDJ))KGAgaJ1)bkthD(bEcZu9tyq6z50iX6feRuIAcQ1wcCwj(2qZxA1s7AhZUiRVHVraJW4Pnkp7ExFX61cEWk4LXITP0oMzGKIXCqfxyJLJlabl3FIoaaHay6SeVud7ZZhnX3BdjNx9S2gMMILS0Ay21mzvPKSiltKdzLLcOyyfLd(muCafw8BPk5OYq4n1QQlPTG1u4jF4ZstiWY4dd22JflpkTigl)OaSpn)nLxcVqVm8F(g2O)bfDT87phRyzrjDpnHVTvR1J2P)BwklIPsBLBm(PAYXnk93HmxEJAUUseqf23Rl3BxAAhnVbqu64r1Iu1CuD0qVeVy9cAoQyzkmjQ8sGHbeWWfMwH4ILnA65WMyEshM99E2Z2bV8ESl5JC2Qev5LWYdR3aZ)s8cFjNMvGwwLGH1R)WOD5)Fz2Vzum(C2YzolsTlbJYZNpO6A2f2Vy)Ysl3BsJR8jnw0o)axIuOerWWIabwAe0Gl16LGcS8vlO9VHFJgZgFQfWjyvBWoZg3vjgZtmdGDz115wTFRch5fQ(gc2ZHp110TocXGn5EvTUMJXzsi82lQ2DGgkHHm2F7SZ6EH2x7DuhV3Bb2Zn0L))0zY31YAF7XUi3W49P7n)mKpFTJyNH(Wsg4aOYTmS8TZMCQ1zCZbk61A5HX4EFzFlmWNpdyFxRWdqOUxzsnLCuQN4GW4D3DIZ3WxPWdrrEVvA24m7qUhKb8EvKl)Bqu7PNEBpqLUVpCNDzl6AhiCAT9(KsA9iR2MdeyDaABP5Wbu(86zmDd5pzmpDJb(WIYpq6K7lE6GE5GyYXWvSFbFVr7yLLDUJ1AYbbrN9qha9)PcZ2066NbCexh6sgXoNXP(Dt)SzMTxGGNGgRtTsjBoq2YXykKgMN(FB1vi)uTubsmWOAbqAXRidguxiLAEk())p]] )

spec:RegisterPack( "Unholy", 20240620, [[Hekili:1Ev3oUjou4NLOkfntBx2eMMot3nzUOAVPZk1BsR6fRwahWeScyJSnD2ufXZ(ESHqSjysAR6nZqS957Z(8)jyEWNcwNGK4Gp6pZ)nZER)mV53DN)D3hSwUVehSUefVdTf(GIkG)(zAglFVA595muIsCbRIhdB9f2xwtkebR3urYLFGgSzyOxaIuIJd(4BdwNrssWnNelIdw)PmIOoQKtyCICFDK6xBqcCsDeJwhjZW1rT84fSoNiKc9laNIQYLWNFu)IqXscJgSUGqtct5y83G7hMI2KJtcEFGeUsQJDAL1XaFyobbpBeFlw6jjf4qjlmHauUSo6U6OP1rkG)koetXfeSqVH)j6eXGQyloui5KDyfn39RGMuSqbcDRbrV5xbrjyKmlmMrYvuSWjftQJsysVuotidtXFfZb6I3b3WtyrI3d0xfNPG6TxcQn5mwsyzoABf(CSAw341FVPrpbX3fk5iQiLXlqnlAz8FWj9BQst9gaaVQYteuPJbu(v0VTxH37(5WtSNIkfW7PuzufkeNp7NdYg9xAfxF)Mp)NdTsM()kKCh3OrQv1awgmDRmdqr7MP3R3Z0IbwLCdhJ2P5WDqZi3wnp3uhfZy5jSNPEwwj9boCO9MmYwAfxELqQx(wdJuvrbJgUfIMy7Z1EDZDh05oIqFpVkVClDI7GVX4XfjhvwTH)9GOo6vwBzIGofr)SgVeYAyPSkHmuKCmnUrpnA4Eb7RhVrPKTzYqoUarOaSpwhTOX00NqyN59ttHGu9j4yuJh)9oPCaS87h4SPnL3C3zkA9H4vuSOl5kOfwUY6UDEjH5JKTqt(Wq2OG0gPlX5q1h8hjHYLyDsJbacZ6JS3okeQ1x7zWQ7epaFK4Ws2ZGlBCfhcfLGTa48Hzn28BoM2Os1Ia4iYkStNySENlZY2nhkhr3HUTJGjJCClUYqqoLqcnTsO2tiHUI0STWYV3UGPV7KLJzihSWSTxQvXuF35lVinxVP1MY3ywWTNpEVgTwyE0ZCn7D4rZuCL30ZCcDNlyIr9IEj4b3fuYENM2rAHWiCQZXgu4Z6FdLOsnuUZhC09mJXPHS0WNjuyhRcN2Bb4jHSVCCmRyd6u)WgO3Rjg4ScDEADd4CszZUV)up3DT13Rm8rj9uAVl1snulq6vGugo1TDBgRkx4D8WDxkoIaniaQ6KHAE(4Pq8I9kuGPbAo7PxCOa(GMa3wOdQbAl2HABqagQN3EDe5soTzaQKQswCC8N5VZdIGFgXP6M86g1HLcvkBM0PGie6AHIQYsgh8BG0r1rBHSaCsmm(d41VdlfE1r1rFq2iK(guGPjkdMmdblRkIV3AmkACEvIkpcMaAn(Fu)uD0Vvh9pFwGviHle)7RRJEoJeNzEAeD)jwRJOmf4)xzojMiZpHBI6R2PZos6FcEp8J08PgiGSo)Rc0eZL8ny(zsEUXlQfs5XJQ1g6LOvfBWCfXICOdL6N(qHsHPwW)yII6i98HWMk7KwnhS(fVOoQzg26O)sfs)3uvth1pbRFUtpC)FQbmHxNP(vR(9EbpVMKU68yIHf9KlUsQlezmme99)F9zEHRMpByrT97hsWHLRXFF4Z3jbCoJbUnx2UcrZdV)uPlVBQDrVL(Mq0pR)peiNsI)djExnqL0tC14THawdQ2j0GDKBElpVBeZTTMEPZ1ZrlmMgb75V(oK800KFhc16YC9cCCENoroFyYPogK06zAxh)cxGP34CGXdhgCyX2Lnhu8wxpdx(itVk)GttrPWYfuUqA6nTUY9e8vglBk3sBp)x6F75roDZyPFCntUn1AQThxC4Gnqpo)CxPnTrG9oP)45mgEKRLRMFP8edoHdi30b7pUhGMTtokytAKXr)PUtdnWKqpU6HzhoCZaZ)m11SplV0Cp3caozSib3t6SCXTotd6sfoDmB71HW1RqT9vgZDyml71ZNTbCY4ZqCoLqN)99KAn8RMzE6EvRvu5CEGkjSAW61vLyoTsi09Gg8)p]] )



spec:RegisterPackSelector( "blood", "Blood", "|T135770:0|t Blood",
    "If you have spent more points in |T135770:0|t Blood than in any other tree, this priority will be automatically selected for you.",
    function( tab1, tab2, tab3 )
        return tab1 > max( tab2, tab3 )
    end )

spec:RegisterPackSelector( "frost", "Frost", "|T135773:0|t Frost",
    "If you have spent more points in |T135773:0|t Frost than in any other tree, this priority will be automatically selected for you.",
    function( tab1, tab2, tab3 )
        return tab2 > max( tab1, tab3 )
    end )

spec:RegisterPackSelector( "unholy", "Unholy", "|T135775:0|t Unholy",
    "If you have spent more points in |T135775:0|t Unholy than in any other tree, this priority will be automatically selected for you.",
    function( tab1, tab2, tab3 )
        return tab3 > max( tab1, tab2 )
    end )