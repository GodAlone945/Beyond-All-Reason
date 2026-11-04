// Syntax checks only; run from the repository root. Tool dependency stays outside game content.
const fs = require('fs');
const path = require('path');
const parser = require(path.resolve('.preview/roguelike-validation/node_modules/luaparse'));
const folders = ['luarules/gadgets', 'unitbasedefs', 'weapons', 'effects', 'features',
  'units/RoguelikeDrones', 'luaui/RmlWidgets/gui_roguelike'];
const files = ['modoptions.lua', 'gamedata/alldefs_post.lua', 'modules/customcommands.lua',
  'luaui/rml_setup.lua', 'luaui/Widgets/gui_buildmenu.lua',
  'luaui/Widgets/gui_unit_stats.lua', 'scripts/Units/armcom_lus.lua',
  'luarules/gadgets/raptor_spawner_defense.lua', 'luarules/gadgets/scav_spawner_defense.lua'];
for (const folder of folders) {
  for (const file of fs.readdirSync(folder)) {
    if (file.endsWith('.lua') && (folder.includes('RoguelikeDrones') || folder.includes('gui_roguelike') || file.includes('roguelike'))) {
      files.push(`${folder}/${file}`);
    }
  }
}
let failures = 0;
for (const file of files) {
  try {
    parser.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''), { luaVersion: '5.1' });
    console.log(`PASS ${file}`);
  } catch (error) {
    failures++;
    console.log(`FAIL ${file}: ${error.message}`);
  }
}
console.log(`RESULT ${files.length - failures}/${files.length} Lua 5.1 syntax checks passed`);
process.exitCode = failures ? 1 : 0;
