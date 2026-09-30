--!strict
-- Generated module-only Roblox form. Source: src/map/HexMath.luau
-- Source SHA-256: b89c7345567eae10a9762d56e4c3ee64720ffd74fb1c391b06f65548dad30892
-- Reproduce with tools/roblox-export.mjs; preserve MPL notices below.
-- Covered source: https://github.com/RoryODonovan/unciv-luau
-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- Obtain a copy at https://mozilla.org/MPL/2.0/.
--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Derived from Unciv by Yair Morgenstern and contributors.
-- Upstream: core/src/com/unciv/logic/map/HexMath.kt
-- Revision: 42939c6a2cf31aa76f44ffc033015ad12fece9f5
-- https://github.com/yairm210/Unciv/blob/42939c6a2cf31aa76f44ffc033015ad12fece9f5/core/src/com/unciv/logic/map/HexMath.kt
local HexCoord = require(script.Parent.HexCoord)
type Coord = HexCoord.Coord
export type Vector = { x: number, y: number }
local HexMath = {}

local function trunc(value: number): number
    return if value < 0 then math.ceil(value) else math.floor(value)
end

-- Kotlin round(Float) uses ties to even, unlike roundToInt (ties toward +infinity).
local function roundEven(value: number): number
    local floor = math.floor(value)
    local fraction = value - floor
    if fraction < 0.5 then return floor end
    if fraction > 0.5 then return floor + 1 end
    return if floor % 2 == 0 then floor else floor + 1
end

function HexMath.getVectorForAngle(angle: number): Vector
    return { x = math.sin(angle), y = math.cos(angle) }
end

function HexMath.getNumberOfTilesInHexagon(size: number): number
    return if size < 0 then 0 else 1 + 3 * size * (size + 1)
end

function HexMath.getHexagonalRadiusForArea(numberOfTiles: number): number
    return if numberOfTiles < 1 then 0 else (math.sqrt(12 * numberOfTiles - 3) - 3) / 6
end

function HexMath.getLatitude(coord: Coord): number
    return coord.x + coord.y
end

function HexMath.getLongitude(coord: Coord): number
    return coord.x - coord.y
end

function HexMath.hexFromLatLong(latitude: number, longitude: number): Vector
    local y = (latitude - longitude) / 2
    return { x = longitude + y, y = y }
end

function HexMath.worldFromLatLong(vector: Vector, tileRadius: number): Vector
    return { x = -vector.x * tileRadius * 1.5, y = vector.y * tileRadius * math.sqrt(3) * 0.5 }
end

function HexMath.getEquivalentRectangularSize(size: number, ratio: number?): Coord
    if size < 0 then return HexCoord.Zero end
    local r = ratio or 0.65
    assert(r > 0 and r < math.huge, "ratio must be finite and positive")
    local width = math.floor(math.sqrt(HexMath.getNumberOfTilesInHexagon(size) / r) + 0.5)
    return HexCoord.of(width, math.floor(width * r + 0.5))
end

function HexMath.getEquivalentHexagonalRadius(width: number, height: number): number
    return math.floor(HexMath.getHexagonalRadiusForArea(width * height) + 0.5)
end

-- x is 10 o'clock and y is 2 o'clock, as in Unciv (not generic axial coordinates).
function HexMath.hex2WorldCoords(coord: Coord): Vector
    return { x = 1.5 * (coord.y - coord.x), y = math.sqrt(3) * 0.5 * (coord.x + coord.y) }
end

function HexMath.world2HexCoords(world: Vector): Vector
    local latitude = world.y * 2 / math.sqrt(3)
    local column = world.x / 1.5
    return { x = (latitude - column) / 2, y = (latitude + column) / 2 }
end

function HexMath.getRow(coord: Coord): number
    return trunc((coord.x + coord.y) / 2)
end

function HexMath.getColumn(coord: Coord): number
    return coord.y - coord.x
end

function HexMath.getTileCoordsFromColumnRow(column: number, row: number): Coord
    local twoRows = row * 2
    if math.abs(column) % 2 == 1 then twoRows += 1 end
    return HexCoord.of(trunc((twoRows - column) / 2), trunc((twoRows + column) / 2))
end

function HexMath.roundHexCoords(coord: Vector): Vector
    local x, y, z = coord.y - coord.x, coord.x, -coord.y
    local rx, ry, rz = roundEven(x), roundEven(y), roundEven(z)
    local dx, dy, dz = math.abs(rx - x), math.abs(ry - y), math.abs(rz - z)
    if dx > dy and dx > dz then
        rx = -ry - rz
    elseif dy > dz then
        ry = -rx - rz
    else
        rz = -rx - ry
    end
    return { x = ry, y = -rz }
end

function HexMath.getUnwrappedNearestTo(coord: Coord, reference: Coord, longitudinalRadius: number): Vector
    assert(longitudinalRadius > 0 and longitudinalRadius % 1 == 0, "longitudinalRadius must be a positive integer")
    local referenceLong = HexMath.getLongitude(reference)
    local longitude = (HexMath.getLongitude(coord) - referenceLong + longitudinalRadius)
        % (longitudinalRadius * 2) - longitudinalRadius + referenceLong
    return HexMath.hexFromLatLong(HexMath.getLatitude(coord), longitude)
end

function HexMath.getHexCoordsAtDistance(origin: Coord, distance: number, maxDistance: number, worldWrap: boolean): {Coord}
    if distance == 0 then return { HexCoord.cpy(origin) } end
    local vectors: {Coord} = {}
    local current = HexCoord.minus(origin, HexCoord.of(distance, distance))
    local function appendOpposite()
        table.insert(vectors, HexCoord.minus(HexCoord.times(origin, 2), current))
    end
    for _ = 1, distance do
        table.insert(vectors, current)
        appendOpposite()
        current = HexCoord.plusXY(current, 1, 0)
    end
    for _ = 1, distance do
        table.insert(vectors, current)
        if not worldWrap or distance ~= maxDistance then appendOpposite() end
        current = HexCoord.plusXY(current, 1, 1)
    end
    for i = 0, distance - 1 do
        table.insert(vectors, current)
        if not worldWrap or distance ~= maxDistance or i ~= 0 then appendOpposite() end
        current = HexCoord.plusXY(current, 0, 1)
    end
    return vectors
end

function HexMath.getHexCoordsInDistance(origin: Coord, distance: number, worldWrap: boolean): {Coord}
    local result: {Coord} = {}
    for ring = 0, distance do
        for _, coord in HexMath.getHexCoordsAtDistance(origin, ring, distance, worldWrap) do
            table.insert(result, coord)
        end
    end
    return result
end

function HexMath.getDistanceXY(originX: number, originY: number, destinationX: number, destinationY: number): number
    local x, y = originX - destinationX, originY - destinationY
    return if x * y >= 0 then math.max(math.abs(x), math.abs(y)) else math.abs(x) + math.abs(y)
end

function HexMath.getDistance(origin: Coord, destination: Coord): number
    return HexMath.getDistanceXY(origin.x, origin.y, destination.x, destination.y)
end

-- Vector2 overload in Kotlin truncates fractional components toward zero first.
function HexMath.getDistanceVector(origin: Vector, destination: Vector): number
    return HexMath.getDistanceXY(trunc(origin.x), trunc(origin.y), trunc(destination.x), trunc(destination.y))
end

local clockCoords: {[number]: Coord} = {
    [0] = HexCoord.of(1, 1), [12] = HexCoord.of(1, 1), [2] = HexCoord.of(0, 1),
    [4] = HexCoord.of(-1, 0), [6] = HexCoord.of(-1, -1),
    [8] = HexCoord.of(0, -1), [10] = HexCoord.of(1, 0),
}
function HexMath.getClockPositionToHexcoord(clockPosition: number): Coord
    return clockCoords[clockPosition] or HexCoord.Zero
end

function HexMath.getZeroBasedIndex(x: number, y: number): number
    if x == 0 and y == 0 then return 0 end
    local ring = HexMath.getDistanceXY(0, 0, x, y)
    local ringStart = 1 + 3 * ring * (ring - 1)
    local position: number
    if ring == y then position = x
    elseif ring == x then position = ring + 1 + y
    elseif ring == -x then position = 2 * ring + 1 - y
    elseif ring == -y then position = 3 * ring + 2 - x
    elseif ring == x - y then position = 4 * ring + 1 + x
    elseif ring == y - x then position = 5 * ring + y
    else error("Expected integer hex coordinates") end
    return ringStart + position
end

return table.freeze(HexMath)
