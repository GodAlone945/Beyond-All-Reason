-- [UnitDef 数据：Legion 激光无人机]
-- 本文件只定义模型、移动/碰撞基础值和可用武器槽。生成、无敌维持、轨道位置、
-- 敌人选择、残骸吸收、扣电修复及升级成长均由 game_roguelike_orbit_drones.lua
-- 在 synced 端执行；不能根据这里的武器命令判断修复是否实际发生。

return {
    leg_laser_drone = {
        name                = "Laser Drone",
        description         = "Orbiting laser drone",
        maxacc              = 0.5,
        maxdec              = 0.8,
        blocking            = false,
        energycost          = 0,
        metalcost           = 0,
        builddistance       = 200,
        builder             = false,
        canfly              = true,
        canmove             = true,
        collide             = false,
        cruisealtitude      = 60,
        explodeas           = "smallexplosiongeneric-builder",
        footprintx          = 1,
        footprintz          = 1,
        health              = 500,
        maxslope            = 60,
        speed               = 300.0,
        maxwaterdepth       = 0,
        objectname          = "Units/scavboss/LEGASSISTDRONE.s3o",
        script              = "Units/LEGCA.cob",
        selfdestructas      = "smallExplosionGenericSelfd",
        sightdistance       = 800,
        turninplaceanglelimit = 360,
        turnrate            = 2400,
        hoverattack         = true,
        mass                = 100,
        collisionVolumeScales  = "1 1 1",
        collisionVolumeOffsets = "0 20 0",
        weapons = {
            { def = "LASER_DRONE_WEAPON" },
            { def = "LASER_DRONE_HEAL" },
            { def = "LASER_DRONE_PARALYZE" },
        },
        weaponDefs = {
            LASER_DRONE_WEAPON = {
                name                    = "Drone Laser Beam",
                avoidFriendly           = true,
                collideFriendly         = false,
                damage                  = {
                    default = 100,  -- 激光单发最高
                },
                fireStarter             = 50,
                impactOnly              = true,
                interceptedByShieldType = 1,
                noSelfDamage            = true,
                range                   = 400,  -- 激光射程最远
                reloadtime              = 1.5,
                size                    = 3,
                soundHit                = "weapon/laser_hit",
                soundStart              = "weapon/laser_fire",
                weaponType              = "BeamLaser",
                thickness               = 3,
                coreThickness           = 1,
                laserFlareSize          = 5,
                rgba                    = "1.0 0.1 0.1 1.0",  -- 红色激光
                customParams = {
                    overpenetrate = "1",  -- 穿透
                },
            },
            LASER_DRONE_HEAL = {
                name                    = "Drone Nano Repair",
                avoidFriendly           = false,
                collideFriendly         = true,
                damage                  = {
                    default = -35,  -- Legion 治疗最强
                },
                range                   = 250,
                reloadtime              = 1.5,
                size                    = 2,
                weaponType              = "BeamLaser",
                thickness               = 2,
                coreThickness           = 0.5,
                laserFlareSize          = 3,
                rgba                    = "0.0 1.0 0.3 1.0",  -- 绿色纳米修复
                noSelfDamage            = true,
                weaponTimer             = 0.15,
                customParams = {
                    is_heal_weapon = "true",
                },
            },
            LASER_DRONE_PARALYZE = {
                name                    = "Drone Focused Paralyze",
                areaOfEffect            = 40,   -- 激光系范围最小但单点强
                avoidFriendly           = true,
                collideFriendly         = false,
                damage                  = {
                    default = 50,    -- 麻痹同时有伤害
                },
                paralyzer               = true,
                paralysisTime           = 2,
                range                   = 350,
                reloadtime              = 3.5,
                size                    = 3,
                soundHit                = "weapon/stun_hit",
                soundStart              = "weapon/laser_fire",
                weaponType              = "BeamLaser",
                thickness               = 2,
                coreThickness           = 1,
                rgba                    = "0.8 0.0 1.0 0.8",  -- 紫色
                noSelfDamage            = true,
            },
        },
        customparams = {
            is_roguelike_drone = "true",
            drone_element = "laser",
        },
    },
}
