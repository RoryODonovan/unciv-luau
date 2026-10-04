--!nonstrict
-- SPDX-License-Identifier: MPL-2.0
-- Original AI-against-AI balance harness for the base game (run through tools/balance-sim.mjs, which supplies a
-- temporary copy of src whose BaseGame exposes its internal turn functions as BaseGame._internal). Both civilizations
-- are played by the built-in AI: each round runs, for civilization 1 then 2, the turn start, the AI, the economy, vision
-- and the victory check, then the round limit, then the barbarian phase, as BaseGame's EndTurn does. Not part of the
-- test gate; it prints a victory table.
local BaseGame=require("./src/simulation/BaseGame")
local Rules=require("./src/simulation/BaseRules")
local WorldMap=require("./src/simulation/WorldMap")
local I=(BaseGame :: any)._internal
assert(I,"run this through tools/balance-sim.mjs")
local args={...}
local seeds=tonumber(args[1]) or 12
local culture=args[2]~="off"
-- The host match presets measured here (Quick 4 policies, Standard and Full 6): map radius, round limit
-- and culture threshold. The policy cost growth is the engine default for the round limit.
local presets={
    {name="Quick",radius=10,maxTurns=45,policies=4},
    {name="Standard",radius=15,maxTurns=80,policies=6},
    {name="Full",radius=20,maxTurns=120,policies=6},
}
local function eraOf(p): number
    local e=1; for _, id in p.technologies do e=math.max(e,Rules.technologies[id].era) end; return e
end
local function median(list: {number}): number
    local sorted=table.clone(list); table.sort(sorted); return sorted[math.max(1,math.ceil(#sorted/2))] or 0
end
print(string.format("AI against AI, %d seeds per preset (seed = n x 7919), barbarians on, Normal, culture victory %s",seeds,if culture then "on" else "off"))
print("| Preset | Policy cost growth | Victories | Draw | First war round, median (games) | End round, median (range) | Technologies at the end, median (max) | Highest era at the end, median | Eras first reached, median round (games) |")
print("| --- | ---: | --- | ---: | --- | --- | --- | ---: | --- |")
for _, preset in presets do
    local wins: {[string]: number}={}; local ends,techs,eras,wars={},{},{},{}; local reached: {[number]: {number}}={}; local growth=0
    local owned={[25]={},[50]={},[75]={}}; local firstCulture,capitalCulture={},{}
    for n=1,seeds do
        local s=BaseGame.new(n*7919,{radius=preset.radius,maxTurns=preset.maxTurns,cultureVictoryPolicies=preset.policies})
        growth=s.policyCostIncrease
        if not culture then s.cultureVictoryPolicies=99 end
        s.players[1].human=false
        local map=WorldMap.fromTiles(s.tiles,s.radius); local seenCulture={}
        local function territoryMetric()
            local counts={}; for _, c in s.cities do counts[c.id]=0 end
            for _, tile in s.tiles do
                local best,dist=nil,4
                for _, c in s.cities do
                    if c.ownerId~=tile.ownerId then continue end
                    local d=WorldMap.distance(map,c.tileId,tile.id)
                    if d<dist or (d==dist and best and c.id<best.id) then best=c; dist=d end
                end
                if best then counts[best.id]+=1 end
            end
            for _, count in counts do table.insert(owned[s.turn],count) end
        end
        local first: {[number]: number}={}; local firstWar: number?=nil
        while s.phase=="Playing" do
            for owner=1,2 do
                I.beginTurn(s,owner); I.ai(s,owner)
                if not firstWar and s.diplomacy.status=="War" then firstWar=s.turn end
                local nextEvent=s.nextEvent
                I.economy(s,owner); I.refreshVision(s); I.evaluate(s)
                for _, e in s.events do
                    if e.id>=nextEvent and e.kind=="BorderGrowth" and e.amount==nil and not seenCulture[e.cityId] then
                        seenCulture[e.cityId]=true; table.insert(firstCulture,s.turn)
                        for _, c in s.cities do if c.id==e.cityId and c.capital then table.insert(capitalCulture,s.turn) end end
                    end
                end
                if s.phase~="Playing" then break end
            end
            if owned[s.turn] then territoryMetric() end
            if s.phase~="Playing" then break end
            if s.turn>=s.maxTurns then
                local v=I.scores(s); s.phase="Finished"
                if v[1]~=v[2] then s.winner=if v[1]>v[2] then 1 else 2; s.victoryType="Score"
                else
                    local one,two=s.players[1],s.players[2]
                    local k1,k2=#one.technologies+#one.policies,#two.technologies+#two.policies
                    if k1~=k2 then s.winner=if k1>k2 then 1 else 2; s.victoryType="Score"
                    else s.winner=nil; s.victoryType="Draw" end
                end
                break
            end
            if s.barbarians then I.barbarianTurn(s); I.refreshVision(s); I.evaluate(s); if s.phase~="Playing" then break end end
            for owner=1,2 do for era=1,eraOf(s.players[owner]) do if not first[era] then first[era]=s.turn end end end
            s.turn += 1
        end
        wins[s.victoryType]=(wins[s.victoryType] or 0)+1; table.insert(ends,s.turn)
        if firstWar then table.insert(wars,firstWar) end
        for owner=1,2 do table.insert(techs,#s.players[owner].technologies); table.insert(eras,eraOf(s.players[owner])) end
        for era,round in first do reached[era]=reached[era] or {}; table.insert(reached[era],round) end
    end
    local kinds={}; for kind,count in wins do if kind~="Draw" then table.insert(kinds,kind.." "..count) end end; table.sort(kinds)
    local eraText={}; for era=2,#Rules.eras do if reached[era] then table.insert(eraText,string.format("%s %d (%d)",Rules.eras[era],median(reached[era]),#reached[era])) end end
    print(string.format("| %s (radius %d, %d rounds, %d policies) | %d | %s | %d | %s | %d (%d-%d) | %d (%d) | %d | %s |",preset.name,preset.radius,preset.maxTurns,preset.policies,growth,
        table.concat(kinds,", "),wins.Draw or 0,if #wars>0 then string.format("%d (%d)",median(wars),#wars) else "none (0)",median(ends),math.min(table.unpack(ends)),math.max(table.unpack(ends)),median(techs),math.max(table.unpack(techs)),median(eras),table.concat(eraText,", ")))
    local function metric(list) return if #list>0 then tostring(median(list)).." ("..#list..")" else "n/a (0)" end
    print(string.format("Territory %s: median tiles/city round 25 %s; 50 %s; 75 %s; first culture round %s; capital first culture round %s",preset.name,metric(owned[25]),metric(owned[50]),metric(owned[75]),metric(firstCulture),metric(capitalCulture)))
end
