# Roguelike multishot: ARM projectile prototype

## Call chain and changed files

`roguelike_unit_tweaks.lua` installs ARM shop weapon `plasma_weapon` at slot 6. The engine fires its native Cannon projectile from the piece returned by `armcom_lus.lua:QueryWeapon`. `game_roguelike_multishot.lua:ProjectileCreated` observes that native projectile, reads the firing commander's personal upgrade count, and spawns the other projectiles immediately using the same WeaponDef, owner, team, position and ballistic speed. The native projectile is the centre shot. Existing `game_roguelike_upgrades.lua:UnitPreDamaged` processes each resulting collision using the existing per-player damage multiplier. No reload or burst field is changed.

| File | Change |
| --- | --- |
| `unitbasedefs/roguelike_multishot.lua` | Explicit `armcom` / `plasma_weapon` allowlist, angle and budget. |
| `luarules/gadgets/game_roguelike_multishot.lua` | Synced projectile creation and recursion guard. |
| `luarules/gadgets/game_roguelike_upgrades.lua` | Personal shop levels and projectile-count RulesParam. |
| `luaui/RmlWidgets/gui_roguelike/gui_roguelike.lua` | ARM-only shop item. |
| `tools/roguelike/Test-Multishot.lua` | Standalone callback simulation. |

`projectiles=0` with a script fire callback has **not** been established on Recoil. This prototype keeps the native centre projectile. Do not switch to full Lua spawning until a live test confirms the callback fires with `projectiles=0`. Normal BAR does not load the Gadget or shop changes because both are gated by `roguelike_mode`.

## Compatibility risks

- The copied Tzar Cannon has a large area of effect. Several projectiles may hit one target, and each can also affect nearby targets. The existing plasma extension Gadget may run its extra effect once per projectile. Measure this interaction before expanding the allowlist.
- The native projectile's first `ProjectileCreated` position is used as the shared origin. Confirm visually and through projectile telemetry that this is the actual muzzle position on the installed Recoil build.
- The horizontal directions use `GetUnitWeaponVectors` and the native projectile's speed; the vertical velocity comes from the native ballistic shot. Confirm trajectories at close and maximum range, particularly on slopes.
- The sixteen-extra-projectile frame budget accommodates two commanders at nine shots each. A third qualifying shooter in the same frame would be capped; phase one permits only two player Teams.
- `SpawnProjectile` inherits the WeaponDef's full damage and collision settings. The mock verifies parameters and damage arithmetic, but only live engine testing can establish collision, shields, armor classes and actual HP loss.

## Standalone regression

From the repository root:

```powershell
node tools/roguelike/Validate-Sources.cjs
.preview\roguelike-validation\node_modules\.bin\fengari.cmd tools/roguelike/Test-Multishot.lua
```

The simulation covers disabled mode, counts 1/3/5/7/9, symmetric 4-degree offsets, identical frame and origin, unchanged WeaponDef damage, additive same-target HP arithmetic, repeat event suppression, explicit allowlist, separate Teams, immediate count changes and two nine-shot volleys in one frame.

## Live acceptance checklist

Use a fresh Roguelike match with ARM, then a two-player match with separate allied Teams. Record `ProjectileCreated` frame, owner, WeaponDef, position and velocity for each volley, plus target HP before and after impact.

1. Unlock Tzar Heavy Cannon and buy Multishot levels 0 through 4. At each level confirm 1/3/5/7/9 projectiles, with the extra angles at 4-degree steps around the current aim direction. Confirm all projectile creation frames and coordinates match the native centre shot.
2. Fire one volley at an isolated high-HP target. Confirm every projectile's collision and the HP decrease from each is the full weapon damage after the existing personal damage multiplier. Repeat with a target large enough to receive multiple hits; record separate damage events. Check plasma extension levels separately.
3. Check that one native shot produces one extra volley, never a recursive volley. Measure native reload frames before and after buying Multishot. Check close range, maximum range, slopes, shield contact and targets of different armor classes.
4. In a two-player match, set each commander's upgrade to a different count and fire independently, then fire both at nine shots in the same frame. Confirm exactly 18 total projectiles, correct owner and Team for each, and no cross-player count changes.
5. Launch ordinary BAR without `roguelike_mode`; confirm the new Gadget is inactive, no Multishot shop item appears, and ARM weapon behavior is unchanged.
6. In a separate throwaway engine test, set `projectiles=0` on a copied Cannon and instrument its script fire callback. Only consider replacing the native-centre approach if that callback fires reliably in single-player and multiplayer.

Live engine acceptance is pending; the standalone test does not substitute for it.
