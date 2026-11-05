// READ-ONLY rehearsal of `/diario importar` on real SavedVariables files, outside the game.
//   node import-dryrun.js --probe <AJProbe.lua> --diary <AdventureJournal.lua> [--flavor classic|forever] [--player Name-Realm] [--tz Europe/Madrid]
//
// It loads COPIES of the two files into the stubbed addon IN MEMORY, fires a login, plans and
// applies the import there (conversations off, then on), runs it again to prove it is idempotent,
// and prints counts only: never an entry's text and never a chat line. No file is opened for
// writing, neither of yours nor in the repo, and AJProbeDB is compared before and after.
//
// What it cannot tell: how the real client behaves (see "What the M4b stubs cannot verify" in
// README.md). --player is the character key ("Name-Realm") whose records to import; by default the key
// that appears most often in the log. The time zone must be the one the game ran in, because the records' `d` strings
// are local times: the default is this machine's, --tz overrides it.
const fs = require('fs');
const path = require('path');

const args = process.argv.slice(2);
const option = (name, fallback) => {
  const index = args.indexOf('--' + name);
  return index >= 0 && args[index + 1] ? args[index + 1] : fallback;
};
const probePath = option('probe');
const diaryPath = option('diary');
const flavor = option('flavor', 'classic');
if (!probePath || !diaryPath || !['classic', 'forever'].includes(flavor)) {
  console.error('usage: node import-dryrun.js --probe <AJProbe.lua> --diary <AdventureJournal.lua> [--flavor classic|forever] [--tz <IANA zone>]');
  process.exit(2);
}
if (option('tz')) process.env.TZ = option('tz');

const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
// tools/ lives inside the addon folder, so the addon is the parent directory.
const addonDir = path.resolve(__dirname, '..');
const luaDir = path.join(__dirname, 'lua');
const tocName = flavor === 'classic' ? 'AdventureJournal_Vanilla.toc' : 'AdventureJournal_Forever.toc';
const files = fs.readFileSync(path.join(addonDir, tocName), 'utf8').split(/\r?\n/)
  .map((l) => l.trim().replace(/\s*\[.*\]$/, '')).filter((l) => l && !l.startsWith('#') && l.endsWith('.lua'));

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const set = (name, value) => { lua.lua_pushstring(L, to_luastring(value)); lua.lua_setglobal(L, to_luastring(name)); };
set('FLAVOR', flavor);
set('ADDON_NAME', 'AdventureJournal');
set('ADDON_DIR', addonDir.replace(/\\/g, '/'));
set('ADDON_FILES', files.join('\n'));
set('SCENARIO', path.join(luaDir, 'dryrun_real.lua').replace(/\\/g, '/'));
set('PRESET_DB', '');
set('STUB_OPTIONS', '');
set('VARIANT', '');
set('TOC_COMPARTMENT_FUNC', '');
set('MODE', 'login');
lua.lua_pushboolean(L, false); lua.lua_setglobal(L, to_luastring('RELOAD'));
set('REAL_PLAYER', option('player', ''));
set('REAL_PROBE_TEXT', fs.readFileSync(probePath, 'utf8'));
set('REAL_DIARY_TEXT', fs.readFileSync(diaryPath, 'utf8'));
for (const file of ['stubs.lua', 'driver.lua']) {
  const status = lauxlib.luaL_dofile(L, to_luastring(path.join(luaDir, file)));
  if (status !== 0) { console.error(`ERROR in ${file}: ` + to_jsstring(lua.lua_tostring(L, -1))); process.exit(1); }
}
lua.lua_getglobal(L, to_luastring('OUTPUT'));
const out = to_jsstring(lua.lua_tostring(L, -1));
// The scenario log and the addon's own messages; the diary dump is switched off in the scenario.
console.log(out.split('== events registered')[0]);
console.log('== what /diario importar printed' + out.split('== chat output')[1].split('== AdventureJournalDB')[0]);
