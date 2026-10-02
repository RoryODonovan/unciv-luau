--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Original deterministic legal-command winning replay for synthetic rules, seed 1.
local replay = {
    {kind="FoundCity",unitId=1}, {kind="Research",technology="Agriculture"},
    {kind="MoveUnit",unitId=2,tileId=6}, {kind="MoveUnit",unitId=2,tileId=11}, {kind="EndTurn"},
    {kind="MoveUnit",unitId=2,tileId=18}, {kind="MoveUnit",unitId=2,tileId=25}, {kind="EndTurn"},
    {kind="MoveUnit",unitId=2,tileId=25}, {kind="EndTurn"}, {kind="MoveUnit",unitId=2,tileId=25}, {kind="EndTurn"},
    {kind="Research",technology="BronzeWorking"}, {kind="MoveUnit",unitId=2,tileId=31},
    {kind="MoveUnit",unitId=4,tileId=6}, {kind="MoveUnit",unitId=4,tileId=11}, {kind="EndTurn"},
    {kind="MoveUnit",unitId=4,tileId=18}, {kind="MoveUnit",unitId=4,tileId=25}, {kind="EndTurn"},
    {kind="MoveUnit",unitId=4,tileId=31}, {kind="EndTurn"}, {kind="MoveUnit",unitId=4,tileId=31}, {kind="EndTurn"},
    {kind="MoveUnit",unitId=4,tileId=31}, {kind="MoveUnit",unitId=5,tileId=6}, {kind="MoveUnit",unitId=5,tileId=11}, {kind="EndTurn"},
    {kind="Research",technology="Writing"}, {kind="MoveUnit",unitId=4,tileId=31},
}
return replay
