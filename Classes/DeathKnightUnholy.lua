-- DeathKnightUnholy.lua
-- June 2018

local addon, ns = ...
local Hekili = _G[ addon ]

local class = Hekili.Class
local state = Hekili.State

local roundUp = ns.roundUp

local PTR = ns.PTR


-- Conduits
-- [x] Convocation of the Dead
-- [-] Embrace Death
-- [x] Eternal Hunger
-- [x] Lingering Plague


if UnitClassBase( "player" ) == "DEATHKNIGHT" then
    local spec = Hekili:NewSpecialization( 252 )

    spec:RegisterResource( Enum.PowerType.Runes, {
        rune_regen = {
            last = function ()
                return state.query_time
            end,

            interval = function( time, val )
                local r = state.runes

                if val == 6 then return -1 end
                return r.expiry[ val + 1 ] - time
            end,

            stop = function( x )
                return x == 6
            end,

            value = 1,    
        },      
    }, setmetatable( {
        expiry = { 0, 0, 0, 0, 0, 0 },
        cooldown = 10,
        regen = 0,
        max = 6,
        forecast = {},
        fcount = 0,
        times = {},
        values = {},
        resource = "runes",

        reset = function()
            local t = state.runes

            for i = 1, 6 do
                local start, duration, ready = GetRuneCooldown( i )

                start = start or 0
                duration = duration or ( 10 * state.haste )
                
                start = roundUp( start, 2 )

                t.expiry[ i ] = ready and 0 or start + duration
                t.cooldown = duration
            end

            table.sort( t.expiry )

            t.actual = nil
        end,

        gain = function( amount )
            local t = state.runes

            for i = 1, amount do
                t.expiry[ 7 - i ] = 0
            end
            table.sort( t.expiry )

            t.actual = nil
        end,

        spend = function( amount )
            local t = state.runes

            for i = 1, amount do
                if t.expiry[ 4 ] > state.query_time then
                    t.expiry[ 1 ] = t.expiry[ 4 ] + t.cooldown
                else
                    t.expiry[ 1 ] = state.query_time + t.cooldown
                end
                table.sort( t.expiry )
            end

            if amount > 0 then
                state.gain( amount * 10, "runic_power" )

                if state.set_bonus.tier20_4pc == 1 then
                    state.cooldown.army_of_the_dead.expires = max( 0, state.cooldown.army_of_the_dead.expires - 1 )
                end
            end

            t.actual = nil
        end,

        timeTo = function( x )
            return state:TimeToResource( state.runes, x )
        end,
    }, {
        __index = function( t, k, v )
            if k == "actual" then
                local amount = 0

                for i = 1, 6 do
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
                return t.current == 6 and 0 or max( 0, t.expiry[6] - state.query_time )


            elseif k == "add" then
                return t.gain

            else
                local amount = k:match( "time_to_(%d+)" )
                amount = amount and tonumber( amount )

                if amount then return state:TimeToResource( t, amount ) end
            end
        end
    } ) )

    spec:RegisterResource( Enum.PowerType.RunicPower, {
        swarming_mist = {
            aura = "swarming_mist",

            last = function ()
                local app = state.debuff.swarming_mist.applied
                local t = state.query_time

                return app + floor( ( t - app ) / class.auras.swarming_mist.tick_time ) * class.auras.swarming_mist.tick_time
            end,

            interval = function () return class.auras.swarming_mist.tick_time end,
            value = function () return min( 15, state.true_active_enemies * 3 ) end,
        },          
    } )


    spec:RegisterStateFunction( "apply_festermight", function( n )
        if azerite.festermight.enabled then
            if buff.festermight.up then
                addStack( "festermight", buff.festermight.remains, n )
            else
                applyBuff( "festermight", nil, n )
            end
        end
    end )

    
    local spendHook = function( amt, resource, noHook )
        if amt > 0 and resource == "runes" and active_dot.shackle_the_unworthy > 0 then
            reduceCooldown( "shackle_the_unworthy", 4 * amt )
        end
    end

    spec:RegisterHook( "spend", spendHook )


    -- Talents
    spec:RegisterTalents( {
        infected_claws = 22024, -- 207272
        all_will_serve = 22025, -- 194916
        clawing_shadows = 22026, -- 207311

        bursting_sores = 22027, -- 207264
        ebon_fever = 22028, -- 207269
        unholy_blight = 22029, -- 115989

        grip_of_the_dead = 22516, -- 273952
        deaths_reach = 22518, -- 276079
        asphyxiate = 22520, -- 108194

        pestilent_pustules = 22522, -- 194917
        harbinger_of_doom = 22524, -- 276023
        soul_reaper = 22526, -- 343294

        spell_eater = 22528, -- 207321
        wraith_walk = 22529, -- 212552
        death_pact = 23373, -- 48743

        pestilence = 22532, -- 277234
        unholy_pact = 22534, -- 319230
        defile = 22536, -- 152280

        army_of_the_damned = 22030, -- 276837
        summon_gargoyle = 22110, -- 49206
        unholy_assault = 22538, -- 207289
    } )


    -- PvP Talents
    spec:RegisterPvpTalents( { 
        cadaverous_pallor = 163, -- 201995
        dark_simulacrum = 41, -- 77606
        decomposing_aura = 3440, -- 199720
        dome_of_ancient_shadow = 5367, -- 328718
        life_and_death = 40, -- 288855
        necromancers_bargain = 3746, -- 288848
        necrotic_aura = 3437, -- 199642
        necrotic_strike = 149, -- 223829
        raise_abomination = 3747, -- 288853
        reanimation = 152, -- 210128
        transfusion = 3748, -- 288977
    } )


    -- Auras
    spec:RegisterAuras( {
        antimagic_shell = {
            id = 48707,
            duration = function () return ( talent.spell_eater.enabled and 10 or 5 ) + ( conduit.reinforced_shell.mod * 0.001 ) end,
            max_stack = 1,
        },
        antimagic_zone = {
            id = 145629,
            duration = 3600,
            max_stack = 1,
        },
        army_of_the_dead = {
            id = 42650,
            duration = 4,
            max_stack = 1,
        },
        asphyxiate = {
            id = 108194,
            duration = 4,
            max_stack = 1,
        },
        chains_of_ice = {
            id = 45524,
            duration = 8,
            max_stack = 1,
        },
        dark_command = {
            id = 56222,
            duration = 3,
            max_stack = 1,
        },
        dark_succor = {
            id = 101568,
            duration = 20,
        },
        dark_transformation = {
            id = 63560, 
            duration = function () return 15 + ( conduit.eternal_hunger.mod * 0.001 ) end,
            generate = function( t )
                local cast = class.abilities.dark_transformation.lastCast or 0
                local up = pet.ghoul.up and cast + t.duration > state.query_time

                t.name = t.name or class.abilities.dark_transformation.name
                t.count = up and 1 or 0
                t.expires = up and cast + t.duration or 0
                t.applied = up and cast or 0
                t.caster = "player"
            end,
        },
        death_and_decay = {
            id = 188290,
            duration = 10,
            max_stack = 1,
        },
        death_pact = {
            id = 48743,
            duration = 15,
            max_stack = 1,
        },
        deaths_advance = {
            id = 48265,
            duration = 10,
            max_stack = 1,
        },
        defile = {
            id = 152280,
            duration = 10,
        },
        festering_wound = {
            id = 194310,
            duration = 30,
            max_stack = 6,
            --[[ meta = {
                stack = function ()
                    -- Designed to work with Unholy Frenzy, time until 4th Festering Wound would be applied.
                    local actual = debuff.festering_wound.up and debuff.festering_wound.count or 0
                    if buff.unholy_frenzy.down or debuff.festering_wound.down then 
                        return actual
                    end

                    local slot_time = query_time
                    local swing, speed = state.swings.mainhand, state.swings.mainhand_speed

                    local last = swing + ( speed * floor( slot_time - swing ) / swing )
                    local window = min( buff.unholy_frenzy.expires, query_time ) - last

                    local bonus = floor( window / speed )

                    return min( 6, actual + bonus )
                end
            } ]]
        },
        frostbolt = {
            id = 317792,
            duration = 4,
            max_stack = 1,
        },
        gnaw = {
            id = 91800,
            duration = 0.5,
            max_stack = 1,
        },
        grip_of_the_dead = {
            id = 273977,
            duration = 3600,
            max_stack = 1,
        },
        icebound_fortitude = {
            id = 48792,
            duration = 8,
            max_stack = 1,
        },
        lichborne = {
            id = 49039,
            duration = 10,
            max_stack = 1,
        },
        on_a_pale_horse = {
            id = 51986,
        },
        path_of_frost = {
            id = 3714,
            duration = 600,
            max_stack = 1,k
        },
        runic_corruption = {
            id = 51460,
            duration = function () return 3 * haste end,
            max_stack = 1,
        },
        soul_reaper = {
            id = 343294,
            duration = 5,
            type = "Magic",
            max_stack = 1,
        },
        sudden_doom = {
            id = 81340,
            duration = 10,
            max_stack = function () return talent.harbinger_of_doom.enabled and 2 or 1 end,
        },
        unholy_assault = {
            id = 207289,
            duration = 12,
            max_stack = 1,
        },
        unholy_blight = {
            id = 115989,
            duration = 6,
            max_stack = 1,
        },
        unholy_blight_dot = {
            id = 115994,
            duration = 14,
            tick_time = function () return 2 * haste end,
            max_stack = 4,
        },
        unholy_pact = {
            id = 319230,
            duration = 15,
            max_stack = 1,
        },
        unholy_strength = {
            id = 53365,
            duration = 15,
            max_stack = 1,
        },
        virulent_plague = {
            id = 191587,
            duration = function () return 27 * ( talent.ebon_fever.enabled and 0.5 or 1 ) end,
            tick_time = function () return 3 * ( talent.ebon_fever.enabled and 0.5 or 1 ) end,
            type = "Disease",
            max_stack = 1,
        },
        wraith_walk = {
            id = 212552,
            duration = 4,
            type = "Magic",
            max_stack = 1,
        },


        -- PvP Talents
        crypt_fever = {
            id = 288849,
            duration = 4,
            max_stack = 1,
        },

        necrotic_wound = {
            id = 223929,
            duration = 18,
            max_stack = 1,
        },


        -- Azerite Powers
        cold_hearted = {
            id = 288426,
            duration = 8,
            max_stack = 1
        },

        festermight = {
            id = 274373,
            duration = 20,
            max_stack = 99,
        },

        helchains = {
            id = 286979,
            duration = 15,
            max_stack = 1
        }
    } )


    spec:RegisterStateTable( "death_and_decay", 
        setmetatable( { onReset = function( self ) end },
        { __index = function( t, k )
            if k == "ticking" then
                return buff.death_and_decay.up

            elseif k == "remains" then
                return buff.death_and_decay.remains

            end

            return false
        end } ) )

    spec:RegisterStateTable( "defile", 
        setmetatable( { onReset = function( self ) end },
        { __index = function( t, k )
            if k == "ticking" then
                return buff.death_and_decay.up

            elseif k == "remains" then
                return buff.death_and_decay.remains

            end

            return false
        end } ) )

    spec:RegisterStateExpr( "dnd_ticking", function ()
        return death_and_decay.ticking
    end )

    spec:RegisterStateExpr( "dnd_remains", function ()
        return death_and_decay.remains
    end )


    spec:RegisterStateExpr( "spreading_wounds", function ()
        if talent.infected_claws.enabled and buff.dark_transformation.up then return false end -- Ghoul is dumping wounds for us, don't bother.
        return azerite.festermight.enabled and settings.cycle and settings.festermight_cycle and cooldown.death_and_decay.remains < 9 and active_dot.festering_wound < spell_targets.festering_strike
    end )


    spec:RegisterStateFunction( "time_to_wounds", function( x )
        if debuff.festering_wound.stack >= x then return 0 end
        return 3600
        --[[ No timeable wounds mechanic in SL?
        if buff.unholy_frenzy.down then return 3600 end

        local deficit = x - debuff.festering_wound.stack
        local swing, speed = state.swings.mainhand, state.swings.mainhand_speed

        local last = swing + ( speed * floor( query_time - swing ) / swing )
        local fw = last + ( speed * deficit ) - query_time

        if fw > buff.unholy_frenzy.remains then return 3600 end
        return fw ]]
    end )


    spec:RegisterGear( "tier19", 138355, 138361, 138364, 138349, 138352, 138358 )
    spec:RegisterGear( "tier20", 147124, 147126, 147122, 147121, 147123, 147125 )
        spec:RegisterAura( "master_of_ghouls", {
            id = 246995,
            duration = 3,
            max_stack = 1
        } )        

    spec:RegisterGear( "tier21", 152115, 152117, 152113, 152112, 152114, 152116 )
        spec:RegisterAura( "coils_of_devastation", {
            id = 253367,
            duration = 4,
            max_stack = 1
        } )

    spec:RegisterGear( "acherus_drapes", 132376 )
    spec:RegisterGear( "cold_heart", 151796 ) -- chilled_heart stacks NYI
        spec:RegisterAura( "cold_heart_item", {
            id = 235599,
            duration = 3600,
            max_stack = 20 
        } )

    spec:RegisterGear( "consorts_cold_core", 144293 )
    spec:RegisterGear( "death_march", 144280 )
    -- spec:RegisterGear( "death_screamers", 151797 )
    spec:RegisterGear( "draugr_girdle_of_the_everlasting_king", 132441 )
    spec:RegisterGear( "koltiras_newfound_will", 132366 )
    spec:RegisterGear( "lanathels_lament", 133974 )
    spec:RegisterGear( "perseverance_of_the_ebon_martyr", 132459 )
    spec:RegisterGear( "rethus_incessant_courage", 146667 )
    spec:RegisterGear( "seal_of_necrofantasia", 137223 )
    spec:RegisterGear( "shackles_of_bryndaor", 132365 ) -- NYI
    spec:RegisterGear( "soul_of_the_deathlord", 151740 )
    spec:RegisterGear( "soulflayers_corruption", 151795 )
    spec:RegisterGear( "the_instructors_fourth_lesson", 132448 )
    spec:RegisterGear( "toravons_whiteout_bindings", 132458 )
    spec:RegisterGear( "uvanimor_the_unbeautiful", 137037 )


    spec:RegisterPet( "ghoul", 26125, "raise_dead", 3600 )
    spec:RegisterTotem( "gargoyle", 458967 )
    spec:RegisterTotem( "abomination", 298667 )
    spec:RegisterPet( "apoc_ghoul", 24207, "apocalypse", 15 )
    spec:RegisterPet( "army_ghoul", 24207, "army_of_the_dead", 30 )


    spec:RegisterHook( "reset_precast", function ()
        local expires = action.summon_gargoyle.lastCast + 35
        if expires > now then
            summonPet( "gargoyle", expires - now )
        end

        local control_expires = action.control_undead.lastCast + 300
        if control_expires > now and pet.up and not pet.ghoul.up then
            summonPet( "controlled_undead", control_expires - now )
        end

        local apoc_expires = action.apocalypse.lastCast + 15
        if apoc_expires > now then
            summonPet( "apoc_ghoul", apoc_expires - now )
        end

        local army_expires = action.army_of_the_dead.lastCast + 30
        if army_expires > now then
            summonPet( "army_ghoul", army_expires - now )
        end

        if talent.all_will_serve.enabled and pet.ghoul.up then
            summonPet( "skeleton" )
        end

        rawset( cooldown, "army_of_the_dead", nil )
        rawset( cooldown, "raise_abomination", nil )

        if pvptalent.raise_abomination.enabled then
            cooldown.army_of_the_dead = cooldown.raise_abomination
        else
            cooldown.raise_abomination = cooldown.army_of_the_dead
        end

        if state:IsKnown( "deaths_due" ) and cooldown.deaths_due.remains then setCooldown( "death_and_decay", cooldown.deaths_due.remains )
        elseif talent.defile.enabled and cooldown.defile.remains then setCooldown( "death_and_decay", cooldown.defile.remains ) end
    end )


    local mt_runeforges = {
        __index = function( t, k )
            return false
        end,
    }

    -- Not actively supporting this since we just respond to the player precasting AOTD as they see fit.
    spec:RegisterStateTable( "death_knight", setmetatable( {
        disable_aotd = false,
        delay = 6,
        runeforge = setmetatable( {}, mt_runeforges )
    }, {
        __index = function( t, k )
            if k == "fwounded_targets" then return state.active_dot.festering_wound end
            return 0
        end,
    } ) )


    -- Abilities
    spec:RegisterAbilities( {
        antimagic_shell = {
            id = 48707,
            cast = 0,
            cooldown = 60,
            gcd = "off",

            toggle = "defensives",

            startsCombat = false,
            texture = 136120,

            handler = function ()
                applyBuff( "antimagic_shell" )
            end,
        },


        antimagic_zone = {
            id = 51052,
            cast = 0,
            cooldown = 120,
            gcd = "spell",
            
            toggle = "defensives",

            startsCombat = false,
            texture = 237510,
            
            handler = function ()
                applyBuff( "antimagic_zone" )
            end,
        },


        apocalypse = {
            id = 275699,
            cast = 0,
            cooldown = function () return ( essence.vision_of_perfection.enabled and 0.87 or 1 ) * ( ( pvptalent.necromancers_bargain.enabled and 45 or 90 ) - ( level > 48 and 15 or 0 ) ) end,
            gcd = "spell",

            toggle = "cooldowns",

            startsCombat = true,
            texture = 1392565,

            handler = function ()
                summonPet( "apoc_ghoul", 15 )

                if debuff.festering_wound.stack > 4 then
                    applyDebuff( "target", "festering_wound", debuff.festering_wound.remains, debuff.festering_wound.remains - 4 )
                    apply_festermight( 4 )
                    if conduit.convocation_of_the_dead.enabled and cooldown.apocalypse.remains > 0 then
                        reduceCooldown( "apocalypse", 4 * conduit.convocation_of_the_dead.mod * 0.1 )
                    end
                    gain( 12, "runic_power" )
                else                    
                    gain( 3 * debuff.festering_wound.stack, "runic_power" )
                    apply_festermight( debuff.festering_wound.stack )
                    if conduit.convocation_of_the_dead.enabled and cooldown.apocalypse.remains > 0 then
                        reduceCooldown( "apocalypse", debuff.festering_wound.stack * conduit.convocation_of_the_dead.mod * 0.1 )
                    end
                    removeDebuff( "target", "festering_wound" )
                end

                if level > 57 then gain( 2, "runes" ) end

                if pvptalent.necromancers_bargain.enabled then applyDebuff( "target", "crypt_fever" ) end
            end,

            auras = {
                frenzied_monstrosity = {
                    id = 334895,
                    duration = 15,
                    max_stack = 1,
                },
                frenzied_monstrosity_pet = {
                    id = 334896,
                    duration = 15,
                    max_stack = 1
                }
            }
        },


        army_of_the_dead = {
            id = function () return pvptalent.raise_abomination.enabled and 288853 or 42650 end,
            cast = 0,
            cooldown = 480,
            gcd = "spell",

            spend = function () return pvptalent.raise_abomination.enabled and 0 or 3 end,
            spendType = "runes",

            toggle = "cooldowns",
            -- nopvptalent = "raise_abomination",

            startsCombat = false,
            texture = function () return pvptalent.raise_abomination.enabled and 298667 or 237511 end,

            handler = function ()
                if pvptalent.raise_abomination.enabled then
                    summonPet( "abomination" )
                else
                    applyBuff( "army_of_the_dead", 4 )
                end
            end,

            copy = { 288853, 42650, "army_of_the_dead", "raise_abomination" }
        },


        asphyxiate = {
            id = 108194,
            cast = 0,
            cooldown = 45,
            gcd = "spell",

            startsCombat = true,
            texture = 538558,

            toggle = "interrupts",

            talent = "asphyxiate",

            debuff = "casting",
            readyTime = state.timeToInterrupt,            

            handler = function ()
                applyDebuff( "target", "asphyxiate" )
            end,
        },


        chains_of_ice = {
            id = 45524,
            cast = 0,
            cooldown = 0,
            gcd = "spell",

            spend = 1,
            spendType = "runes",

            startsCombat = true,
            texture = 135834,

            handler = function ()
                applyDebuff( "target", "chains_of_ice" )
                removeBuff( "cold_heart_item" )
            end,
        },


        clawing_shadows = {
            id = 207311,
            cast = 0,
            cooldown = 0,
            gcd = "spell",

            spend = 1,
            spendType = "runes",

            startsCombat = true,
            texture = 615099,

            talent = "clawing_shadows",

            handler = function ()
                if debuff.festering_wound.up then
                    if debuff.festering_wound.stack > 1 then
                        applyDebuff( "target", "festering_wound", debuff.festering_wound.remains, debuff.festering_wound.stack - 1 )
                    else removeDebuff( "target", "festering_wound" ) end
                    
                    if conduit.convocation_of_the_dead.enabled and cooldown.apocalypse.remains > 0 then
                        reduceCooldown( "apocalypse", conduit.convocation_of_the_dead.mod * 0.1 )
                    end

                    apply_festermight( 1 )
                end
                gain( 3, "runic_power" )
            end,
        },


        control_undead = {
            id = 111673,
            cast = 1.5,
            cooldown = 0,
            gcd = "spell",

            spend = 1,
            spendType = "runes",

            startsCombat = true,
            texture = 237273,

            usable = function () return target.is_undead and target.level <= level + 1 end,
            handler = function ()
                dismissPet( "ghoul" )
                summonPet( "controlled_undead", 300 )
            end,
        },


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


        dark_simulacrum = {
            id = 77606,
            cast = 0,
            cooldown = 20,
            gcd = "spell",

            spend = 0,
            spendType = "runic_power",

            startsCombat = true,
            texture = 135888,

            pvptalent = "dark_simulacrum",

            usable = function ()
                if not target.is_player then return false, "target is not a player" end
                return true
            end,
            handler = function ()
                applyDebuff( "target", "dark_simulacrum" )
            end,
        },


        dark_transformation = {
            id = 63560,
            cast = 0,
            cooldown = 60,
            gcd = "spell",

            startsCombat = false,
            texture = 342913,

            usable = function () return pet.ghoul.alive end,
            handler = function ()
                applyBuff( "dark_transformation" )
                if azerite.helchains.enabled then applyBuff( "helchains" ) end
                if talent.unholy_pact.enabled then applyBuff( "unholy_pact" ) end

                if legendary.frenzied_monstrosity.enabled then
                    applyBuff( "frenzied_monstrosity" )
                    applyBuff( "frenzied_monstrosity_pet" )
                end
            end,

            auras = {
                frenzied_monstrosity = {
                    id = 334895,
                    duration = 15,
                    max_stack = 1,
                },
                frenzied_monstrosity_pet = {
                    id = 334896,
                    duration = 15,
                    max_stack = 1
                }
            }
        },


        death_and_decay = {
            id = 43265,
            noOverride = 324128,
            cast = 0,
            cooldown = 30,
            gcd = "spell",

            spend = 1,
            spendType = "runes",

            startsCombat = true,
            texture = 136144,

            notalent = "defile",

            handler = function ()
                applyBuff( "death_and_decay", 10 )
                if talent.grip_of_the_dead.enabled then applyDebuff( "target", "grip_of_the_dead" ) end
            end,
        },


        death_coil = {
            id = 47541,
            cast = 0,
            cooldown = 0,
            gcd = "spell",

            spend = function () return buff.sudden_doom.up and 0 or ( legendary.deadliest_coil.enabled and 30 or 40 ) end,
            spendType = "runic_power",

            startsCombat = true,
            texture = 136145,

            handler = function ()
                removeStack( "sudden_doom" )
                if cooldown.dark_transformation.remains > 0 then setCooldown( "dark_transformation", max( 0, cooldown.dark_transformation.remains - 1 ) ) end
                if legendary.deadliest_coil.enabled and buff.dark_transformation.up then buff.dark_transformation.expires = buff.dark_transformation.expires + 2 end
                if legendary.deaths_certainty.enabled then
                    local spell = covenant.night_fae and "deaths_due" or ( talent.defile.enabled and "defile" or "death_and_decay" )
                    if cooldown[ spell ].remains > 0 then reduceCooldown( spell, 2 ) end
                end                
            end,
        },


        death_grip = {
            id = 49576,
            cast = 0,
            cooldown = 25,
            gcd = "spell",

            startsCombat = true,
            texture = 237532,

            handler = function ()
                applyDebuff( "target", "death_grip" )
                setDistance( 5 )
                if conduit.unending_grip.enabled then applyDebuff( "target", "unending_grip" ) end
            end,
        },


        death_pact = {
            id = 48743,
            cast = 0,
            cooldown = 120,
            gcd = "spell",

            toggle = "defensives",

            startsCombat = false,
            texture = 136146,

            talent = "death_pact",

            handler = function ()
                gain( health.max * 0.5, "health" )
                applyDebuff( "player", "death_pact" )
            end,
        },


        death_strike = {
            id = 49998,
            cast = 0,
            cooldown = 0,
            gcd = "spell",

            spend = function () return buff.dark_succor.up and 0 or ( ( buff.transfusion.up and 0.5 or 1 ) * 35 ) end,
            spendType = "runic_power",

            startsCombat = true,
            texture = 237517,

            handler = function ()
                removeBuff( "dark_succor" )

                if legendary.deaths_certainty.enabled then
                    local spell = conduit.night_fae and "deaths_due" or ( talent.defile.enabled and "defile" or "death_and_decay" )
                    if cooldown[ spell ].remains > 0 then reduceCooldown( spell, 2 ) end
                end                
            end,
        },


        deaths_advance = {
            id = 48265,
            cast = 0,
            cooldown = 45,
            gcd = "spell",

            startsCombat = false,
            texture = 237561,

            handler = function ()
                applyBuff( "deaths_advance" )
                if conduit.fleeting_wind.enabled then applyBuff( "fleeting_wind" ) end
            end,
        },


        defile = {
            id = 152280,
            cast = 0,
            cooldown = 20,
            gcd = "spell",

            spend = 1,
            spendType = "runes",

            talent = "defile",

            startsCombat = true,
            texture = 1029008,

            handler = function ()
                applyBuff( "death_and_decay" )
                setCooldown( "death_and_decay", 20 )

                applyDebuff( "target", "defile", 1 )
            end,
        },


        epidemic = {
            id = 207317,
            cast = 0,
            cooldown = 0,
            gcd = "spell",

            spend = function () return buff.sudden_doom.up and 0 or 30 end,
            spendType = "runic_power",

            startsCombat = true,
            texture = 136066,

            targets = {
                count = function () return active_dot.virulent_plague end,
            },

            usable = function () return active_dot.virulent_plague > 0 end,
            handler = function ()
                removeBuff( "sudden_doom" )
            end,
        },


        festering_strike = {
            id = 85948,
            cast = 0,
            cooldown = 0,
            gcd = "spell",

            spend = 2,
            spendType = "runes",

            startsCombat = true,
            texture = 879926,

            cycle = function ()
                if settings.cycle and azerite.festermight.enabled and settings.festermight_cycle and dot.festering_wound.stack >= 2 and active_dot.festering_wound < spell_targets.festering_strike then return "festering_wound" end
            end,
            min_ttd = function () return min( cooldown.death_and_decay.remains + 3, 8 ) end, -- don't try to cycle onto targets that will die too fast to get consumed.

            handler = function ()
                applyDebuff( "target", "festering_wound", nil, debuff.festering_wound.stack + 2 )
            end,
        },


        icebound_fortitude = {
            id = 48792,
            cast = 0,
            cooldown = function () return 180 - ( azerite.cold_hearted.enabled and 15 or 0 ) + ( conduit.chilled_resilience.mod * 0.001 ) end,
            gcd = "spell",

            toggle = "defensives",

            startsCombat = false,
            texture = 237525,

            handler = function ()
                applyBuff( "icebound_fortitude" )
                if azerite.cold_hearted.enabled then applyBuff( "cold_hearted" ) end
            end,
        },


        lichborne = {
            id = 49039,
            cast = 0,
            cooldown = 60,
            gcd = "off",

            toggle = "defensives",

            startsCombat = false,
            texture = 136187,

            handler = function ()
                applyBuff( "lichborne" )
                if conduit.hardened_bones.enabled then applyBuff( "hardened_bones" ) end
            end,
        },


        mind_freeze = {
            id = 47528,
            cast = 0,
            cooldown = 15,
            gcd = "spell",

            spend = 0,
            spendType = "runic_power",

            startsCombat = true,
            texture = 237527,

            toggle = "interrupts",

            debuff = "casting",
            readyTime = state.timeToInterrupt,

            handler = function ()
                if conduit.spirit_drain.enabled then gain( conduit.spirit_drain.mod * 0.1, "runic_power" ) end
                interrupt()
            end,
        },


        necrotic_strike = {
            id = 223829,
            cast = 0,
            cooldown = 0,
            gcd = "spell",

            spend = 1,
            spendType = "runes",

            startsCombat = true,
            texture = 132481,

            pvptalent = function ()
                if essence.conflict_and_strife.major then return end
                return "necrotic_strike"
            end,
            debuff = "festering_wound",

            handler = function ()
                if debuff.festering_wound.up then
                    if debuff.festering_wound.stack == 1 then removeDebuff( "target", "festering_wound" )
                    else applyDebuff( "target", "festering_wound", debuff.festering_wound.remains, debuff.festering_wound.stack - 1 ) end

                    if conduit.convocation_of_the_dead.enabled and cooldown.apocalypse.remains > 0 then
                        reduceCooldown( "apocalypse", conduit.convocation_of_the_dead.mod * 0.1 )
                    end

                    applyDebuff( "target", "necrotic_wound" )
                end
            end,
        },


        outbreak = {
            id = 77575,
            cast = 0,
            cooldown = 0,
            gcd = "spell",

            spend = 1,
            spendType = "runes",

            startsCombat = true,
            texture = 348565,

            cycle = "virulent_plague",

            handler = function ()
                applyDebuff( "target", "virulent_plague" )
                active_dot.virulent_plague = active_enemies
            end,
        },


        path_of_frost = {
            id = 3714,
            cast = 0,
            cooldown = 0,
            gcd = "spell",

            spend = 1,
            spendType = "runes",

            startsCombat = false,
            texture = 237528,

            handler = function ()
                applyBuff( "path_of_frost" )
            end,
        },


        --[[ raise_ally = {
            id = 61999,
            cast = 0,
            cooldown = 600,
            gcd = "spell",

            spend = 30,
            spendType = "runic_power",

            startsCombat = false,
            texture = 136143,

            handler = function ()
            end,
        }, ]]


        raise_dead = {
            id = 46584,
            cast = 0,
            cooldown = 30,
            gcd = "spell",

            startsCombat = false,
            texture = 1100170,

            essential = true, -- new flag, will allow recasting even in precombat APL.
            nomounted = true,

            usable = function () return not pet.alive end,
            handler = function ()
                summonPet( "ghoul", 3600 )
                if talent.all_will_serve.enabled then summonPet( "skeleton", 3600 ) end
            end,
        },


        sacrificial_pact = {
            id = 327574,
            cast = 0,
            cooldown = 120,
            gcd = "spell",
            
            spend = 20,
            spendType = "runic_power",
            
            toggle = "cooldowns",

            startsCombat = true,
            texture = 136133,
            
            usable = function () return pet.alive, "requires an undead pet" end,

            handler = function ()
                dismissPet( "ghoul" )
                gain( 0.25 * health.max, "health" )
            end,
        },


        scourge_strike = {
            id = 55090,
            cast = 0,
            cooldown = 0,
            gcd = "spell",

            spend = 1,
            spendType = "runes",

            startsCombat = true,
            texture = 237530,

            notalent = "clawing_shadows",

            handler = function ()
                gain( 3, "runic_power" )
                if debuff.festering_wound.stack > 1 then
                    applyDebuff( "target", "festering_wound", debuff.festering_wound.remains, debuff.festering_wound.stack - 1 )
                else removeDebuff( "target", "festering_wound" ) end
                apply_festermight( 1 )

                if conduit.lingering_plague.enabled and debuff.virulent_plague.up then
                    debuff.virulent_plague.expires = debuff.virulent_plague.expires + ( conduit.lingering_plague.mod * 0.001 )
                end
            end,
        },


        soul_reaper = {
            id = 343294,
            cast = 0,
            cooldown = 6,
            gcd = "spell",

            spend = 1,
            spendType = "runes",

            startsCombat = true,
            texture = 636333,

            talent = "soul_reaper",

            handler = function ()
                applyDebuff( "target", "soul_reaper" )
            end,
        },


        summon_gargoyle = {
            id = 49206,
            cast = 0,
            cooldown = 180,
            gcd = "spell",

            toggle = "cooldowns",

            startsCombat = true,
            texture = 458967,

            talent = "summon_gargoyle",

            handler = function ()
                summonPet( "gargoyle", 30 )
            end,
        },


        transfusion = {
            id = 288977,
            cast = 0,
            cooldown = 45,
            gcd = "spell",

            spend = -20,
            spendType = "runic_power",

            startsCombat = false,
            texture = 237515,

            pvptalent = "transfusion",

            handler = function ()
                applyBuff( "transfusion" )
            end,
        },


        unholy_assault = {
            id = 207289,
            cast = 0,
            cooldown = 75,
            gcd = "spell",
            
            toggle = "cooldowns",

            startsCombat = true,
            texture = 136224,

            talent = "unholy_assault",
            
            handler = function ()
                applyDebuff( "target", "festering_wound", nil, min( 6, debuff.festering_wound.stack + 4 ) )
                applyBuff( "unholy_frenzy" )
                stat.haste = stat.haste + 0.1
            end,
        },


        unholy_blight = {
            id = 115989,
            cast = 0,
            cooldown = 45,
            gcd = "spell",

            spend = 1,
            spendType = "runes",

            startsCombat = true,
            texture = 136132,

            talent = "unholy_blight",

            handler = function ()
                applyBuff( "unholy_blight" )
                applyDebuff( "unholy_blight_dot" )
            end,
        },


        wraith_walk = {
            id = 212552,
            cast = 4,
            channeled = true,
            cooldown = 60,
            gcd = "spell",

            startsCombat = false,
            texture = 1100041,

            talent = "wraith_walk",

            start = function ()
                applyBuff( "wraith_walk" )
            end,
        },
    } )


    spec:RegisterOptions( {
        enabled = true,

        aoe = 2,

        nameplates = true,
        nameplateRange = 8,

        damage = true,
        damageExpiration = 8,

        cycle = true,

        potion = "potion_of_unbridled_fury",

        package = "Unholy",
    } )


    spec:RegisterSetting( "festermight_cycle", false, {
        name = "Festermight: Spread |T237530:0|t Wounds",
        desc = function ()
            return  "If checked, the addon will encourage you to spread Festering Wounds to multiple targets before |T136144:0|t Death and Decay.\n\n" ..
                    "Requires |cFF" .. ( state.azerite.festermight.enabled and "00FF00" or "FF0000" ) .. "Festermight|r (Azerite)\n" .. 
                    "Requires |cFF" .. ( state.settings.cycle and "00FF00" or "FF0000" ) .. "Recommend Target Swaps|r in |cFFFFD100Targeting|r section."
        end,
        type = "toggle",
        width = "full"
    } )  


    spec:RegisterPack( "Unholy", 20201028, [[dGKfCbqiHOhba1MekJsOYPes9kHQMfb6wauyxu6xkrgga5yufTma0ZaOAAqexdI02aG8naaJda05esOwNqcP5rvY9GW(OkCqaGSqLOEOqIYebOiUiafPncqrDsHevwjb8sHeGBkKGStQs9tHevnuHeulfaOEkOMQq4QcjeBvib0Ej6VOmybhM0IvspgXKPYLvTzL6ZGmAaDAPwnaLEne1SP42eA3s(TOHtvDCHez5q9CKMUIRdPTRe(obnEHeOZdK1lK08bQ9JQLEkJqc705sVbiGaiG8eqaeaA9eaaPEciaaj8aY)syFLGScDjCPIxchfPaMgqsyFfKjvNmcjmnrXKlHboJpnk6slb1dq0vljfxI2IOgD6SiyDplrBrYss4v02mr5k5Qe2PZLEdqabqa5jGaia06jaasbesrQeM6FI0BaIuakHb2o3l5Qe2DkrcdG5HOifW0aIham56aKhIcOAiGdxaampeLNm56X8aabGcYdaeqaeqCb4caG5HOmGAbDAuuUaayEaWGhaa5C3XdrH6YXdaMX)r9wUaayEaWGhIYYAXXZD8WOyOpSEZdKSC90zr5Hj5b8HqnkMhiz56PZIA5caG5badEaaSsA1qxcWCwdpKBEikCk8yEyeEfzQLlaaMham4b4e1WdaGV6FSG8aai)KOgq(0ZdJWRitTsytthQmcj8P0xKtLri92tzes4x6Q5o5YsycUNJBvcJrRBNw8SjzEYdEWdqehpeJhWOvty(PWJ5bV4bKaijSsMoljS4ftmiwUzgus7yo8vrQCKEdqzes4x6Q5o5YsycUNJBvc7UoazA5yUtuq2Pji3fepagmp4)XQ(jHbbmrnwLm9IZdX4bLm9IZEDX(uEabp4PewjtNLeE1KPJLB2a8SxxeKCKEd4YiKWV0vZDYLLWeCph3QeooEGKPXLclR6Ne1aYNEl(IAxuEWlEaaXdX4bsMgxkSSkweel3Sb4zURol(IAxuEWdEGKPXLclljl3l6DmtV)oXKBXxu7IYdrZdGbZdKmnUuyzvSiiwUzdWZCxDw8f1UO8Gx8aaLWkz6SKWqOk21AXYntJ6X5auosVrImcj8lD1CNCzjmb3ZXTkHxr3Bl(eKnNsz7etUf1NhadMhwr3Bl(eKnNsz7etoJKO1CSLokbzEWlEWtpLWkz6SKWdWZqR1eTCSDIjxosVrQmcj8lD1CNCzjmb3ZXTkHJKhCxhGmTCm3jki70eK7cscRKPZscVtck9oMg1J75S1RIYr6nasgHe(LUAUtUSeMG754wLWUCSKSiVgSo3X2gv8SvuCzXxu7IYdi4bajHvY0zjHjzrEnyDUJTnQ4LJ0Baazes4x6Q5o5YsycUNJBvchjp4UoazA5yUtuq2Pji3fKewjtNLe2hf3BqDbXwnkDKJ0BaOmcj8lD1CNCzjmb3ZXTkHh18ASkweel3Sb4zovSUZ(sxn3XdX4HtPVi3UOPDwSCZ8pEFY0zzf7kX8qmEyfDVTOfW0aIrh8lObOf1NhadMhoL(IC7IM2zXYnZ)49jtNLvSReZdX4b)pw1pjmiGjQXQKPxCEamyEyuZRXQyrqSCZgGN5uX6o7lD1ChpeJh8)yv)KWGaMOgRsMEX5Hy8ajtJlfwwflcILB2a8m3vNfFrTlkp4bpaGaepagmpmQ51yvSiiwUzdWZCQyDN9LUAUJhIXd(FSkweedcyIASkz6fxcRKPZsclmXg3I3fdFAwArUCKEhflJqc)sxn3jxwctW9CCRs4i5b31bitlhZDIcYonb5UG4Hy8Wk6EBrlGPbeJo4xqdqlQppeJhIKhoL(IC7IM2zXYnZ)49jtNLvSReZdX4Hi5HrnVgRIfbXYnBaEMtfR7SV0vZD8ayW8WOyOp2PfpBsMRpp4fpqY04sHLv9tIAa5tVfFrTlQewjtNLewyInUfVlg(0S0IC5i92tajJqc)sxn3jxwctW9CCRs4i5b31bitlhZDIcYonb5UGKWkz6SKW4233CwxmQVsUCKE7PNYiKWV0vZDYLLWeCph3QeosEyfDVT(TXOywUzBCshlQppeJhIKhwr3B7k(6aKLBgTlhwHsQAr95Hy8qC8WOyOpwGxndqMpz4bpqWdaqaXdGbZdJIH(ybE1maz(KHh8cbpaqaXdGbZd7gc4WWxu7IYdEXdibP8q0syLmDwsy8v)UGyBJkEQCKJe29TIAgzesV9ugHewjtNLewSlhBJ)J6LWV0vZDYLLJ0BakJqc)sxn3jxwcN(sy6hjSsMolj8cf36Q5s4fQb9sysMgxkSSuurXSyqkgkbzUfFrTlkp4fpGuEigpmQ51yPOIIzXGumucYC7lD1CNeEHIzLkEjSFMMUGy7eZGumucYC5i9gWLriHFPRM7KllHj4EoUvjmgTAcZpfES19Dt6Hh8GhaqiLhIXdXXd(FSqkgkbzUvjtV48ayW8qK8WOMxJLIkkMfdsXqjiZTV0vZD8q08qmEaJw36(Uj9WdEGGhqQewjtNLewXeToBsm(1ihP3irgHe(LUAUtUSeMG754wLW(FSqkgkbzUvjtV48ayW8qK8WOMxJLIkkMfdsXqjiZTV0vZDsyLmDws4vtMo2gfdsosVrQmcj8lD1CNCzjmb3ZXTkHxr3BlAbmnGykLQOMXI6ZdGbZd(FSqkgkbzUvjtV48ayW8qC8WOMxJvXIGy5MnapZPI1D2x6Q5oEigp4)XQ(jHbbmrnwLm9IZdrlHvY0zjHxpMEmYDbjhP3aizes4x6Q5o5YsycUNJBvchhpSIU3w0cyAaXOd(f0a0I6ZdX4Hv092UpDowSHaow8f1UO8Gxi4bKYdrZdGbZdkz6fN96I9P8Ghi4baYdX4H44Hv092IwatdigDWVGgGwuFEamyEyfDVT7tNJfBiGJfFrTlkp4fcEaP8q0syLmDwsytdbCOmalQds81ihP3aaYiKWV0vZDYLLWeCph3QeooEW)JfsXqjiZTkz6fNhIXdJAEnwkQOywmifdLGm3(sxn3XdrZdGbZd(FSQFsyqatuJvjtV4syLmDwsyTiNoy1WiQXihP3aqzes4x6Q5o5YsycUNJBvcRKPxC2Rl2NYdEGGhaipagmpehpGrRBDF3KE4bpqWdiLhIXdy0Qjm)u4Xw33nPhEWde8aacq8q0syLmDwsyft06mFud9Yr6DuSmcj8lD1CNCzjmb3ZXTkHJJh8)yHumucYCRsMEX5Hy8WOMxJLIkkMfdsXqjiZTV0vZD8q08ayW8G)hR6NegeWe1yvY0lUewjtNLeE34VAY0jhP3Ecizes4x6Q5o5YsycUNJBvcVIU3w0cyAaXOd(f0a0I6ZdX4bLm9IZEDX(uEabp4jpagmpSIU329PZXIneWXIVO2fLh8IhGioEigpOKPxC2Rl2NYdi4bpLWkz6SKWRkel3Sb3eKPYr6TNEkJqc)sxn3jxwctW9CCRs4Pfpp4bpaqaXdGbZdrYdpkH2((3zXQOFxqmv030dQ7mOgsxKMH9cQRZdGbZdrYdpkH2((3zx00olwUzUl20lHvY0zjHrPN1ZfPYr6TNaugHe(LUAUtUSewjtNLewJkfOIvkBN1WYnZpfESeMG754wLWXXdNsFrUDrt7Sy5M5F8(KPZY(sxn3XdX4Hi5HrnVglAbmnGykLQOMX(sxn3XdrZdGbZdXXdrYdNsFrULKL7f9oMP3FNyYTIkGnX8qmEisE4u6lYTlAANfl3m)J3NmDw2x6Q5oEiAjCPIxcRrLcuXkLTZAy5M5NcpwosV9eWLriHFPRM7KllHvY0zjH1OsbQyLY2znSCZ8tHhlHj4EoUvjmjtJlfww1pjQbKp9w8f1UO8Gx8GNiHhIXdXXdNsFrULKL7f9oMP3FNyYTIkGnX8ayW8WP0xKBx00olwUz(hVpz6SSV0vZD8qmEyuZRXIwatdiMsPkQzSV0vZD8q0s4sfVewJkfOIvkBN1WYnZpfESCKE7jsKriHFPRM7KllHvY0zjH1OsbQyLY2znSCZ8tHhlHj4EoUvj8UHaom8f1UO8Gx8ajtJlfww1pjQbKp9w8f1UO8q88aGJejCPIxcRrLcuXkLTZAy5M5NcpwosV9ePYiKWV0vZDYLLWkz6SKWkf4cToLH1OMygjXQrctW9CCRsy3xr3BlwJAIzKeRgM7RO7TLokbzEWlEWtjCPIxcRuGl06ugwJAIzKeRg5i92taKmcj8lD1CNCzjSsMoljSsbUqRtzynQjMrsSAKWeCph3Qe2)JfcvXUwlwUzAupohGwLm9IZdX4b)pw1pjmiGjQXQKPxCjCPIxcRuGl06ugwJAIzKeRg5i92taazes4x6Q5o5YsyLmDwsyLcCHwNYWAutmJKy1iHj4EoUvjmjtJlfww1pjQbKp9w8vhiEigpehpCk9f5wswUx07yME)DIj3kQa2eZdX4HDdbCy4lQDr5bV4bsMgxkSSKSCVO3Xm9(7etUfFrTlkpeppaqaXdGbZdrYdNsFrULKL7f9oMP3FNyYTIkGnX8q0s4sfVewPaxO1PmSg1eZijwnYr6TNaqzes4x6Q5o5YsyLmDwsyLcCHwNYWAutmJKy1iHj4EoUvj8UHaom8f1UO8Gx8ajtJlfww1pjQbKp9w8f1UO8q88aabKeUuXlHvkWfADkdRrnXmsIvJCKE7zuSmcj8lD1CNCzjSsMolj8IM2zXYnZDXMEjmb3ZXTkHJJhizACPWYQ(jrnG8P3IV6aXdX4b3xr3B7(054UGyct0YzPJsqMh8abpGeEigpCk9f52fnTZILBM)X7tMol7lD1ChpenpagmpSIU3w0cyAaXukvrnJf1NhadMh8)yHumucYCRsMEXLWLkEj8IM2zXYnZDXME5i9gGasgHe(LUAUtUSewjtNLegRI(DbXurFtpOUZGAiDrAg2lOUUeMG754wLWKmnUuyzv)KOgq(0BXxu7IYdEXdaKhadMhg18ASkweel3Sb4zovSUZ(sxn3XdGbZdyTDSV41yvNJA7Ih8IhqQeUuXlHXQOFxqmv030dQ7mOgsxKMH9cQRlhP3a0tzes4x6Q5o5YsyLmDws4vqqzD26ptnIAPejmb3ZXTkHjzACPWYsrffZIbPyOeK5w8f1UO8Gh8aacq8ayW8qK8WOMxJLIkkMfdsXqjiZTV0vZD8qmEyAXZdEWdaeq8ayW8qK8WJsOTV)DwSk63fetf9n9G6odQH0fPzyVG66s4sfVeEfeuwNT(ZuJOwkrosVbiaLriHFPRM7KllHvY0zjHbSNYaMcnhlHj4EoUvjS)hlKIHsqMBvY0lopagmpejpmQ51yPOIIzXGumucYC7lD1ChpeJhMw88Gh8aabepagmpejp8OeA77FNfRI(DbXurFtpOUZGAiDrAg2lOUUeUuXlHbSNYaMcnhlhP3aeWLriHFPRM7KllHvY0zjHHuZjQXCmLTEfzjmb3ZXTkH9)yHumucYCRsMEX5bWG5Hi5HrnVglfvumlgKIHsqMBFPRM74Hy8W0INh8GhaiG4bWG5Hi5HhLqBF)7Syv0VliMk6B6b1DgudPlsZWEb11LWLkEjmKAornMJPS1RilhP3aejYiKWV0vZDYLLWkz6SKWq4SGOmFClQggwHUeMG754wLWy068Gxi4baNhIXdXXdtlEEWdEaGaIhadMhIKhEucT99VZIvr)UGyQOVPhu3zqnKUind7fuxNhIwcxQ4LWq4SGOmFClQggwHUCKEdqKkJqc)sxn3jxwctW9CCRsysMgxkSSkweel3Sb4zURol(Qdepagmp4)XcPyOeK5wLm9IZdGbZdRO7TfTaMgqmLsvuZyr9LWkz6SKW(50zjhP3aeajJqc)sxn3jxwctW9CCRsyxo2fng18Ay(gfc9w8f1UO8Gxi4biItcRKPZscNOZk(kYYr6nabaKriHFPRM7KllHvY0zjHjQXWuY0zXmnDKWMMoSsfVe(u6lYPYr6nabGYiKWV0vZDYLLWkz6SKWe1yykz6SyMMosytthwPIxctY04sHfvosVbyuSmcj8lD1CNCzjmb3ZXTkHvY0lo71f7t5bpqWdaucthCtgP3EkHvY0zjHjQXWuY0zXmnDKWMMoSsfVewZlhP3aoGKriHFPRM7KllHj4EoUvjSsMEXzVUyFkpGGh8ucthCtgP3EkHvY0zjHjQXWuY0zXmnDKWMMoSsfVeg61XnrosVbCpLriHFPRM7KllHvY0zjH3Noh3feJo4g5lHj4EoUvjS7RO7TDF6CCxqmHjA5S0rjiZdEXdirctarmNnkg6dv6TNYrosyF8jP4QoYiKE7PmcjSsMoljmwB6zURoj8lD1CNCz5i9gGYiKWV0vZDYLLWLkEjSgvkqfRu2oRHLBMFk8yjSsMoljSgvkqfRu2oRHLBMFk8y5i9gWLriHFPRM7KllHD3OGKWaucRKPZscRyrqSCZgGN5U6KJCKWKmnUuyrLri92tzesyLmDwsyflcILB2a8m3vNe(LUAUtUSCKEdqzes4x6Q5o5YsycUNJBvc7(k6EB3Noh3fetyIwolDucY8Ghi4bKWdX4H44bLm9IZEDX(uEWde8aa5bWG5Hi5HtPVi3UOPDwSCZ8pEFY0zzFPRM74bWG5Hi5bnQh3ZTIkekLLB2a8m3vN9LUAUJhadMhoL(IC7IM2zXYnZ)49jtNL9LUAUJhIXdXXdJAEnw0cyAaXukvrnJ9LUAUJhIXdKmnUuyzrlGPbetPuf1mw8f1UO8Gxi4baNhadMhIKhg18ASOfW0aIPuQIAg7lD1ChpenpeTewjtNLew9tIAa5tVCKEd4YiKWV0vZDYLLWeCph3QeosEaRTJ9fVgR6Cu7Jc20HYdGbZdyTDSV41yvNJA7Ih8Gh8ePsyLmDwsyNIrMnyTO7elQtNLCKEJezes4x6Q5o5YsycUNJBvcJrRMW8tHhBDF3KE4bV4bprIewjtNLeMIkkMfdsXqjiZLJ0BKkJqc)sxn3jxwctW9CCRs4tPVi3UOPDwSCZ8pEFY0zzFPRM74Hy8G)hR6NegeWe1yvY0lopagmp4(k6EB3Noh3fetyIwolDucY8Gx8as4Hy8qK8WP0xKBx00olwUz(hVpz6SSV0vZD8qmEioEisEqJ6X9CROcHsz5MnapZD1zFPRM74bWG5bnQh3ZTIkekLLB2a8m3vN9LUAUJhIXd(FSQFsyqatuJvjtV48q0syLmDwsy0cyAaXukvrnJCKEdGKriHFPRM7KllHj4EoUvjSsMEXzVUyFkp4bcEaG8qmEioEioEGKPXLclR76aKPLJ5orbzXxu7IYdEHGhGioEigpejpmQ51yDF3MBFPRM74HO5bWG5H44bsMgxkSSUVBZT4lQDr5bVqWdqehpeJhg18ASUVBZTV0vZD8q08q0syLmDwsy0cyAaXukvrnJCKEdaiJqc)sxn3jxwctW9CCRs4rXqFStlE2KmxFEWdEWtKiHvY0zjHPavcYMZgGNHwct8aeKCKEdaLriHFPRM7KllHj4EoUvjSsMEXzVUyFkp4bpaqjSsMoljSUMIDPtNfZ0IRYr6DuSmcj8lD1CNCzjmb3ZXTkHvY0lo71f7t5bp4bakHvY0zjHPcvSyxqmXMoYr6TNasgHe(LUAUtUSewjtNLeMMOgg(Q)XsycUNJBvcpkg6JDAXZMK56ZdEXdaqEigpmkg6JDAXZMK56ZdEWdirctarmNnkg6dv6TNYr6TNEkJqc)sxn3jxwctW9CCRs4rXqFStlE2KmFYWaCKWdEXdiLhIXdy068Gxi4H44bp5badEyfDVTOfW0aIPuQIAglQppeTewjtNLeMMOgg(Q)XYr6TNaugHewjtNLegTaMgqSvtdbCKWV0vZDYLLJCKWqVoUjYiKE7Pmcj8lD1CNCzjmb3ZXTkHxr3Blf15EXCzkAXxjdpeJhWO1TtlE2KmKWdEWdqehpeJhIKhwO4wxn36NPPli2oXmifdLGmNhadMh8)yHumucYCRsMEXLWkz6SKWURdqgjBJCKEdqzes4x6Q5o5YsycUNJBvcJrRMW8tHhBDF3KE4bV4bprcpeJhWO1TtlE2KmKWdEWdqehpeJhIKhwO4wxn36NPPli2oXmifdLGmxcRKPZsc7UoazKSnYr6nGlJqc)sxn3jxwctW9CCRsy3xr3B7(054UGyct0Yzr95Hy8qC8ajtJlfww1pjQbKp9w8f1UO8Gh8as5bWG5HrnVglAbmnGykLQOMX(sxn3XdX4bsMgxkSSOfW0aIPuQIAgl(IAxuEWdEaaYdGbZdUVIU329PZXDbXeMOLZshLGmp4bpGeEiAjSsMoljmLKOyOZOdUr(Yr6nsKriHFPRM7KllHj4EoUvjS7RO7TDF6CCxqmHjA5SO(8qmEioEGKPXLclR6Ne1aYNEl(IAxuEWdEaP8ayW8WOMxJfTaMgqmLsvuZyFPRM74Hy8ajtJlfww0cyAaXukvrnJfFrTlkp4bpaa5bWG5b3xr3B7(054UGyct0YzPJsqMh8GhqcpeTewjtNLeMyuHDbXOavxkKkhP3ivgHe(LUAUtUSeMG754wLWy0Qjm)u4Xw33nPhEWlEaGaIhIXdrYdluCRRMB9Z00feBNygKIHsqMlHvY0zjHDxhGms2g5i9gajJqc)sxn3jxwctW9CCRsy3xr3B7(054UGyct0YzPJsqMh8IhqcpeJhizACPWYQ(jrnG8P3IVO2fLh8IhaCEamyEW9v092UpDoUliMWeTCw6OeK5bV4bpLWkz6SKW7tNJ7cIrhCJ8LJ0Baazes4x6Q5o5YsycUNJBvchjpSqXTUAU1pttxqSDIzqkgkbzUewjtNLe2DDaYizBKJCKWAEzesV9ugHe(LUAUtUSeMG754wLWKmnUuyzv)KOgq(0BXxu7IYdX4bLm9IZC5y3Noh3fetyIwoEWdEaqsyLmDwsy31bitlhZDIcsosVbOmcj8lD1CNCzjmb3ZXTkHjzACPWYQ(jrnG8P3IVO2fLhIXdkz6fN5YXUpDoUliMWeTC8Gh8aGKWkz6SKWUVBZLJ0BaxgHe(LUAUtUSeMG754wLWKmnUuyzv)KOgq(0BXxu7IYdX4bLm9IZC5y3Noh3fetyIwoEWdEaqsyLmDwsy31biL5qVCKEJezes4x6Q5o5YsycUNJBvc7UoazA5yUtuq2Pji3fepeJhWOvty(PWJTUVBsp8Gx8GNiHhIXdrYdJAEn2vumD6cIrt8P2x6Q5oEigpejpSqXTUAU1pttxqSDIzqkgkbzUewjtNLe((T7InrosVrQmcj8lD1CNCzjmb3ZXTkHDxhGmTCm3jki70eK7cIhIXdXXdrYdURdqgYvdbCSBHjA5UJnkg6dLhIXdJAEn2vumD6cIrt8P2x6Q5oEiAEigpejpSqXTUAU1pttxqSDIzqkgkbzUewjtNLe((T7InrosVbqYiKWV0vZDYLLWeCph3Qe2DDaY0YXCNOGSttqUliEigpqY04sHLv9tIAa5tVfFrTlQewjtNLeMssum0z0b3iF5i9gaqgHe(LUAUtUSeMG754wLWURdqMwoM7efKDAcYDbXdX4bsMgxkSSQFsudiF6T4lQDrLWkz6SKWeJkSligfO6sHu5i9gakJqc)sxn3jxwctW9CCRs4i5HfkU1vZT(zA6cITtmdsXqjiZLWkz6SKW3VDxSjYr6DuSmcj8lD1CNCzjSsMolj8(054UGy0b3iFjmb3ZXTkHJJhIJhIJhIJhCFfDVT7tNJ7cIjmrlNLokbzEWlEaj8qmEisEyfDVTOfW0aIPuQIAglQppenpagmp4(k6EB3Noh3fetyIwolDucY8Gx8aGZdrZdX4bsMgxkSSQFsudiF6T4lQDr5bV4baNhIMhadMhCFfDVT7tNJ7cIjmrlNLokbzEWlEWtEiAEigpehpqY04sHLvXIGy5MnapZD1zXxu7IYdEWdiLhIwctarmNnkg6dv6TNYr6TNasgHe(LUAUtUSeMG754wLWRO7TLI6CVyUmfT4RKHhIXdy062PfpBsgs4bp4biItcRKPZsc7UoazKSnYr6TNEkJqc)sxn3jxwctW9CCRs4v092srDUxmxMIw8vYWdX4Hi5HfkU1vZT(zA6cITtmdsXqjiZ5bWG5b)pwifdLGm3QKPxCjSsMoljS76aKrY2ihP3Ecqzes4x6Q5o5YsycUNJBvcJrRMW8tHhBDF3KE4bV4bprcpeJhIJhizACPWYQ(jrnG8P3IVO2fLh8Ghqkpagmp4(k6EB3Noh3fetyIwolDucY8Gh8as4HO5Hy8qK8Wcf36Q5w)mnDbX2jMbPyOeK5syLmDwsy31biJKTrosV9eWLriHFPRM7KllHvY0zjHPKefdDgDWnYxctW9CCRs444H44bsMgxkSSkweel3Sb4zURol(IAxuEWdEaP8ayW8G76aKHC1qahRRP6Q5mnhhpenpeJhIJhizACPWYQ(jrnG8P3IVO2fLh8GhqkpeJhCFfDVT7tNJ7cIjmrlNLokbzEWdEaq8ayW8G7RO7TDF6CCxqmHjA5S0rjiZdEWdiHhIMhIXdXXd7gc4WWxu7IYdEXdKmnUuyzDxhGmTCm3jkil(IAxuEiEEWtaXdGbZd7gc4WWxu7IYdEWdKmnUuyzv)KOgq(0BXxu7IYdrZdrlHjGiMZgfd9Hk92t5i92tKiJqc)sxn3jxwcRKPZsctmQWUGyuGQlfsLWeCph3QeooEioEGKPXLclRIfbXYnBaEM7QZIVO2fLh8Ghqkpagmp4UoazixneWX6AQUAotZXXdrZdX4H44bsMgxkSSQFsudiF6T4lQDr5bp4bKYdX4b3xr3B7(054UGyct0YzPJsqMh8Ghaepagmp4(k6EB3Noh3fetyIwolDucY8Gh8as4HO5Hy8qC8WUHaom8f1UO8Gx8ajtJlfww31bitlhZDIcYIVO2fLhINh8eq8ayW8WUHaom8f1UO8Gh8ajtJlfww1pjQbKp9w8f1UO8q08q0syciI5SrXqFOsV9uosV9ePYiKWV0vZDYLLWeCph3QegJwnH5Ncp26(Uj9WdEXdaeq8qmEisEyHIBD1CRFMMUGy7eZGumucYCjSsMoljS76aKrY2ihP3EcGKriHFPRM7KllHj4EoUvjCC8qC8qC8qC8G7RO7TDF6CCxqmHjA5S0rjiZdEXdiHhIXdrYdRO7TfTaMgqmLsvuZyr95HO5bWG5b3xr3B7(054UGyct0YzPJsqMh8IhaCEiAEigpqY04sHLv9tIAa5tVfFrTlkp4fpa48q08ayW8G7RO7TDF6CCxqmHjA5S0rjiZdEXdEYdrZdX4H44bsMgxkSSkweel3Sb4zURol(IAxuEWdEaP8ayW8G76aKHC1qahRRP6Q5mnhhpeTewjtNLeEF6CCxqm6GBKVCKE7jaGmcj8lD1CNCzjmb3ZXTkHDxhGmTCm3jki70eK7cscRKPZsctjjkg6m6GBKVCKE7jaugHe(LUAUtUSeMG754wLWrYdluCRRMB9Z00feBNygKIHsqMlHvY0zjHDxhGms2g5ih5iHxCmTZs6nabeabKNaYtKA9ucluXvxqujCuor)ep3XdaiEqjtNfpyA6qTCbKWk6amXsy4we1OtNvugw3Je2hN72CjmaMhIIuatdiEaWKRdqEikGQHaoCbaW8quEYKRhZdaeakipaqabqaXfGlaaMhIYaQf0Prr5caG5badEaaKZDhpefQlhpayg)h1B5caG5badEiklRfhp3XdJIH(W6npqYY1tNfLhMKhWhc1OyEGKLRNolQLlaaMham4baWkPvdDjaZzn8qU5HOWPWJ5Hr4vKPwUaayEaWGhGtudpaa(Q)XcYdaG8tIAa5tppmcVIm1YfGlGsMolQ1hFskUQt8iwcRn9m3vhxaLmDwuRp(KuCvN4rSek9SEUOGLkEeAuPavSsz7SgwUz(PWJ5cOKPZIA9XNKIR6epILuSiiwUzdWZCxDc6UrbHaGCb4caG5batJcEc6Chp8fhdIhMw88Wa88GsMeZdnLh0fAB0vZTCbuY0zrri2LJTX)r9CbuY0zrJhXsluCRRMlyPIhHFMMUGy7eZGumucYCbxOg0JGKPXLcllfvumlgKIHsqMBXxu7I6fsJnQ51yPOIIzXGumucYC7lD1ChxaampaawjTAOcYdr5MlsfKh0YXd5a8yEiHiokxaLmDw04rSKIjAD2Ky8RrWEJaJwnH5Ncp26(Uj94bacPXIZ)JfsXqjiZTkz6fhm4ih18ASuurXSyqkgkbzU9LUAUl6yy06w33nPhpqGuUakz6SOXJyPvtMo2gfdsWEJW)JfsXqjiZTkz6fhm4ih18ASuurXSyqkgkbzU9LUAUJlGsMolA8iwA9y6Xi3fKG9gXk6EBrlGPbetPuf1mwuFWG9)yHumucYCRsMEXbdoUrnVgRIfbXYnBaEMtfR7SV0vZDX8)yv)KWGaMOgRsMEXJMlGsMolA8iwY0qahkdWI6GeFnc2BeXTIU3w0cyAaXOd(f0a0I6hBfDVT7tNJfBiGJfFrTlQxiqA0GbRKPxC2Rl2N6bcaglUv092IwatdigDWVGgGwuFWGxr3B7(05yXgc4yXxu7I6fcKgnxaLmDw04rSKwKthSAye1yeS3iIZ)JfsXqjiZTkz6fp2OMxJLIkkMfdsXqjiZTV0vZDrdgS)hR6NegeWe1yvY0loxaLmDw04rSKIjADMpQHEb7ncLm9IZEDX(upqaqWGJdJw36(Uj94bcKgdJwnH5Ncp26(Uj94bcaeGIMlGsMolA8iwA34VAY0jyVreN)hlKIHsqMBvY0lESrnVglfvumlgKIHsqMBFPRM7Igmy)pw1pjmiGjQXQKPxCUakz6SOXJyPvfILB2GBcYub7nIv092IwatdigDWVGgGwu)ykz6fN96I9Pi8em4v092UpDowSHaow8f1UOEbrCXuY0lo71f7tr4jxaampeLHsNuKhgCxi)HYdOuf6CbuY0zrJhXsO0Z65Iub7nIPfVhaeqGbh5JsOTV)DwSk63fetf9n9G6odQH0fPzyVG66Gbh5JsOTV)D2fnTZILBM7In9CbuY0zrJhXsO0Z65IcwQ4rOrLcuXkLTZAy5M5NcpwWEJiUtPVi3UOPDwSCZ8pEFY0zzFPRM7If5OMxJfTaMgqmLsvuZyFPRM7Igm44I8u6lYTKSCVO3Xm9(7etUvubSjowKNsFrUDrt7Sy5M5F8(KPZY(sxn3fnxaLmDw04rSek9SEUOGLkEeAuPavSsz7SgwUz(PWJfS3iizACPWYQ(jrnG8P3IVO2f1lprsS4oL(ICljl3l6DmtV)oXKBfvaBIbd(u6lYTlAANfl3m)J3NmDw2x6Q5UyJAEnw0cyAaXukvrnJ9LUAUlAUakz6SOXJyju6z9Crblv8i0OsbQyLY2znSCZ8tHhlyVrSBiGddFrTlQxKmnUuyzv)KOgq(0BXxu7IgpGJeUakz6SOXJyju6z9Crblv8iukWfADkdRrnXmsIvJG9gH7RO7TfRrnXmsIvdZ9v092shLGSxEYfqjtNfnEelHspRNlkyPIhHsbUqRtzynQjMrsSAeS3i8)yHqvSR1ILBMg1JZbOvjtV4X8)yv)KWGaMOgRsMEX5cOKPZIgpILqPN1ZffSuXJqPaxO1PmSg1eZijwnc2BeKmnUuyzv)KOgq(0BXxDGIf3P0xKBjz5ErVJz693jMCROcytCSDdbCy4lQDr9IKPXLclljl3l6DmtV)oXKBXxu7IgpabeyWrEk9f5wswUx07yME)DIj3kQa2ehnxaLmDw04rSek9SEUOGLkEekf4cToLH1OMygjXQrWEJy3qahg(IAxuVizACPWYQ(jrnG8P3IVO2fnEaciUakz6SOXJyju6z9Crblv8iw00olwUzUl20lyVrehjtJlfww1pjQbKp9w8vhOyUVIU329PZXDbXeMOLZshLGShiqsStPVi3UOPDwSCZ8pEFY0zzFPRM7Igm4v092IwatdiMsPkQzSO(Gb7)XcPyOeK5wLm9IZfqjtNfnEelHspRNlkyPIhbwf97cIPI(MEqDNb1q6I0mSxqDDb7ncsMgxkSSQFsudiF6T4lQDr9cGGbpQ51yvSiiwUzdWZCQyDN9LUAUdmyS2o2x8ASQZrTD5fs5cOKPZIgpILqPN1ZffSuXJyfeuwNT(ZuJOwkrWEJGKPXLcllfvumlgKIHsqMBXxu7I6bacqGbh5OMxJLIkkMfdsXqjiZTV0vZDXMw8EaqabgCKpkH2((3zXQOFxqmv030dQ7mOgsxKMH9cQRZfqjtNfnEelHspRNlkyPIhbG9ugWuO5yb7nc)pwifdLGm3QKPxCWGJCuZRXsrffZIbPyOeK52x6Q5UytlEpaiGadoYhLqBF)7Syv0VliMk6B6b1DgudPlsZWEb115cOKPZIgpILqPN1ZffSuXJasnNOgZXu26vKfS3i8)yHumucYCRsMEXbdoYrnVglfvumlgKIHsqMBFPRM7InT49aGacm4iFucT99VZIvr)UGyQOVPhu3zqnKUind7fuxNlGsMolA8iwcLEwpxuWsfpciCwquMpUfvddRqxWEJaJw3leaES4Mw8EaqabgCKpkH2((3zXQOFxqmv030dQ7mOgsxKMH9cQRhnxaLmDw04rSKFoDwc2BeKmnUuyzvSiiwUzdWZCxDw8vhiWG9)yHumucYCRsMEXbdEfDVTOfW0aIPuQIAglQpxaampefs7A0U6cIhIcSXOMxdpef2OqONhAkpO8GpUtCpG4cOKPZIgpILs0zfFfzb7ncxo2fng18Ay(gfc9w8f1UOEHaI44cOKPZIgpILiQXWuY0zXmnDeSuXJ4u6lYPCbuY0zrJhXse1yykz6SyMMocwQ4rqY04sHfLlGsMolA8iwIOgdtjtNfZ00rq6GBYGWtblv8i08c2Bekz6fN96I9PEGaGCbuY0zrJhXse1yykz6SyMMocshCtgeEkyPIhb0RJBIG9gHsMEXzVUyFkcp5cOKPZIgpIL2Noh3feJo4g5libeXC2OyOpueEkyVr4(k6EB3Noh3fetyIwolDucYEHeUaCbaW8aaOeWuEaNJoDwCbuY0zrTAEeURdqMwoM7efKG9gbjtJlfww1pjQbKp9w8f1UOXuY0loZLJDF6CCxqmHjA58aqCbuY0zrTA(4rSK772Cb7ncsMgxkSSQFsudiF6T4lQDrJPKPxCMlh7(054UGyct0Y5bG4cOKPZIA18XJyj31biL5qVG9gbjtJlfww1pjQbKp9w8f1UOXuY0loZLJDF6CCxqmHjA58aqCbuY0zrTA(4rS09B3fBIG9gH76aKPLJ5orbzNMGCxqXWOvty(PWJTUVBspE5jsIf5OMxJDfftNUGy0eFQ9LUAUlwKluCRRMB9Z00feBNygKIHsqMZfqjtNf1Q5JhXs3VDxSjc2BeURdqMwoM7efKDAcYDbflUiDxhGmKRgc4y3ct0YDhBum0hASrnVg7kkMoDbXOj(u7lD1Cx0XICHIBD1CRFMMUGy7eZGumucYCUakz6SOwnF8iwIssum0z0b3iFb7nc31bitlhZDIcYonb5UGIrY04sHLv9tIAa5tVfFrTlkxaLmDwuRMpEelrmQWUGyuGQlfsfS3iCxhGmTCm3jki70eK7ckgjtJlfww1pjQbKp9w8f1UOCbuY0zrTA(4rS09B3fBIG9grKluCRRMB9Z00feBNygKIHsqMZfqjtNf1Q5JhXs7tNJ7cIrhCJ8fKaIyoBum0hkcpfS3iIlU4IZ9v092UpDoUliMWeTCw6OeK9cjXICfDVTOfW0aIPuQIAglQF0Gb7(k6EB3Noh3fetyIwolDucYEb4rhJKPXLclR6Ne1aYNEl(IAxuVa8Obd29v092UpDoUliMWeTCw6OeK9YZOJfhjtJlfwwflcILB2a8m3vNfFrTlQhinAUakz6SOwnF8iwYDDaYizBeS3iwr3Blf15EXCzkAXxjtmmAD70INnjdjEarCCbuY0zrTA(4rSK76aKrY2iyVrSIU3wkQZ9I5Yu0IVsMyrUqXTUAU1pttxqSDIzqkgkbzoyW(FSqkgkbzUvjtV4CbuY0zrTA(4rSK76aKrY2iyVrGrRMW8tHhBDF3KE8YtKelosMgxkSSQFsudiF6T4lQDr9aPGb7(k6EB3Noh3fetyIwolDucYEGKOJf5cf36Q5w)mnDbX2jMbPyOeK5CbuY0zrTA(4rSeLKOyOZOdUr(csarmNnkg6dfHNc2BeXfhjtJlfwwflcILB2a8m3vNfFrTlQhifmy31bid5QHaowxt1vZzAoUOJfhjtJlfww1pjQbKp9w8f1UOEG0yUVIU329PZXDbXeMOLZshLGShacmy3xr3B7(054UGyct0YzPJsq2dKeDS42neWHHVO2f1lsMgxkSSURdqMwoM7efKfFrTlA8EciWG3neWHHVO2f1dsMgxkSSQFsudiF6T4lQDrJoAUakz6SOwnF8iwIyuHDbXOavxkKkibeXC2OyOpueEkyVrexCKmnUuyzvSiiwUzdWZCxDw8f1UOEGuWGDxhGmKRgc4yDnvxnNP54IowCKmnUuyzv)KOgq(0BXxu7I6bsJ5(k6EB3Noh3fetyIwolDucYEaiWGDFfDVT7tNJ7cIjmrlNLokbzpqs0XIB3qahg(IAxuVizACPWY6UoazA5yUtuqw8f1UOX7jGadE3qahg(IAxupizACPWYQ(jrnG8P3IVO2fn6O5cOKPZIA18XJyj31biJKTrWEJaJwnH5Ncp26(Uj94fabuSixO4wxn36NPPli2oXmifdLGmNlGsMolQvZhpIL2Noh3feJo4g5lyVrexCXfN7RO7TDF6CCxqmHjA5S0rji7fsIf5k6EBrlGPbetPuf1mwu)Obd29v092UpDoUliMWeTCw6OeK9cWJogjtJlfww1pjQbKp9w8f1UOEb4rdgS7RO7TDF6CCxqmHjA5S0rji7LNrhlosMgxkSSkweel3Sb4zURol(IAxupqkyWURdqgYvdbCSUMQRMZ0CCrZfqjtNf1Q5JhXsusIIHoJo4g5lyVr4UoazA5yUtuq2Pji3fexaLmDwuRMpEel5UoazKSnc2BerUqXTUAU1pttxqSDIzqkgkbzoxaUakz6SOwsMgxkSOiuSiiwUzdWZCxDCbuY0zrTKmnUuyrJhXsQFsudiF6fS3iCFfDVT7tNJ7cIjmrlNLokbzpqGKyXPKPxC2Rl2N6bcacgCKNsFrUDrt7Sy5M5F8(KPZY(sxn3bgCKAupUNBfviukl3Sb4zURo7lD1ChyWNsFrUDrt7Sy5M5F8(KPZY(sxn3flUrnVglAbmnGykLQOMX(sxn3fJKPXLcllAbmnGykLQOMXIVO2f1leaoyWroQ51yrlGPbetPuf1m2x6Q5UOJMlGsMolQLKPXLclA8iwYPyKzdwl6oXI60zjyVrejwBh7lEnw15O2hfSPdfmyS2o2x8ASQZrTD5HNiLlGsMolQLKPXLclA8iwIIkkMfdsXqjiZfS3iWOvty(PWJTUVBspE5js4cOKPZIAjzACPWIgpILqlGPbetPuf1mc2BeNsFrUDrt7Sy5M5F8(KPZY(sxn3fZ)Jv9tcdcyIASkz6fhmy3xr3B7(054UGyct0YzPJsq2lKelYtPVi3UOPDwSCZ8pEFY0zzFPRM7IfxKAupUNBfviukl3Sb4zURo7lD1ChyWAupUNBfviukl3Sb4zURo7lD1Cxm)pw1pjmiGjQXQKPx8O5cOKPZIAjzACPWIgpILqlGPbetPuf1mc2Bekz6fN96I9PEGaGXIlosMgxkSSURdqMwoM7efKfFrTlQxiGiUyroQ51yDF3MBFPRM7Igm44izACPWY6(Un3IVO2f1leqexSrnVgR772C7lD1Cx0rZfqjtNf1sY04sHfnEelrbQeKnNnapdTeM4biib7nIrXqFStlE2KmxFp8ejCbuY0zrTKmnUuyrJhXs6Ak2LoDwmtlUkyVrOKPxC2Rl2N6ba5cOKPZIAjzACPWIgpILOcvSyxqmXMoc2Bekz6fN96I9PEaqUakz6SOwsMgxkSOXJyjAIAy4R(hlibeXC2OyOpueEkyVrmkg6JDAXZMK567fam2OyOp2PfpBsMRVhiHlGsMolQLKPXLclA8iwIMOgg(Q)Xc2BeJIH(yNw8Sjz(KHb4iXlKgdJw3leX5jGXk6EBrlGPbetPuf1mwu)O5cOKPZIAjzACPWIgpILqlGPbeB10qahUaCbuY0zrTNsFrofH4ftmiwUzgus7yo8vrQG9gbgTUDAXZMK5PhqexmmA1eMFk8yVqcG4cOKPZIApL(ICA8iwA1KPJLB2a8SxxeKG9gH76aKPLJ5orbzNMGCxqGb7)XQ(jHbbmrnwLm9IhtjtV4SxxSpfHNCbuY0zrTNsFronEelbHQyxRfl3mnQhNdqb7nI4izACPWYQ(jrnG8P3IVO2f1laumsMgxkSSkweel3Sb4zURol(IAxupizACPWYsYY9IEhZ07Vtm5w8f1UOrdgmjtJlfwwflcILB2a8m3vNfFrTlQxaKlGsMolQ9u6lYPXJyPb4zO1AIwo2oXKlyVrSIU3w8jiBoLY2jMClQpyWRO7TfFcYMtPSDIjNrs0Ao2shLGSxE6jxaLmDwu7P0xKtJhXs7KGsVJPr94EoB9QOG9grKURdqMwoM7efKDAcYDbXfqjtNf1Ek9f504rSejlYRbRZDSTrfVG9gHlhljlYRbRZDSTrfpBffxw8f1UOiaexaLmDwu7P0xKtJhXs(O4EdQli2QrPJG9grKURdqMwoM7efKDAcYDbXfqjtNf1Ek9f504rSKWeBClExm8PzPf5c2BeJAEnwflcILB2a8mNkw3zFPRM7IDk9f52fnTZILBM)X7tMolRyxjo2k6EBrlGPbeJo4xqdqlQpyWNsFrUDrt7Sy5M5F8(KPZYk2vIJ5)XQ(jHbbmrnwLm9Idg8OMxJvXIGy5MnapZPI1D2x6Q5Uy(FSQFsyqatuJvjtV4XizACPWYQyrqSCZgGN5U6S4lQDr9aabiWGh18ASkweel3Sb4zovSUZ(sxn3fZ)JvXIGyqatuJvjtV4CbuY0zrTNsFronEeljmXg3I3fdFAwArUG9grKURdqMwoM7efKDAcYDbfBfDVTOfW0aIrh8lObOf1pwKNsFrUDrt7Sy5M5F8(KPZYk2vIJf5OMxJvXIGy5MnapZPI1D2x6Q5oWGhfd9XoT4ztYC99IKPXLclR6Ne1aYNEl(IAxuUakz6SO2tPViNgpILWTVV5SUyuFLCb7nIiDxhGmTCm3jki70eK7cIlGsMolQ9u6lYPXJyj8v)UGyBJkEQG9grKRO7T1VngfZYnBJt6yr9Jf5k6EBxXxhGSCZOD5WkusvlQFS4gfd9Xc8QzaY8jJhiaGacm4rXqFSaVAgGmFY4fcaciWG3neWHHVO2f1lKG0O5cWfqjtNf1c964MGWDDaYizBeS3iwr3Blf15EXCzkAXxjtmmAD70INnjdjEarCXICHIBD1CRFMMUGy7eZGumucYCWG9)yHumucYCRsMEX5cOKPZIAHEDCtIhXsURdqgjBJG9gbgTAcZpfES19Dt6XlprsmmAD70INnjdjEarCXICHIBD1CRFMMUGy7eZGumucYCUakz6SOwOxh3K4rSeLKOyOZOdUr(c2BeUVIU329PZXDbXeMOLZI6hlosMgxkSSQFsudiF6T4lQDr9aPGbpQ51yrlGPbetPuf1m2x6Q5UyKmnUuyzrlGPbetPuf1mw8f1UOEaabd29v092UpDoUliMWeTCw6OeK9ajrZfqjtNf1c964MepILigvyxqmkq1LcPc2BeUVIU329PZXDbXeMOLZI6hlosMgxkSSQFsudiF6T4lQDr9aPGbpQ51yrlGPbetPuf1m2x6Q5UyKmnUuyzrlGPbetPuf1mw8f1UOEaabd29v092UpDoUliMWeTCw6OeK9ajrZfqjtNf1c964MepILCxhGms2gb7ncmA1eMFk8yR77M0JxaeqXICHIBD1CRFMMUGy7eZGumucYCUakz6SOwOxh3K4rS0(054UGy0b3iFb7nc3xr3B7(054UGyct0YzPJsq2lKeJKPXLclR6Ne1aYNEl(IAxuVaCWGDFfDVT7tNJ7cIjmrlNLokbzV8KlGsMolQf61XnjEel5UoazKSnc2BerUqXTUAU1pttxqSDIzqkgkbzUCKJuc]] )

end
