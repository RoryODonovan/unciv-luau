--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Provenance-Kind: original
-- Original shared territory sight, exploration and bilateral contact reconciliation.
local WorldMap=require("./WorldMap")
local BaseVision={}
function BaseVision.nearby(map: any, tileId: number, radius: number): {number}
    map.nearby=map.nearby or {}; map.nearbyOrder=map.nearbyOrder or {}
    local key=tostring(tileId)..":"..tostring(radius)
    if map.nearby[key] then return map.nearby[key] end
    if #map.nearbyOrder==64 then map.nearby[table.remove(map.nearbyOrder,1)]=nil end
    local ids=WorldMap.range(map,tileId,radius); map.nearby[key]=ids; table.insert(map.nearbyOrder,key); return ids
end
function BaseVision.visible(s: any, map: any, owner: number): {[number]: boolean}
    local centers = {}; for _, u in s.units do if u.ownerId == owner then table.insert(centers, u.tileId) end end
    for _, c in s.cities do if c.ownerId == owner then table.insert(centers, c.tileId) end end
    local set: {[number]: boolean} = {}; for _, center in centers do for _, id in BaseVision.nearby(map,center,2) do set[id]=true end end
    -- Civ V territory sight: owned tiles and their adjacent ring, without a distance-row search.
    local neighbors=map.neighbors
    for _, tile in s.tiles do if tile.ownerId==owner then
        set[tile.id]=true
        for _, id in neighbors[tile.id] do set[id]=true end
    end end
    return set
end
-- Returns true only for newly established contact. The caller owns event emission.
function BaseVision.contact(s: any, owner: number, seen: {[number]: boolean}): boolean
    if s.diplomacy.met then return false end
    local other=3-owner
    for _, entities in {s.units,s.cities} do
        for _, entity in entities do
            if entity.ownerId==other and seen[entity.tileId] then
                s.diplomacy.met=true
                return true
            end
        end
    end
    return false
end
-- Commands supply the normal Contact event callback; restore leaves event history untouched.
function BaseVision.refresh(s: any, map: any, onContact: (() -> ())?)
    for owner=1,2 do
        local discovered: {[number]: boolean} = {}; for _, id in s.players[owner].explored do discovered[id] = true end
        local seen=BaseVision.visible(s,map,owner)
        if BaseVision.contact(s,owner,seen) and onContact then onContact() end
        for id in seen do discovered[id] = true end
        local ids = {}; for id in discovered do table.insert(ids,id) end; table.sort(ids); s.players[owner].explored = ids
    end
end
return table.freeze(BaseVision)
