# ARM electric orb prototype

The electric orb is a Roguelike-only ARM shop weapon. It uses a native Cannon projectile at slot 13; the existing ARM auxiliary `AimFromWeapon`, `AimWeapon`, `FireWeapon`, and `QueryWeapon` callbacks provide aiming, purchase gating and the muzzle. The original primary weapon remains in slot 1. The personal shield moves to slot 14. Normal BAR does not install the orb.

The projectile definition is `unitbasedefs/roguelike_electric_orb.lua`. It uses the Cannon's native plasma-ball sprite with an explicit size of 27 (50% larger than the previous size of 18) and blue color. `effects/roguelike_electric_orb.lua` adds a faint lightning halo and conduction sparks so the sphere remains visible. The impact reuses `genericshellexplosion-small-lightning`. Visual appearance requires an in-game check.

Buying `electric_orb` in the ARM shop sets the commander's own `roguelike_shop_electric_orb_level` and enables the slot. `shopProjectileEffects.electric_orb` registers each native projectile with the Weapon Effects gadget. On its first valid damage event, `chain` rolls an 18% chance, observes its 12-frame per-owner cooldown and two-target cap, then deals 45% and 32% of the base orb damage to nearby enemies within 230 elmos. Existing damage multipliers apply through the usual damage callback. The chain is extra damage, not new child projectiles; it does not test impact splitting of a physical projectile.

## Verification

Run `node tools/roguelike/Validate-Sources.cjs`, then the Fengari simulations `tools/roguelike/Test-ArmShopWeapons.lua` and `tools/roguelike/Test-WeaponEffects.lua`. They check mode isolation, slot registration, projectile visuals, chain damage, probability boundary, cooldown and duplicate-hit protection. They do not prove Recoil visual rendering or collision behavior.

In a fresh ARM Roguelike match, buy Electric Orb and confirm slot 13 fires a visible sphere from the hand muzzle. Fire at an isolated target to verify 120 base direct damage, then at a group with at least two nearby enemies to observe chain probability, target selection, sparks and health changes. Confirm the orb remains disabled before purchase and that two players on separate Teams cannot share an unlock or cooldown. Also test an ordinary BAR match for unchanged ARM weapons. A later main-weapon replacement can use this baseline.
