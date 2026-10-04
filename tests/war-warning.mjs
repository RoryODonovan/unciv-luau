// SPDX-License-Identifier: MPL-2.0
// Run seat-neutral diplomacy fixtures against internal AI steps in a disposable copy, as balance-sim does.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
const root=process.cwd();
const temp=fs.mkdtempSync(path.join(os.tmpdir(),'unciv-luau-war-warning-'));
try {
  fs.cpSync(path.join(root,'src'),path.join(temp,'src'),{recursive:true});
  const module=path.join(temp,'src/simulation/BaseGame.luau');
  const source=fs.readFileSync(module,'utf8');
  const marker='return table.freeze(BaseGame)';
  if(!source.includes(marker))throw new Error('missing BaseGame export');
  fs.writeFileSync(module,source.replace(marker,'BaseGame._internal={ai=ai,refreshVision=refreshVision}\n'+marker));
  fs.mkdirSync(path.join(temp,'tests/unit'),{recursive:true});
  fs.copyFileSync(path.join(root,'tests/unit/base-war-warning.luau'),path.join(temp,'tests/unit/base-war-warning.luau'));
  const result=spawnSync(process.env.LUAU_BIN??'luau',['tests/unit/base-war-warning.luau','-a','internal'],{cwd:temp,stdio:'inherit',windowsHide:true});
  if(result.error)throw result.error;
  process.exitCode=result.status??1;
} finally { fs.rmSync(temp,{recursive:true,force:true}); }
