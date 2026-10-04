--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Original W2-D cost, snapshot, AI and save regressions; no upstream parity claim.
local Game=require("../../src/simulation/BaseGame")
local Save=require("../../src/simulation/BaseSave")
local Rules=require("../../src/simulation/BaseRules")
local Canonical=require("../golden/canonical")
local function apply(s: any, owner: number, command: any)
    local result=Game.apply(s,owner,command); assert(result.ok,result.message)
end
local function unit(s: any, owner: number, kind: string): any
    for _, u in s.units do if u.ownerId==owner and u.kind==kind then return u end end
    error("missing unit")
end
local function city(s: any, owner: number): any
    for _, c in s.cities do if c.ownerId==owner then return c end end
    error("missing city")
end
local function founded(turns: number, solo: boolean?): any
    local s: any=Game.new(23,{maxTurns=turns,humanPlayers=if solo then 1 else 2,radius=10,barbarians=false})
    -- Bare, resource-free grassland makes the first-step yields independent of the generated terrain.
    for _, t in s.tiles do t.terrain="Grassland"; t.feature=nil; t.river=nil; t.resource=nil; t.improvement=nil end
    apply(s,1,{kind="FoundCity",unitId=unit(s,1,"Settler").id})
    if not solo then
        apply(s,1,{kind="EndTurn"})
        apply(s,2,{kind="FoundCity",unitId=unit(s,2,"Settler").id})
        apply(s,2,{kind="EndTurn"})
    end
    return s
end
local function rounded(base: number, percent: number): number return math.max(1,math.floor(base*percent/100+0.5)) end

-- Literal pace values, Full identity and monotonicity over the entire allowed round-limit domain.
for _, row in {{45,30},{80,54},{120,100},{200,200}} do
    assert(Game.costPercent(Game.new(1,{maxTurns=row[1]}))==row[2],"costPercent at "..row[1])
end
do
    local previous=0
    for turns=20,500 do
        local s: any={maxTurns=turns}; local percent=Game.costPercent(s)
        assert(percent>=previous and percent>=30 and percent<=200); previous=percent
    end
end

-- Every cost table entry (units, ordinary buildings, wonders and Space Project), research menu/current research,
-- purchase affordability/debit, forecasts and actual economy completions use the same rounded cost.
for _, row in {{45,30},{80,54},{120,100}} do
    local turns,percent=row[1],row[2]; local s=founded(turns); local home=city(s,1); local p=s.players[1]
    local view=Game.snapshot(s,1)
    for id,base in Rules.productionCosts do
        assert(view.productionCosts[id]==rounded(base,percent),"production "..id)
        assert(view.purchaseCosts[id]==rounded(base,percent)*4,"purchase "..id)
        assert(view.productionCosts[id]>=1)
    end
    for _, tech in view.availableResearch do assert(tech.cost==rounded(Rules.technologies[tech.id].cost,percent)) end
    apply(s,1,{kind="Research",technology="Mining"})
    assert(p.research.cost==rounded(14,percent) and (Game.snapshot(s,1).research :: any).cost==rounded(14,percent))
    -- A save at 45 rounds (and the other paces) retains the derived research cost and replays identically.
    local saved=Game.serialize(s); assert(Save.valid(saved) and saved.version==1 and saved.state.costPercent==nil)
    local restored=Game.restore(saved) :: any; local direct=Save.restore(saved) :: any
    assert(Canonical.encode(Game.serialize(restored))==Canonical.encode(saved))
    assert(Canonical.encode(direct)==Canonical.encode(restored),"both restore paths agree")
    apply(s,1,{kind="EndTurn"}); apply(restored,1,{kind="EndTurn"})
    assert(Canonical.encode(Game.serialize(s))==Canonical.encode(Game.serialize(restored)))
    apply(s,2,{kind="EndTurn"})
    -- Reject a cost that is neither the derived cost nor the legacy base cost, and an already-completed progress.
    local corrupt=Game.serialize(restored)
    corrupt.state.players[1].research={id="Mining",progress=0,cost=15}; assert(not Save.valid(corrupt))
    corrupt.state.players[1].research={id="Mining",progress=rounded(14,percent),cost=rounded(14,percent)}; assert(not Save.valid(corrupt))
    -- Purchase menu and application at exactly the paced affordability boundary.
    local cost=rounded(14,percent)*4; p.gold=cost-1
    assert(not table.find(Game.snapshot(s,1).availablePurchasesByCity[tostring(home.id)],"Monument"))
    assert(not Game.apply(s,1,{kind="Purchase",cityId=home.id,item="Monument"}).ok)
    p.gold=cost
    assert(table.find(Game.snapshot(s,1).availablePurchasesByCity[tostring(home.id)],"Monument"))
    apply(s,1,{kind="Purchase",cityId=home.id,item="Monument"}); assert(p.gold==0 and table.find(home.buildings,"Monument"))
    -- Reset to a fresh city so its forecast has positive food and a single completion to inspect.
    s=founded(turns); home=city(s,1); home.food=0; home.production=0; home.queue="Monument"
    local forecast=Game.snapshot(s,1).cityForecasts[tostring(home.id)]
    local growAt=rounded(28,percent); local madeAt=rounded(14,percent)
    assert(forecast.food>0 and forecast.production>0)
    assert(forecast.growthTurns==math.ceil(growAt/forecast.food))
    assert(forecast.productionTurns==math.ceil(madeAt/forecast.production))
    home.food=growAt-forecast.food; home.production=madeAt-forecast.production
    forecast=Game.snapshot(s,1).cityForecasts[tostring(home.id)]
    assert(forecast.growthTurns==1 and forecast.productionTurns==1)
    apply(s,1,{kind="EndTurn"})
    assert(home.population==2 and home.food==0 and home.production==0 and table.find(home.buildings,"Monument"))
    -- Production of a unit, a wonder and the Space Project spends each paced threshold exactly.
    for _, item in {"Worker","HangingGardens","SpaceProject"} do
        local f=founded(turns); local c=city(f,1); f.players[1].technologies=table.clone(Rules.technologyOrder)
        c.queue=item; c.production=0
        local nextStep=Game.snapshot(f,1).cityForecasts[tostring(c.id)]
        c.production=rounded(Rules.productionCosts[item],percent)-nextStep.production
        assert(Game.snapshot(f,1).cityForecasts[tostring(c.id)].productionTurns==1)
        apply(f,1,{kind="EndTurn"}); assert(c.production==0,"completion debits the paced cost: "..item)
        if Rules.buildings[item] then assert(table.find(c.buildings,item)) else assert(unit(f,1,item)) end
    end
    -- Snapshot tables remain detached and global rule costs remain the Full values.
    view.productionCosts.Warrior=999; view.purchaseCosts.Warrior=999
    assert(Game.snapshot(s,1).productionCosts.Warrior==rounded(12,percent) and Rules.productionCosts.Warrior==12)
end

-- Upgrades scale their minimum as well as the difference between rounded unit production costs.
for _, row in {{45,30},{80,54},{120,100}} do
    local s=founded(row[1]); local home=city(s,1); local warrior=unit(s,1,"Warrior")
    s.players[1].technologies={"Agriculture","Mining","BronzeWorking","IronWorking"}
    for _, t in s.tiles do if t.ownerId==1 and t.id~=home.tileId then t.terrain="Hills"; t.resource="Iron"; t.improvement="Mine"; break end end
    warrior.tileId=home.tileId; warrior.moves=2
    local cost=math.max(rounded(20,row[2]),rounded(28,row[2])-rounded(12,row[2]))*2
    s.players[1].gold=cost-1
    local function viewUnit(): any for _, u in Game.snapshot(s,1).units do if u.id==warrior.id then return u end end; error("missing view") end
    assert(viewUnit().upgradeCost==cost and not viewUnit().canUpgrade)
    assert(not Game.apply(s,1,{kind="UpgradeUnit",unitId=warrior.id}).ok)
    s.players[1].gold=cost; assert(viewUnit().canUpgrade)
    apply(s,1,{kind="UpgradeUnit",unitId=warrior.id}); assert(s.players[1].gold==0 and warrior.kind=="Swordsman")
end

-- At the same 70-gold treasury the AI can upgrade and keep its 40-gold reserve only at the shorter paces.
for _, turns in {45,80,120} do
    local s=founded(turns,true); local home=city(s,2); local warrior=unit(s,2,"Warrior")
    s.players[2].technologies={"Agriculture","Mining","BronzeWorking","IronWorking"}; s.players[2].gold=70; s.players[2].income.gold=10
    for _, t in s.tiles do if t.ownerId==2 and t.id~=home.tileId then t.terrain="Hills"; t.resource="Iron"; t.improvement="Mine"; break end end
    warrior.tileId=home.tileId; warrior.moves=2
    apply(s,1,{kind="EndTurn"})
    assert(warrior.kind==(if turns==120 then "Warrior" else "Swordsman"),"AI affordability at "..turns)
    assert(s.players[2].research.cost==rounded(16,Game.costPercent(s)),"AI research uses paced Archery cost")
end

-- A pre-pacing Quick save retains research's completed fraction through either public restore path.
do
    local s=founded(45); apply(s,1,{kind="Research",technology="Mining"})
    local legacy=Game.serialize(s); legacy.state.players[1].research={id="Mining",cost=14,progress=13}
    assert(Save.valid(legacy))
    local restored=Game.restore(legacy) :: any; local direct=Save.restore(legacy) :: any
    local r=restored.players[1].research; assert(r.cost==4 and r.progress==3)
    assert(Canonical.encode(direct)==Canonical.encode(restored)); assert(Save.valid(Game.serialize(restored)))
end
print("base cost pacing: research, production, purchase, growth, upgrades, snapshots, AI and saves passed")
