// Runs the AdventureJournal scenario under fengari with stubbed WoW globals.
//   node run.js            print the reports
//   node run.js --update   write them to expected/
//   node run.js --check    compare with expected/ (exit 1 on any difference)
// Each scenario runs once per flavor ("classic", "forever"), in up to three modes,
// each on top of the SavedVariables the previous mode produced:
//   login    a fresh login (no saved data)
//   reload   a /reload (continues the current jornada)
//   relogin  a second real login (starts a new jornada)
//   adventurejournal          normal play (the M0 smoke test, scripted)
//   adventurejournal_secrets  the same kind of session with secret values, in an
//                             instance, plus /diario diag and /diario debug
//   adventurejournal_migration  a diary saved by the pre-M4 addon (schema v1)
//   adventurejournal_options  every M5 option (panel and slash commands), persistence across
//                             reload and relogin, the AddonCompartment function
//   adventurejournal_bigdiary a generated diary of 250 jornadas, bounded frame count in the index
//   adventurejournal_import_* M4b: /diario importar against a synthetic AJProbeDB (empty diary, a diary
//                             whose jornadas overlap the log, AJProbe not installed)
//   adventurejournal_conversations M4b: the opt-in RP conversation log, live
//   adventurejournal_chemadiary T1: a diary saved by Chema's Forever line, and a round trip through it
// A scenario can set `variant`, read by the scenario file as H.variant, to run one file in several setups.
// A scenario can set `stub`: comma-separated STUB_OPTIONS for tools/lua/stubs.lua (see its header),
// e.g. a client without the Settings API or without ScrollBox templates (the fallback paths).
// Pin the time zone so os.date output is the same on every machine.
process.env.TZ = 'UTC';
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');

// tools/ lives inside the addon folder, so the addon is the parent directory.
const addonName = 'AdventureJournal';
const addonDir = path.resolve(__dirname, '..');
const root = addonDir;
const luaDir = path.join(__dirname, 'lua');
const expectedDir = path.join(__dirname, 'expected');

const SCENARIOS = [
  { name: 'adventurejournal', file: 'scenario_adventurejournal.lua', modes: ['login', 'reload', 'relogin'] },
  { name: 'adventurejournal_secrets', file: 'scenario_secrets.lua', modes: ['login', 'reload'] },
  { name: 'adventurejournal_migration', file: 'scenario_migration.lua', modes: ['login'] },
  { name: 'adventurejournal_options', file: 'scenario_options.lua', modes: ['login', 'reload', 'relogin'] },
  { name: 'adventurejournal_options_nosettings', file: 'scenario_options.lua', modes: ['login'], stub: 'nosettings' },
  { name: 'adventurejournal_options_opentoobject', file: 'scenario_options.lua', modes: ['login'], stub: 'opentoobject' },
  { name: 'adventurejournal_bigdiary', file: 'scenario_bigdiary.lua', modes: ['login'] },
  { name: 'adventurejournal_bigdiary_noscrollbox', file: 'scenario_bigdiary.lua', modes: ['login'], stub: 'noscrollbox' },
  { name: 'adventurejournal_bigdiary_notemplates', file: 'scenario_bigdiary.lua', modes: ['login'], stub: 'noscrolltemplates' },
  { name: 'adventurejournal_import_empty', file: 'scenario_import.lua', modes: ['login'], variant: 'empty' },
  { name: 'adventurejournal_import_overlap', file: 'scenario_import.lua', modes: ['login'], variant: 'overlap' },
  { name: 'adventurejournal_import_notimetable', file: 'scenario_import.lua', modes: ['login'], variant: 'notimetable', stub: 'notimetable' },
  { name: 'adventurejournal_import_noprobe', file: 'scenario_import.lua', modes: ['login'], variant: 'noprobe' },
  // M6: the entry types added after M5, live. off_with / off_without must leave identical diaries (sameDiaryAs).
  { name: 'adventurejournal_newtypes', file: 'scenario_newtypes.lua', modes: ['login', 'reload', 'relogin'], variant: 'live' },
  { name: 'adventurejournal_newtypes_secrets', file: 'scenario_newtypes.lua', modes: ['login'], variant: 'secrets' },
  { name: 'adventurejournal_newtypes_nomessages', file: 'scenario_newtypes.lua', modes: ['login'], variant: 'live', stub: 'nomessages' },
  { name: 'adventurejournal_newtypes_off_without', file: 'scenario_newtypes.lua', modes: ['login'], variant: 'off_without' },
  { name: 'adventurejournal_newtypes_off_with', file: 'scenario_newtypes.lua', modes: ['login'], variant: 'off_with', sameDiaryAs: 'adventurejournal_newtypes_off_without' },
  { name: 'adventurejournal_importnew_types', file: 'scenario_importnew.lua', modes: ['login'], variant: 'types' },
  { name: 'adventurejournal_importnew_off_without', file: 'scenario_importnew.lua', modes: ['login'], variant: 'off_without' },
  { name: 'adventurejournal_importnew_off_with', file: 'scenario_importnew.lua', modes: ['login'], variant: 'off_with', sameDiaryAs: 'adventurejournal_importnew_off_without' },
  { name: 'adventurejournal_conversations', file: 'scenario_conversations.lua', modes: ['login', 'reload', 'relogin'] },
  { name: 'adventurejournal_conversations_nosocial', file: 'scenario_conversations.lua', modes: ['login'], stub: 'nosocial' },
  // T1: diaries written by Chema's Forever line (1.1.0-Forever): migration, the "clasico" profile, round trip.
  { name: 'adventurejournal_chemadiary', file: 'scenario_chemadiary.lua', modes: ['login', 'reload', 'relogin'], variant: 'chema' },
  { name: 'adventurejournal_chemadiary_roundtrip', file: 'scenario_chemadiary.lua', modes: ['login'], variant: 'roundtrip' },
];

const MODE_TITLES = { login: 'fresh login', reload: '/reload', relogin: 'second login' };

const mode = process.argv.includes('--update') ? 'update'
           : process.argv.includes('--check') ? 'check' : 'print';

// Pick the TOC for a flavor, falling back to the plain TOC (pre-M1 layout).
function tocFor(flavor) {
  const suffix = flavor === 'classic' ? '_Vanilla' : '_Forever';
  for (const name of [`${addonName}${suffix}.toc`, `${addonName}.toc`]) {
    const p = path.join(addonDir, name);
    if (fs.existsSync(p)) return p;
  }
  throw new Error('No TOC found for ' + flavor);
}

// The value of "## AddonCompartmentFunc:" in a TOC, or '' when the field is absent.
function tocCompartmentFunc(tocPath) {
  const match = fs.readFileSync(tocPath, 'utf8').match(/^##\s*AddonCompartmentFunc:\s*(\S+)/m);
  return match ? match[1] : '';
}

function tocFiles(tocPath) {
  return fs.readFileSync(tocPath, 'utf8').split(/\r?\n/)
    .map((l) => l.trim().replace(/\s*\[.*\]$/, ''))
    .filter((l) => l && !l.startsWith('#') && l.endsWith('.lua'));
}

function runOnce(scenario, flavor, runMode, presetDb) {
  const reload = runMode === 'reload';
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const set = (name, value) => { lua.lua_pushstring(L, to_luastring(value)); lua.lua_setglobal(L, to_luastring(name)); };
  const setBool = (name, value) => { lua.lua_pushboolean(L, value); lua.lua_setglobal(L, to_luastring(name)); };
  set('FLAVOR', flavor);
  set('ADDON_NAME', addonName);
  set('ADDON_DIR', addonDir.replace(/\\/g, '/'));
  set('ADDON_FILES', tocFiles(tocFor(flavor)).join('\n'));
  set('SCENARIO', path.join(luaDir, scenario.file).replace(/\\/g, '/'));
  set('PRESET_DB', presetDb || '');
  set('STUB_OPTIONS', scenario.stub || '');
  set('VARIANT', scenario.variant || '');
  set('TOC_COMPARTMENT_FUNC', tocCompartmentFunc(tocFor(flavor)));
  setBool('RELOAD', reload);
  set('MODE', runMode);
  for (const file of ['stubs.lua', 'driver.lua']) {
    const status = lauxlib.luaL_dofile(L, to_luastring(path.join(luaDir, file)));
    if (status !== 0) throw new Error(`${scenario.name} ${flavor} ${runMode} (${file}): ` + to_jsstring(lua.lua_tostring(L, -1)));
  }
  const get = (name) => { lua.lua_getglobal(L, to_luastring(name)); return to_jsstring(lua.lua_tostring(L, -1)); };
  return { output: get('OUTPUT'), db: get('DB_DUMP') };
}

// ONLY=<regex> runs just the matching scenarios (handy while writing one).
const only = process.env.ONLY ? new RegExp(process.env.ONLY) : null;

let failed = 0;
const finalDiaries = {};   // [scenario name + flavor] = the saved diary after the last mode, for sameDiaryAs
for (const scenario of SCENARIOS) {
  if (only && !only.test(scenario.name)) continue;
  for (const flavor of ['classic', 'forever']) {
    let preset = '';
    const parts = [];
    for (const runMode of scenario.modes) {
      const result = runOnce(scenario, flavor, runMode, preset);
      preset = result.db;
      parts.push(`##### ${flavor}: ${MODE_TITLES[runMode]} #####\n${result.output}`);
    }
    const report = parts.join('\n');
    const label = `${scenario.name}_${flavor}`;
    finalDiaries[label] = preset;
    if (scenario.sameDiaryAs) {
      const other = `${scenario.sameDiaryAs}_${flavor}`;
      if (finalDiaries[other] !== preset) {
        failed++;
        console.log(`FAIL  ${label}: the saved diary differs from ${other} (they must be identical)`);
        fs.writeFileSync(path.join(__dirname, `actual_${label}_diary.txt`), preset, 'utf8');
        fs.writeFileSync(path.join(__dirname, `actual_${other}_diary.txt`), finalDiaries[other] || '', 'utf8');
      } else {
        console.log(`ok    ${label} has the same saved diary as ${other}`);
      }
    }
    const file = path.join(expectedDir, `${label}.txt`);
    if (mode === 'update') {
      fs.mkdirSync(expectedDir, { recursive: true });
      fs.writeFileSync(file, report, 'utf8');
      console.log('wrote ' + path.relative(root, file));
    } else if (mode === 'check') {
      const expected = fs.existsSync(file) ? fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n') : null;
      if (expected === report) console.log('ok    ' + label);
      else {
        failed++;
        const actualFile = path.join(__dirname, `actual_${label}.txt`);
        fs.writeFileSync(actualFile, report, 'utf8');
        console.log(`FAIL  ${label}: differs from expected/ (see ${path.relative(root, actualFile)}; diff it against ${path.relative(root, file)})`);
      }
    } else {
      console.log(report);
    }
  }
}
if (failed) process.exit(1);
