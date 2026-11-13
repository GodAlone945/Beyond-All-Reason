// Run from the repository root. Exercise the real Lua callback with a small
// Spring state stub without loading the entire BAR gadget environment.
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } =
  require(path.resolve('.preview/roguelike-validation/node_modules/fengari'));
const source = fs.readFileSync('luarules/gadgets/unit_shield_behaviour.lua', 'utf8');
const start = source.indexOf('function gadget:ShieldPreDamaged(');
const end = source.indexOf('-- Gadget interface methods', start);
if (start < 0 || end < 0) throw new Error('Shield callback not found');
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
lua.lua_pushstring(L, to_luastring(source.slice(start, end)));
lua.lua_setglobal(L, to_luastring('shieldCallbackSource'));
const test = fs.readFileSync('tools/roguelike/Test-ShieldRepulsion.lua', 'utf8');
if (lauxlib.luaL_dostring(L, to_luastring(test)) !== lua.LUA_OK) {
  throw new Error(to_jsstring(lua.lua_tostring(L, -1)));
}
