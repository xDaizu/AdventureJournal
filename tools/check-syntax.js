// Lua 5.1 syntax check for every .lua file in the addon folder (tools/ lives inside it), skipping
// node_modules and .git. Extra folders can be given as arguments, for example a sibling dev addon:
//   node check-syntax.js                 the addon (what `npm test` runs)
//   node check-syntax.js ../../AJProbe   the addon and AJProbe (in the wow-addons workspace)
const fs = require('fs');
const path = require('path');
const luaparse = require('luaparse');

const addonDir = path.resolve(__dirname, '..');
const roots = [addonDir, ...process.argv.slice(2).map((dir) => path.resolve(dir))];
const skip = new Set(['node_modules', '.git']);
const files = [];
function walk(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (skip.has(entry.name)) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full);
    else if (entry.name.endsWith('.lua')) files.push(full);
  }
}
for (const dir of roots) {
  if (!fs.existsSync(dir)) { console.log('FAIL  no such folder: ' + dir); process.exit(1); }
  walk(dir);
}

const base = path.dirname(addonDir);
let failed = 0;
for (const file of files) {
  try {
    luaparse.parse(fs.readFileSync(file, 'utf8'), { luaVersion: '5.1' });
    console.log('ok    ' + path.relative(base, file));
  } catch (err) {
    failed++;
    console.log('FAIL  ' + path.relative(base, file) + ': ' + err.message);
  }
}
if (failed) { console.log(`${failed} file(s) failed`); process.exit(1); }
