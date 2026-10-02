--!strict
-- Generated module-only Roblox form. Source: src/models/Counter.luau
-- Source SHA-256: b10dda1f60b6d4674936e196c818bb51b8a02f794d3d125d71c8aef6ef3270da
-- Reproduce with tools/roblox-export.mjs; preserve MPL notices below.
-- Covered source: https://github.com/RoryODonovan/unciv-luau
-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- Obtain a copy at https://mozilla.org/MPL/2.0/.
--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Derived from Unciv core/src/com/unciv/models/Counter.kt
-- Upstream revision: 42939c6a2cf31aa76f44ffc033015ad12fece9f5
-- Upstream file has no individual copyright notice.
local Counter = {}

export type Entry = {key: string, value: number}
export type Value = {
    values: {[string]: number},
    order: {string},
    readOnly: boolean,
}

local function integer(value: number)
    assert(value == value and math.abs(value) < math.huge and value % 1 == 0,
        "Counter values must be finite integers")
    assert(math.abs(value) <= 9007199254740991, "Counter integer exceeds exact number range")
end

-- Ordered entries replace Kotlin's Map constructor. As upstream, constructor
-- preserves zero entries; subsequent put/add operations remove zeroed keys.
function Counter.new(entries: {Entry}?): Value
    local result: Value = {values = {}, order = {}, readOnly = false}
    for _, entry in entries or {} do
        integer(entry.value)
        if result.values[entry.key] == nil then table.insert(result.order, entry.key) end
        result.values[entry.key] = entry.value
    end
    return result
end

function Counter.get(self: Value, key: string): number
    return self.values[key] or 0
end

function Counter.containsKey(self: Value, key: string): boolean
    return self.values[key] ~= nil
end

function Counter.entries(self: Value): {Entry}
    local result = {}
    for _, key in self.order do
        table.insert(result, {key = key, value = self.values[key]})
    end
    return result
end

function Counter.removeKey(self: Value, key: string): number?
    assert(not self.readOnly, "Do not modify Counter.ZERO")
    local previous = self.values[key]
    if previous ~= nil then
        self.values[key] = nil
        local index = table.find(self.order, key)
        assert(index ~= nil, "Corrupt counter order")
        table.remove(self.order, index)
    end
    return previous
end

function Counter.put(self: Value, key: string, value: number): number?
    assert(not self.readOnly, "Do not modify Counter.ZERO")
    integer(value)
    if value == 0 then return Counter.removeKey(self, key) end
    local previous = self.values[key]
    if previous == nil then table.insert(self.order, key) end
    self.values[key] = value
    return previous
end

function Counter.add(self: Value, key: string, amount: number)
    integer(amount)
    Counter.put(self, key, Counter.get(self, key) + amount)
end

-- Snapshot handles self-subtraction without invalidating insertion-order traversal.
function Counter.addCounter(self: Value, other: Value)
    for _, entry in Counter.entries(other) do Counter.add(self, entry.key, entry.value) end
end

function Counter.remove(self: Value, other: Value)
    for _, entry in Counter.entries(other) do Counter.add(self, entry.key, -entry.value) end
end

function Counter.clone(self: Value): Value
    return Counter.new(Counter.entries(self))
end

function Counter.times(self: Value, multiplier: number): Value
    integer(multiplier)
    local result = Counter.new()
    for _, key in self.order do
        Counter.put(result, key, Counter.get(self, key) * multiplier)
    end
    return result
end

function Counter.plus(self: Value, other: Value): Value
    local result = Counter.clone(self)
    Counter.addCounter(result, other)
    return result
end

function Counter.sumValues(self: Value): number
    local sum = 0
    for _, key in self.order do
        sum += self.values[key]
        integer(sum)
    end
    return sum
end

local zero = Counter.new()
zero.readOnly = true
table.freeze(zero.values)
table.freeze(zero.order)
Counter.ZERO = table.freeze(zero) :: Value
return table.freeze(Counter)
