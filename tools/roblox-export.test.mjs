// SPDX-License-Identifier: MPL-2.0
// Regression coverage for source-preserving module import adaptation.
import assert from 'node:assert/strict';
import {rewriteImports} from './roblox-export.mjs';
const modules = ['map/HexMath.luau', 'map/HexCoord.luau', 'models/stats/Stats.luau'];
const rewrite = source => rewriteImports(source, 'map/HexMath.luau', modules);
assert.equal(rewrite('require("./HexCoord")'), 'require(script.Parent.HexCoord)');
assert.equal(rewriteImports("require('../../map/HexCoord')", 'models/stats/Stats.luau', modules), 'require(script.Parent.Parent.Parent.map.HexCoord)');
for (const source of [
  '-- require("./Missing")\nreturn {}',
  '--[=[ require("./Missing") ]=]\nreturn {}',
  'local text = [[require("./HexCoord")]]',
  'local text = [==[require("./Missing")]==]',
  "local text = 'require(\"./Missing\")'",
  'local text = `require("./Missing")`',
]) assert.equal(rewrite(source), source, 'Strings and comments must stay unchanged');
assert.equal(rewrite('-- ignored require("./Missing")\nlocal C = require("./HexCoord")'), '-- ignored require("./Missing")\nlocal C = require(script.Parent.HexCoord)');
assert.throws(() => rewrite("require('./Missing')"), /Unknown\/outside/);
assert.throws(() => rewrite("require('../../private/Secrets')"), /Unknown\/outside/);
assert.throws(() => rewrite('local text = [=[unterminated'), /Unterminated/);
console.log('Roblox exporter regression checks passed');
