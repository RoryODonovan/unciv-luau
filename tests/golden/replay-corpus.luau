--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Original deterministic engine/fog regression corpus. Run via run.mjs for baseline comparison and update.
local BaseGame = require("../../src/simulation/BaseGame")
local Canonical = require("./canonical")
local args = {...}
assert(#args == 1 and (args[1] == "default" or args[1] == "full"), "run node tests/golden/run.mjs")
local full = args[1] == "full"
local started = os.clock()

-- Independent FNV-1a reference vectors and encoder invariants run even in update mode.
assert(Canonical.hashBytes("") == "cbf29ce484222325")
assert(Canonical.hashBytes("a") == "af63dc4c8601ec8c")
assert(Canonical.hashBytes("foobar") == "85944171f73967e8")
assert(Canonical.encode({z=1, a={3,2,1}}) == '{"a":[3,2,1],"z":1}')
assert(Canonical.encode({a=1,z=2}) == Canonical.encode({z=2,a=1}))
assert(Canonical.hash({1,2}) ~= Canonical.hash({2,1}))
assert(Canonical.encode('"\\\n\0') == '"\\"\\\\\\u000a\\u0000"')
assert(Canonical.encode(1/3) == "0.33333333333333331")
assert(Canonical.encode(-0) == "0" and Canonical.encode(9007199254740991) == "9007199254740991")
assert(Canonical.hash(1) ~= Canonical.hash("1") and Canonical.encode({}) == "{}")
assert(not pcall(Canonical.encode, math.huge) and not pcall(Canonical.encode, 0/0))
assert(not pcall(Canonical.encode, {[1]=1,[3]=3}) and not pcall(Canonical.encode, {[1]=1,a=2}))

-- Balance harness options, with the corresponding MapSizes Tiny/Small/Medium sphere frequencies.
-- Leave policyCostIncrease implicit in new() to catch changes to the engine's pace-derived default too.
local presets = {
    {name="Quick",radius=10,frequency=6,maxTurns=45,cultureVictoryPolicies=4,policyCostIncrease=50},
    {name="Standard",radius=15,frequency=8,maxTurns=80,cultureVictoryPolicies=6,policyCostIncrease=63},
    {name="Full",radius=20,frequency=12,maxTurns=120,cultureVictoryPolicies=6,policyCostIncrease=140},
}
local seeds = {7919,15838,23757,31676,39595,47514,55433,63352}
local config = {
    schemaVersion=1, encoder="canonical-json-empty-object-v1", hash="fnv1a-64",
    driver="base-content-first-city-first-research-end-turn", difficulty="Normal", humanPlayers=1,
    checkpointEvery=10, defaultSeedCount=2, barbarians="odd seed index on, even off",
    seeds=seeds, shapes={"Hex","Sphere"}, presets=presets,
}
print("GOLDEN_CONFIG " .. Canonical.encode(config))

local function apply(state: BaseGame.State, command: BaseGame.Command)
    local result = BaseGame.apply(state, 1, command)
    assert(result.ok, result.message)
end

local function newGame(seed: number, preset: any, shape: string, barbarians: boolean): BaseGame.State
    local state = BaseGame.new(seed, {
        humanPlayers=1, difficulty="Normal", mapShape=shape,
        radius=if shape == "Hex" then preset.radius else nil,
        frequency=if shape == "Sphere" then preset.frequency else nil,
        maxTurns=preset.maxTurns, cultureVictoryPolicies=preset.cultureVictoryPolicies, barbarians=barbarians,
    })
    assert(state.policyCostIncrease == preset.policyCostIncrease, "balance preset policy cost growth changed")
    local settler: number? = nil
    for _, unit in state.units do
        if unit.ownerId == 1 and unit.kind == "Settler" then settler = unit.id; break end
    end
    assert(settler, "missing first settler")
    apply(state, {kind="FoundCity",unitId=settler})
    return state
end

local function turn(state: BaseGame.State)
    -- Same deterministic player-1 policy as tests/unit/base-content.luau; AI player 2 is engine driven.
    if not state.players[1].research then
        local view = BaseGame.snapshot(state, 1)
        if #view.availableResearch > 0 then apply(state, {kind="Research",technology=view.availableResearch[1].id}) end
    end
    apply(state, {kind="EndTurn"})
end

local function hashes(state: BaseGame.State): {[string]: string}
    return {
        state=Canonical.hash(BaseGame.serialize(state)),
        actor1=Canonical.hash(BaseGame.snapshot(state, 1)),
        actor2=Canonical.hash(BaseGame.snapshot(state, 2)),
    }
end

for _, preset in presets do
    for _, shape in config.shapes do
        for index, seed in seeds do
            if not full and index > config.defaultSeedCount then continue end
            local barbarians = index % 2 == 1
            local id = string.format("%s/%s/seed-%d/barbarians-%s", preset.name, shape, seed, if barbarians then "on" else "off")
            local state = newGame(seed, preset, shape, barbarians)
            local resumed: BaseGame.State? = if index <= config.defaultSeedCount then newGame(seed, preset, shape, barbarians) else nil
            local checkpoints: {any} = {}
            local function checkpoint(label: string, completedRound: number)
                local current = hashes(state)
                if resumed then
                    local restored = hashes(resumed)
                    for _, field in {"state","actor1","actor2"} do
                        assert(current[field] == restored[field], string.format(
                            "GOLDEN RESUME MISMATCH %s checkpoint %s %s: uninterrupted=%s restored=%s",
                            id, label, field, current[field], restored[field]))
                    end
                end
                table.insert(checkpoints, {checkpoint=label,completedRound=completedRound,stateRound=state.turn,hashes=current})
            end
            checkpoint("initial", 0)
            while state.phase == "Playing" do
                local round = state.turn
                turn(state)
                if resumed then
                    assert(resumed.phase == "Playing" and resumed.turn == round, "resume phase/round drift: " .. id)
                    turn(resumed)
                    local restored, message = BaseGame.restore(BaseGame.serialize(resumed))
                    assert(restored, "resume rejected " .. id .. ": " .. tostring(message))
                    resumed = restored
                end
                if round % config.checkpointEvery == 0 then checkpoint("round-" .. round, round) end
                if state.phase ~= "Playing" then checkpoint("final", round) end
                assert(state.turn <= preset.maxTurns, "replay exceeded round limit: " .. id)
            end
            print("GOLDEN_GAME " .. Canonical.encode({
                id=id, finalRound=state.turn, phase=state.phase, winner=state.winner, victoryType=state.victoryType,
                checkpoints=checkpoints,
            }))
        end
    end
end
print(string.format("Golden Luau corpus completed in %.3f s (resume parity: 12 games).", os.clock() - started))
