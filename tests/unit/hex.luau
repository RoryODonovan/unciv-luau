--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Index uniqueness and formatting scenarios adapted from Unciv HexmathTests.kt.
-- Revision: 42939c6a2cf31aa76f44ffc033015ad12fece9f5
local C = require("../../src/map/HexCoord")
local H = require("../../src/map/HexMath")
local checks = 0
local function check(condition: boolean, label: string)
    assert(condition, label)
    checks += 1
end
local function equal(actual: number, expected: number)
    check(actual == expected, tostring(actual) .. " ~= " .. tostring(expected))
end
local function coord(actual: C.Coord, x: number, y: number)
    check(C.eq(actual, x, y), C.toPrettyString(actual) .. " unexpected")
end
local function near(actual: number, expected: number)
    check(math.abs(actual - expected) < 1e-9, "Floating coordinate mismatch")
end

equal(H.getDistance(C.of(3, 3), C.Zero), 3)
equal(H.getDistance(C.of(3, -2), C.Zero), 5)
equal(H.getDistance(C.of(-3, -2), C.Zero), 3)
equal(H.getDistanceVector({ x = -1.9, y = 0.9 }, { x = 0, y = 0 }), 1)
equal(H.getRow(C.of(-1, 0)), 0)
equal(H.getRow(C.of(-3, 0)), -1)
coord(H.getTileCoordsFromColumnRow(-1, -1), 0, -1)
coord(H.getTileCoordsFromColumnRow(1, -1), -1, 0)
coord(H.getTileCoordsFromColumnRow(0, -1), -1, -1)

local expectedNeighbors = {{-1,-1},{1,1},{0,-1},{0,1},{1,0},{-1,0}}
for i, actual in H.getHexCoordsAtDistance(C.Zero, 1, 1, false) do
    coord(actual, expectedNeighbors[i][1], expectedNeighbors[i][2])
end
for hour, expected in { [0]={1,1}, [2]={0,1}, [4]={-1,0}, [6]={-1,-1}, [8]={0,-1}, [10]={1,0}, [12]={1,1} } do
    coord(H.getClockPositionToHexcoord(hour), expected[1], expected[2])
end
coord(H.getClockPositionToHexcoord(3), 0, 0)
equal(H.getZeroBasedIndex(0, 0), 0)

local indices: {[number]: boolean} = {}
for ring = 1, 100 do
    local cells = H.getHexCoordsAtDistance(C.Zero, ring, 100, false)
    equal(#cells, 6 * ring)
    local start = 1 + 3 * ring * (ring - 1)
    local seen: {[string]: boolean} = {}
    for _, cell in cells do
        equal(H.getDistance(cell, C.Zero), ring)
        local key = C.toPrettyString(cell)
        check(not seen[key], "Duplicate ring coordinate")
        seen[key] = true
        local index = H.getZeroBasedIndex(cell.x, cell.y)
        check(not indices[index], "Duplicate upstream index")
        check(index >= start and index < start + 6 * ring, "Index outside ring")
        indices[index] = true
    end
end
for radius = 0, 8 do
    equal(#H.getHexCoordsInDistance(C.of(4, -2), radius, false), H.getNumberOfTilesInHexagon(radius))
    near(H.getHexagonalRadiusForArea(H.getNumberOfTilesInHexagon(radius)), radius)
    if radius > 0 then
        equal(#H.getHexCoordsAtDistance(C.Zero, radius, radius, true), 5 * radius - 1)
    end
end
equal(#H.getHexCoordsAtDistance(C.Zero, -1, 3, false), 0)
equal(#H.getHexCoordsInDistance(C.Zero, -1, false), 0)
equal(H.getNumberOfTilesInHexagon(-1), 0)

for x = -12, 12 do
    for y = -12, 12 do
        local value = C.of(x, y)
        local parsed = C.fromString(C.toPrettyString(value))
        check(C.equals(value, parsed), "Format/parse mismatch")
        local latLong = H.hexFromLatLong(H.getLatitude(value), H.getLongitude(value))
        coord(latLong, x, y)
        local world = H.hex2WorldCoords(value)
        local back = H.world2HexCoords(world)
        near(back.x, x)
        near(back.y, y)
        coord(H.roundHexCoords(back), x, y)
    end
end
coord(H.roundHexCoords({x=0.5,y=0}), 0, 0)
coord(H.roundHexCoords({x=-0.5,y=0}), 0, 0)
coord(H.roundHexCoords({x=1.5,y=0}), 2, 0)
coord(H.roundHexCoords({x=-1.5,y=0}), -2, 0)
coord(H.roundHexCoords({x=0.5,y=0.5}), 0, 0)
near(H.hex2WorldCoords(C.of(1,0)).x, -1.5)
near(H.hex2WorldCoords(C.of(0,1)).x, 1.5)
near(H.hex2WorldCoords(C.of(1,1)).y, math.sqrt(3))
coord(H.getUnwrappedNearestTo(C.of(-4,4), C.Zero, 5), 1, -1)
coord(H.getUnwrappedNearestTo(C.of(4,-4), C.Zero, 5), -1, 1)
coord(C.plus(C.of(2,-1), C.of(-3,2)), -1, 1)
coord(C.minus(C.of(2,-1), C.of(-3,2)), 5, -3)
coord(C.times(C.of(-2,3), -2), 4, -6)
check(not pcall(C.fromString, "(1.5,2)"), "Fractional coordinate parsed")
check(not pcall(C.fromString, "(1, 2)"), "Whitespace coordinate parsed")
check(not pcall(C.of, 0.5, 0), "Fractional coordinate accepted")
check(not pcall(C.of, 2147483648, 0), "Out of range coordinate accepted")
check(not pcall(function() (C.Zero :: any).x = 1 end), "Coordinate was mutable")
check(not pcall(H.getUnwrappedNearestTo, C.Zero, C.Zero, 0), "Zero wrap radius accepted")
print("hex: " .. checks .. " checks passed")

