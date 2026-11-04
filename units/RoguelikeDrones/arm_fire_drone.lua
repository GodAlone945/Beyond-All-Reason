-- [UnitDef 数据：Cortex 火焰无人机]
-- 本文件只定义模型、移动/碰撞基础值和可用武器槽。生成、无敌维持、轨道位置、
-- 敌人选择、残骸吸收、扣电修复及升级成长均由 game_roguelike_orbit_drones.lua
-- 在 synced 端执行；不能根据这里的武器命令判断修复是否实际发生。

return {
    arm_fire_drone = {
        name                = "Fire Drone",
        description         = "Orbiting fire drone",
        maxacc              = 0.5, -- 最大加速度
        maxdec              = 0.8, -- 最大减速度
        blocking            = false, -- 不阻挡其他单位
        energycost          = 0, -- 建造该单位所需的能量
        metalcost           = 0, -- 建造该单位所需的金属
        builddistance       = 200, -- 建造范围
        builder             = false, -- 不是建造单位
        canfly              = true, -- 可以飞行
        canmove             = true, -- 可以移动
        collide             = false,           -- 不与其他单位碰撞
        cruisealtitude      = 60, -- 巡航高度
        explodeas           = "smallexplosiongeneric-builder", -- 死亡爆炸效果
        footprintx          = 1, -- 占用格数（X方向）
        footprintz          = 1, -- 占用格数（Z方向）
        health              = 500, -- 初始最大生命值
        maxslope            = 60, -- 最大坡度
        speed               = 300.0, -- 最大速度
        maxwaterdepth       = 0, -- 最大水深
        objectname          = "Units/legheavydronesmall.s3o", -- 复用现有模型，后续换
        script              = "Units/legheavydrone.cob", -- 复用现有脚本，后续换
        selfdestructas      = "smallExplosionGenericSelfd", -- 死亡自爆效果
        sightdistance       = 800, -- 与 Roguelike 目标搜索半径一致
        turninplaceanglelimit = 360, -- 转向角度限制
        turnrate            = 2400, -- 转向速度
        hoverattack         = true, -- 悬停攻击
        mass                = 100, -- 质量
        nochasecategory     = "ALL", -- 不追击任何单位
        -- 无敌：极高装甲 + 极小碰撞体积
        collisionVolumeScales  = "1 1 1",
        collisionVolumeOffsets = "0 20 0",
        weapons = {
            {
                def = "FIRE_DRONE_WEAPON",
                onlytargetcategory = "SURFACE", -- 仅攻击地面单位
                -- 武器自动攻击最近敌人
            },
            {
                def = "FIRE_DRONE_HEAL",
                -- 治疗指挥官
            },
            {
                def = "FIRE_DRONE_PARALYZE",
                -- 麻痹敌人
            },
        },
        weaponDefs = {
            FIRE_DRONE_WEAPON = {
                name                    = "Drone Fire Bolt",
                areaOfEffect            = 48, -- 武器的爆炸范围
                burst = 16, -- 每次开火发射的子弹数量
				burstrate = 0.05, -- 每发子弹之间的时间间隔
                turret = true, -- 可以旋转瞄准
                cegtag = "burnflame-anim", -- 武器的特效标签
                avoidFriendly           = true, -- 避免击中友军
                collideFriendly         = false, -- 不与友军碰撞
                damage                  = {
                    default = 80,
                },
                colormap = "1 0.95 0.82 0.03   0.65 0.4 0.35 0.030   0.44 0.25 0.20 0.028   0.033 0.018 0.012 0.03   0.0 0.0 0.0 0.01",
                explosionGenerator      = "custom:napalm_thing",  -- 火焰特效
                fireStarter             = 100, -- 火焰启动概率
                flightTime              = 1.5, -- 飞行时间
                impactOnly              = true, -- 只在命中时触发伤害
                interceptedByShieldType = 1, -- 可被护盾拦截
                noSelfDamage            = true, -- 不会伤害自己
                range                   = 350, -- 射程
                reloadtime              = 1.0, -- 装填时间
                size                    = 3, -- 子弹大小
                soundHit                = "weapon/burn_mixed",
                soundStart              = "weapon/burn_launch",
                startVelocity           = 400, -- 初始速度
                tolerance               = 8000, -- 容差角度
                weaponAcceleration       = 400, -- 武器加速度
                weaponType              = "Flame", -- 武器类型为火焰
                weaponVelocity          = 400, -- 武器速度
                customParams = {
                    burntime = "3", -- 燃烧时间
                    burndamage = "15", -- 每秒燃烧伤害
                    burnchance = "1", -- 燃烧触发概率
                },
                customparams = {
					weapons_group = 1, -- 自定义参数，武器组
				},
            },
            FIRE_DRONE_HEAL = {
                name                    = "Drone Repair Beam",
                avoidFriendly           = false,
                collideFriendly         = true,
                damage                  = {
                    default = -30,   -- 负伤害 = 治疗
                },
                range                   = 250,
                reloadtime              = 1.5,
                size                    = 2,
                weaponType              = "BeamLaser",
                thickness               = 2,
                coreThickness           = 0.5,
                laserFlareSize          = 3,
                rgba                    = "1.0 0.6 0.2 1.0",  -- 橙色
                noSelfDamage            = true,
                targetBorder            = 0,
                weaponTimer             = 0.1,
                customParams = {
                    is_heal_weapon = "true",
                },
                customparams = {
					weapons_group = 2, -- 自定义参数，武器组
				},
            },
            FIRE_DRONE_PARALYZE = {
                name                    = "Drone Stun Burst",
                areaOfEffect            = 80,
                avoidFriendly           = true,
                collideFriendly         = false,
                damage                  = {
                    default = 0,
                },
                paralyzer               = true,
                paralysisTime           = 3,
                range                   = 200,
                reloadtime              = 4.0,
                size                    = 4,
                soundHit                = "weapon/stun_hit",
                soundStart              = "weapon/stun_fire",
                weaponType              = "Cannon",
                rgba                    = "1.0 0.3 0.0 0.7",  -- 红橙色
                noSelfDamage            = true,
                customparams = {
					weapons_group = 3, -- 自定义参数，武器组
				},
            },
        },
        customparams = {
            is_roguelike_drone = "true",
            drone_element = "fire",
        },
    },
}
