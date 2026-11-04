# Roguelike current implementation audit

> This table is the pre-P1 source snapshot. The implementation status below records the follow-up work in this change.

Audit date: 2026-11-01. This is a source review. The user's prior local multiplayer validation applies to the deployed base game/service, not to the new effect behaviors in this change. No new effect in this audit is marked as runtime verified.

## Current state

| Area | Source and stable IDs | Status | Findings |
|---|---|---|---|
| Meteor prototype | `luarules/gadgets/game_roguelike_weapon_effects.lua`; `weapons/roguelike_meteor_payload.lua`; `CMD_ROGUELIKE_METEOR_STRIKE` | Original map-click prototype existed; P1 auto-shop path source-added, runtime unverified | Payload WeaponDef loads in Roguelike mode; only the map-click command is dev-option gated. Shop `meteor_weapon` schedules the same falling payload toward the nearest enemy within 900 elmos. It is an automatic attack source, not a spawned autonomous UnitDef. |
| Splitter prototype | `game_roguelike_weapon_effects.lua`; `roguelike_test_splitter`; effect ID `splitter` | Code exists;待实机验证 | Impact, timed and in-flight splitting; homing; damage falloff; max depth 3; max 48 active tracked projectiles per owner, 256 total and 16 spawns/frame. Split children inherit owner/team. `registerProjectile` counts all tracked projectiles on each add, and the active table is scanned each frame. |
| Faction weapon definitions | `unitbasedefs/roguelike_weapon_catalog.lua`; 12 IDs `rl_arm_*`, `rl_cor_*`, `rl_leg_*` | Code exists;待实机验证 | Catalog has effect-style attack definitions and a small number of level overrides. Current purchase level is read from `roguelike_shop_<weaponID>_level`; catalog exposes at most three shop levels. A general weapon Lv.1–6 progression was not found in the current implementation. |
| Faction attack resolution | `luarules/gadgets/game_roguelike_faction_weapons.lua`; `UnitWeaponFired`, `ProjectileCreated`, `Explosion`, `Spring.AddUnitDamage` | Code exists;待实机验证 | Synced target selection/attack styles include cone, blast, pierce, multi/hive, ramp and thermal. Most final damage is manually applied through `Spring.AddUnitDamage` with the commander and WeaponDef, preserving the existing Roguelike damage/defense path. Burn, ramp and slow are local state tables; burn and slow have cleanup but no explicit global status cap. |
| Shop and card upgrade integration | `luarules/gadgets/game_roguelike_upgrades.lua`; `SHOP_ITEMS`, `UPGRADE_POOL`, `statesByTeam` | Code exists;待实机验证 | Purchases and card effects are Synced and Team-scoped. Faction weapon ownership/levels are shop purchases; no generic effect registration or proc upgrade currently links these levels to effect data. Test meteor/splitter upgrade RulesParams are initialized only by the prototype Gadget and are not in the standard shop/card pool. |
| Multiplayer boundary | `game_roguelike_upgrades.lua`, `game_roguelike_faction_weapons.lua`, `game_roguelike_weapon_effects.lua` | Architecture exists; feature verification pending | Combat simulation is Synced. Owner Team is derived from the firing commander/projectile; upgrades live on owner RulesParams and Coop state is stored per Team. The new effects have not yet been tested with 1/2/4 clients, replay, disconnect/rebuild or late join. |
| Non-Roguelike isolation | Mod-option guards in the Roguelike Gadgets and `unitbasedefs/roguelike_unit_tweaks.lua` | Code boundary exists; regression pending | Existing gameplay Gadgets return unless `roguelike_mode` is enabled; test weapons also require a dev option. No new non-Roguelike behavior is proven without a vanilla regression match. |

## P1 implementation plan

1. Extend the existing projectile-effect prototype into the Roguelike-only effect bus. Preserve splitter projectile tracking, meteor payload and current test IDs; remove the test-only guard only from the reusable bus, while keeping prototype-only weapons/commands dev-gated.
2. Add a stable effect registry with per-effect trigger, coefficient, cooldown and budget settings. Route primary hits from the existing faction-weapon damage helper and tracked projectile impacts into it; proc-generated damage is explicitly non-proccing.
3. Add bounded chain/ricochet, kill burst, burn zone, aftershock and delayed strike. Use local unit queries and deterministic sorting; apply damage through the existing `Spring.AddUnitDamage` route so Roguelike defenses and Commander modifiers remain authoritative.
4. Attach effect unlocks/upgrades to current faction weapon level data and projectile upgrades to the existing meteor/splitter RulesParams. Do not create duplicate weapon definitions or another shop state store.
5. Add low-frequency diagnostics and record static validation, then runtime tests when a match can be run. Keep runtime evidence separate from the user's prior service/multiplayer validation.

## Known gaps and risks before runtime validation

- Meteor is currently a map-target command, not an auto-targeting independent UnitDef. The existing falling projectile can be reused as payload; targeting/scheduling needs adaptation.
- The splitter's tracked table is globally counted by iteration during registration and scanned in full on each simulation frame. Hard caps exist, but later-game cost has not been measured.
- `UnitDamaged`/`Explosion` and `Spring.AddUnitDamage` ordering must be validated in the exact deployed Recoil build. Proc damage must not re-enter itself or multiply Commander damage twice.
- Existing burn states are per owner/item/target. Area zones and shared status data require explicit per-owner/global caps and expiry cleanup.
- Test-only projectile upgrade values are not a generic projectile upgrade interface and are not currently exposed to the standard shop/card progression.
- New content is not validated for self/ally damage, shields, elites/Bosses, replay consistency, 4-player load, disconnect/reconnect, late join or performance.

## P1 implementation status (source review only, 2026-11-01)

| Area | Implementation | Runtime status |
|---|---|---|
| Shared proc registry | `unitbasedefs/roguelike_weapon_effects.lua`: stable IDs `chain`, `ricochet`, `burst`, `burn_zone`, `aftershock`, `delayed_strike`; Synced event contexts and one proc per effect per event. CEG groundflash markers are in `effects/roguelike_weapon_effects.lua` | Code present; unverified in BAR |
| Faction weapon integration | `game_roguelike_faction_weapons.lua`: existing 12 weapon IDs expose effect unlocks at their current level data and call the shared bus from the existing damage helper | Code present; scripted hit ordering and damage scaling unverified |
| Meteor payload availability | `weapons/roguelike_meteor_payload.lua`: existing payload now loads in Roguelike mode without the developer test option | Source guard corrected; WeaponDef loading unverified in BAR |
| Common projectile upgrades | Existing plasma/sniper/barrage/shockwave extension purchases unlock aftershock/delayed strike/burn zone/burst on tracked commander projectiles. Existing projectile definitions are reused; no new general projectile-level upgrade pool was added | Code present for those four shop IDs; other projectile weapons and actual upgrade balance unverified |
| Proc/status budget | Depth 1 for effect procs; 16 effect starts/frame, 4/owner/frame, 3 burn zones/owner, 12 area states/owner, 16 targets/status tick. Existing splitter remains capped at depth 3, 48/owner, 256 global, 16 projectile spawns/frame | Static caps only; CPU/sim-speed not measured |
| Meteor purchase | Shop ID `meteor_weapon` schedules the existing warning and falling payload to the nearest enemy within 900 elmos. Lv.2 adds a capped impact burn zone; levels also alter interval, radius, damage, count and split. The developer map-click command remains dev-option gated | Automatic attack source is present; it is not a spawned autonomous UnitDef. That specific interpretation remains open |
| Isolation/multiplayer | Synced Gadget returns unless `roguelike_mode` is enabled; effect values and cooldowns key to owner UnitID. Proc damage rejects allies and self-hits | Source boundary present; 1/2/4-player sync, replay and non-Roguelike regression unverified |

### P1 gaps and verification

- `ricochet` currently applies a bounded damage hit to the nearest second target; it does not create a visible redirected projectile. It is a gameplay bounce approximation.
- `burst` supports hit and kill triggers. ARM focus annihilator registers a same-frame owning-hit context and requests a 12% base chance (× its 0.6 attack proc coefficient); exact BAR `UnitDamaged`/`UnitDestroyed` callback order and attribution remain unverified.
- Automatic meteor weapon Lv.2 attaches the same bounded `burn_zone` state on impact; area visuals and damage timing are still unverified.
- The six prioritized effect families are represented in source, but this is not a complete acceptance pass. Penetrate-then-scatter is intentionally not included in the six-effect MVP.
- No BAR match, replay, multiplayer, 4-player load, or frame-time benchmark was run. Existing local service verification is not evidence for these new effects.
