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

-- Literal category values, Full identity and monotonicity over the entire allowed round-limit domain.
local paceRows={{45,20,61,61,148},{80,48,82,82,118},{120,100,100,100,100},{200,200,129,129,82}}
local categories: {Game.CostCategory}={"tech","production","growth","policy"}
for _, row in paceRows do
    local s=Game.new(1,{maxTurns=row[1]})
    for index,category in categories do assert(Game.costPercent(s,category)==row[index+1],category.." percent at "..row[1]) end
    assert(Game.costPercent(s)==row[2],"default category is tech")
end
for _, category in categories do
    local previous=Game.costPercent(({maxTurns=20} :: any),category)
    for turns=21,500 do
        local percent=Game.costPercent(({maxTurns=turns} :: any),category)
        assert(percent>=(if category=="tech" then 20 else 30) and percent<=200)
        assert(if category=="policy" then percent<=previous else percent>=previous,category.." monotonicity")
        previous=percent
    end
end

-- Every cost table entry (units, ordinary buildings, wonders and Space Project), research menu/current research,
-- purchase affordability/debit, forecasts and actual economy completions use their category cost.
for _, row in paceRows do
    local turns,techPercent,percent,growthPercent=row[1],row[2],row[3],row[4]; local s=founded(turns); local home=city(s,1); local p=s.players[1]
    local view=Game.snapshot(s,1)
    for id,base in Rules.productionCosts do
        assert(view.productionCosts[id]==rounded(base,percent),"production "..id)
        assert(view.purchaseCosts[id]==rounded(base,percent)*4,"purchase "..id)
        assert(view.productionCosts[id]>=1)
    end
    for _, tech in view.availableResearch do assert(tech.cost==rounded(Rules.technologies[tech.id].cost,techPercent)) end
    apply(s,1,{kind="Research",technology="Mining"})
    assert(p.research.cost==rounded(14,techPercent) and (Game.snapshot(s,1).research :: any).cost==rounded(14,techPercent))
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
    corrupt.state.players[1].research={id="Mining",progress=rounded(14,techPercent),cost=rounded(14,techPercent)}; assert(not Save.valid(corrupt))
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
    local growAt=rounded(28,growthPercent); local madeAt=rounded(14,percent)
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
for _, row in paceRows do
    local s=founded(row[1]); local home=city(s,1); local warrior=unit(s,1,"Warrior")
    s.players[1].technologies={"Agriculture","Mining","BronzeWorking","IronWorking"}
    for _, t in s.tiles do if t.ownerId==1 and t.id~=home.tileId then t.terrain="Hills"; t.resource="Iron"; t.improvement="Mine"; break end end
    warrior.tileId=home.tileId; warrior.moves=2
    local cost=math.max(rounded(20,row[3]),rounded(28,row[3])-rounded(12,row[3]))*2
    s.players[1].gold=cost-1
    local function viewUnit(): any for _, u in Game.snapshot(s,1).units do if u.id==warrior.id then return u end end; error("missing view") end
    assert(viewUnit().upgradeCost==cost and not viewUnit().canUpgrade)
    assert(not Game.apply(s,1,{kind="UpgradeUnit",unitId=warrior.id}).ok)
    s.players[1].gold=cost; assert(viewUnit().canUpgrade)
    apply(s,1,{kind="UpgradeUnit",unitId=warrior.id}); assert(s.players[1].gold==0 and warrior.kind=="Swordsman")
end

-- At the same 75-gold treasury the AI can upgrade and keep its 40-gold reserve only at the shorter paces.
for _, turns in {45,80,120} do
    local s=founded(turns,true); local home=city(s,2); local warrior=unit(s,2,"Warrior")
    -- The final technology stays in progress even at Quick; cheap Archery can finish in this same economy step.
    s.players[2].technologies=table.clone(Rules.technologyOrder); table.remove(s.players[2].technologies)
    s.players[2].gold=75; s.players[2].income.gold=10
    for _, t in s.tiles do if t.ownerId==2 and t.id~=home.tileId then t.terrain="Hills"; t.resource="Iron"; t.improvement="Mine"; break end end
    warrior.tileId=home.tileId; warrior.moves=2
    apply(s,1,{kind="EndTurn"})
    assert(warrior.kind==(if turns==120 then "Warrior" else "Swordsman"),"AI affordability at "..turns)
    assert(s.players[2].research and s.players[2].research.id=="SpaceFlight" and s.players[2].research.cost==rounded(Rules.technologies.SpaceFlight.cost,Game.costPercent(s)),"AI research uses paced Space Flight cost")
end

-- Policy bases scale before the unchanged adoption-growth formula and Oracle discount.
-- Check all policies, every adopted count, explicit growth options, refusal/debit and Full identity.
for _, row in paceRows do
    for _, increase in {0,50,140} do
        for count=0,#Rules.policyOrder-1 do
            local s=founded(row[1]); local p=s.players[1]; s.policyCostIncrease=increase
            for index=1,count do table.insert(p.policies,Rules.policyOrder[index]) end
            local id=Rules.policyOrder[count+1]; local base=Rules.policies[id].cost
            local expected=math.floor(rounded(base,row[5])*(100+increase*count)/100)
            local function menuCost(): number
                for _, policy in Game.snapshot(s,1).availablePolicies do if policy.id==id then return policy.cost end end
                error("missing policy "..id)
            end
            assert(menuCost()==expected,"policy cost at "..row[1].."/"..id)
            if row[1]==120 then assert(expected==math.floor(base*(100+increase*count)/100),"Full policy identity") end
            p.culture=expected-1; assert(not Game.apply(s,1,{kind="AdoptPolicy",policy=id}).ok)
            p.culture=expected; apply(s,1,{kind="AdoptPolicy",policy=id}); assert(p.culture==0)
            -- Fresh state avoids the victory reached by the final adoption above.
            s=founded(row[1]); p=s.players[1]; s.policyCostIncrease=increase
            for index=1,count do table.insert(p.policies,Rules.policyOrder[index]) end
            table.insert(city(s,1).buildings,"Oracle")
            for _, policy in Game.snapshot(s,1).availablePolicies do if policy.id==id then assert(policy.cost==math.floor(expected*0.75)) end end
        end
    end
end

-- AI uses the same paced policy affordability and debit, including an Oracle discount.
for _, row in paceRows do
    for _, oracle in {false,true} do
        for _, delta in {-1,0} do
            local s=founded(row[1],true); local p=s.players[2]
            if oracle then table.insert(city(s,2).buildings,"Oracle") end
            local expected=rounded(Rules.policies.Tradition.cost,row[5])
            if oracle then expected=math.floor(expected*0.75) end
            p.culture=expected+delta
            apply(s,1,{kind="EndTurn"})
            assert((table.find(p.policies,"Tradition")~=nil)==(delta==0),"AI policy boundary at "..row[1])
            -- Economy follows adoption; its reported culture income must be the only new culture.
            assert(p.culture==(if delta==0 then 0 else expected-1)+p.income.culture,"AI policy debit")
        end
    end
end

-- A pre-pacing Quick save retains research's completed fraction through either public restore path.
do
    local s=founded(45); apply(s,1,{kind="Research",technology="Mining"})
    local legacy=Game.serialize(s); legacy.state.players[1].research={id="Mining",cost=14,progress=13}
    assert(Save.valid(legacy))
    local restored=Game.restore(legacy) :: any; local direct=Save.restore(legacy) :: any
    local r=restored.players[1].research; local expected=rounded(14,Game.costPercent(s))
    assert(r.cost==expected and r.progress==math.floor(13*expected/14))
    assert(Canonical.encode(direct)==Canonical.encode(restored)); assert(Save.valid(Game.serialize(restored)))
end
-- The first W2-D pace is also a supported save form after the tech curve changes.
for _, turns in {45,80,200} do
    local s=founded(turns); apply(s,1,{kind="Research",technology="Mining"})
    local firstPass=Game.serialize(s)
    local oldPercent=math.clamp(math.floor(100*(turns/120)^1.5+0.5),30,200)
    local oldCost=rounded(14,oldPercent)
    firstPass.state.players[1].research={id="Mining",cost=oldCost,progress=oldCost-1}
    assert(Save.valid(firstPass),"first-pass paced save accepted")
    local restored=Game.restore(firstPass) :: any; local direct=Save.restore(firstPass) :: any
    local newCost=rounded(14,Game.costPercent(s))
    assert(restored.players[1].research.cost==newCost and restored.players[1].research.progress==math.floor((oldCost-1)*newCost/oldCost))
    assert(Canonical.encode(direct)==Canonical.encode(restored))
end
print("base cost pacing: research, production, purchase, growth, upgrades, snapshots, AI and saves passed")
