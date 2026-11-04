# Roguelike 数值平衡基线与调参方案

## 2026-11-01 本轮数值修正（源码已改，未实机验证）

- 指挥官基础金属产出与每次选卡后的 `umm` 均为 `0`；`roguelike_metal_income` 显示值也为 `0`。跳过卡牌不再额外给 `15` 金属。商店仍消费金属，敌方残骸吸收仍按原公式给金属，选卡电力增长不变。若房间中另有产金单位，仍应单独检查其规则。
- 新生成敌人的生命倍率固定按时间计算：`min(12, 1.12^(经过分钟) × Boss系数)`，Boss 系数为 `1.35`，普通敌人为 `1`。移除了额外乘入玩家当前伤害倍率的反向缩放；时间成长率、上限和敌人伤害成长 `min(6, 1.09^(经过分钟) × Boss系数)` 未改。购买攻击成长后，同时间同单位的新敌人基础血量不应因此上升。
- 指挥官通用伤害成长跳过运行时 `WeaponDef.type == "DGun"` 或 `manualFire` 武器。D-Gun 原本的基础伤害与原生机制保持；其他 Gadget 的伤害修饰仍需实机核查。
- 派生伤害面对标记 Boss 或最大生命超过 `12000` 的目标时，限制为目标最大生命的 `5%`：效果模块先限制输入，Upgrades 在角色/商店倍率之后再次限制。是否有其他 Gadget 在此后改写伤害，仍需实机日志验证。
- BeamLaser 的商店扩展在 `UnitDamaged` 没有 projectileID 时，使用 WeaponDef 基础伤害作为延迟打击基数，并按 `max(1, floor(reload × 30 × 0.75))` 帧限次。此限次是源码级回退机制，实际 BeamLaser 回调频率、特殊齐射与命中表现尚未实测。

实机对照：同一波次和时间分别在购买攻击卡前后记录同 UnitDef 的新敌人最大生命；分别记录普攻、D-Gun 和派生攻击对普通敌人/Boss 的扣血；两人各持不同攻击成长重复一遍。记录实际 WeaponDefID、伤害、护盾剩余量、回放和 `infolog.txt`。本节无实测 DPS、TTK 或联机同步结论。

> 当前进度与游玩入口：[统一总览](RoguelikeOverview.md)。本页保留历史估算；最新数值口径以上方“本轮数值修正”为准，未实机验证的参数不因源码检查通过而升级为已验证。

> 关联文档：[玩法维护手册](RoguelikeMaintenanceManual.md) · [架构与接口](RoguelikeArchitecture.md)。
> 本文记录 2026-11 的数值体检结论、目标曲线和改动清单。既有恢复/升级 P0、商店武器调整、开局火力/自爆拦截 P0 与三阵营专属武器及通用槽位补齐均已写入代码，仍待实机验证；敌人曲线和伤害陷阱未实施。第 1 节有早期审计快照，后续变更以本次武器章节和变更日志为准。

**2026-11-01 新数值覆盖：** `RECOVERY_DURATION` 从 30 秒改为 **0 秒**；开局准备仍为 5 秒。清场 10% 最大生命治疗保留，原 30 秒内约 36% 的休整回血不再发生；商店可以在战斗/清场/开局准备任意阶段购买。下文第 0–3 节关于“休整 30 秒”和“休整后 ≥90%”是旧方案的设计与历史计算，已被此条覆盖。双人 Coop 暂用同一敌人目标数/预算与共享击杀阈值，不乘人数；续航、每人升级节奏和经济均**未实机验证**，需重新定标。审计和阶段测试见 [RoguelikeCoopAudit.md](RoguelikeCoopAudit.md)。

**2026-11-01 连续刷怪修正（覆盖上一段的清场机制）：** 实机日志证实旧实现每 70 秒战斗后进入最多 25 秒清场，期间停止补兵。现已取消清场阶段；累计作战秒数每秒推进，目标存活数仍按 `min(120, max(20, round(20 × 1.28^(秒数/60))))` 更新。每秒增加 `min(450, 目标数 × 3) / 70` 点刷怪额度，上限为当前阶段单批上限（8/12/18/24/30）；每 4 秒最多按额度、批量上限和目标缺口补兵。每 70 秒只更新波次编号、治疗 10% 最大生命并触发里程碑，旧敌人保留，不再以清场作为下一波前置条件。敌军 HP/伤害成长公式未改。该连续速率和续航**尚未实机验证**。

## 0. 结论摘要

> 以下 0–3 节为 P0 前审计与历史推算；其中 30 秒休整和对应回血目标已被上方 2026-11-01 新数值覆盖，不能当作当前实测结论。

1. **暴毙的主因不是“每秒回血太小”，而是“波与波之间没有恢复闭环”。** 当前每波最多恢复约 11%（无人机解锁前）到 26%（解锁后）最大生命，而第三波一次交火就能打掉 100% 以上；损失只会逐波累积，第三、四波必然见底。
2. **战斗内治疗在数学上救不了被围。** 集火保护之后，原始 2250 DPS 仍会打成约 1438 DPS（14.4%/s），TTK 只有 7 秒；无人机紧急修复 2 架合计 0.5%/s，相差约 30 倍。因此回血应主要发生在**休整阶段**，战斗内只保留“逃生保险”。
3. **指挥官基础参数散落在三处，Legion 漏改。** `armcom`/`corcom` 是 10000 HP、60 速、0 金属；`legcom` 仍是 3700 HP、37.5 速、2 金属。同一模式内 EHP 差 2.7 倍，这是“换个阵营第三波必死”的直接原因。
4. **升级阈值在第三波只给 3 张卡，卡池又没有防御保底。** 而每张卡的自动成长只有生命 +4.5%、护甲 +0.87%，同期压力是敌伤 ×1.22 × 数量 ×1.78。玩家如果随机到攻击/移速卡，EHP 几乎不涨。
5. **武器数值两极分化，且只有 Cortex 能买全 5 把武器。** 雷霆步枪 362 DPS / 1200 金属，覆盖炮 51 DPS / 2700 金属；`armcom`/`legcom` 只追加了雷霆槽位，其余 4 把在商店里点了会返回 `weapon_unavailable`。
6. **敌方血量乘了玩家伤害倍率，使“武器强化”和每卡攻击成长对 TTK 基本无效。** 这是一个隐藏的负反馈陷阱：买 +2% 伤害，之后刷出的敌人就 +2% 血量。

## 1. 现状体检

> 本节是 **P0 实施前** 的基线数据，用于说明改动理由；当前代码数值以第 3 节和 [维护手册](RoguelikeMaintenanceManual.md) 为准。

### 1.1 波次压力曲线

按 `game_roguelike_spawner.lua` 的常量复算（战斗 70 秒/波，清场不计入 `combatSeconds`），假设 85% 击杀率：

| 波次 | 战斗分钟 | 敌血× | 敌伤× | 目标存活 | 波次预算 | 累计击杀 | 当前卡数 |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 0.00 | 1.00 | 1.00 | 20 | 60 | 51 | 1 |
| 2 | 1.17 | 1.14 | 1.11 | 27 | 81 | 119 | 2 |
| 3 | 2.33 | 1.30 | 1.22 | 36 | 108 | 211 | 3 |
| 4 | 3.50 | 1.49 | 1.35 | 47 | 141 | 331 | 3 |
| 5 | 4.67 | 1.70 | 1.50 | 63 | 189 | 492 | 4 |
| 6 | 5.83 | 1.94 | 1.65 | 84 | 252 | 706 | 5 |
| 7 | 7.00 | 2.21 | 1.83 | 113 | 339 | 994 | 6 |
| 8 | 8.17 | 2.52 | 2.02 | 120 | 360 | 1300 | 7 |

关键点：

- 总压力 ≈ 数量 × 伤害 = `1.28^m × 1.09^m ≈ 1.40^m`（每战斗分钟 +40%）。
- 玩家单卡自动成长 ≈ 生命 +4.5%~6.7%、护甲 +0.9%~1.1%，即每波 +5% 量级。
- 两者相差一个数量级；第 3 波正是“压力已翻倍、卡片只有 3 张”的交叉点，与实机反馈吻合。

### 1.2 承伤与 TTK

`UnitPreDamaged` 的集火保护是“每秒前 10% 最大生命全额、超出部分 ×0.35”。按 10000 HP 复算：

| 原始承伤 DPS | 保护后 DPS | 占最大生命 | TTK |
| ---: | ---: | ---: | ---: |
| 1200 | 1070 | 10.7%/s | 9.3s |
| 2250 | 1438 | 14.4%/s | 7.0s |
| 3000 | 1700 | 17.0%/s | 5.9s |
| 5000 | 2400 | 24.0%/s | 4.2s |

结论：**被 10 个以上单位贴身集火时，任何“每秒 1%”级别的回血都追不上**。回血只能负责“打完这一波之后能回到安全线”，战斗内的容错要靠走位、护盾和逃生窗口。

### 1.3 回血供给（当前）

| 来源 | 触发条件 | 数值 | 每波折算 | 问题 |
| --- | --- | ---: | ---: | --- |
| 基础回复 | 脱战 8 秒后 | 0.15%/s | ≈3.3% | 战斗中几乎不触发 |
| 波次清场 | 每波结算 | 8% 最大生命 | 8% | 一次性，杯水车薪 |
| 无人机修复 | 无敌人 1500 范围内，或 <30% 紧急 | 0.25%/s/架 | ≈15%（2 架） | 战斗中 1500 内有敌人就永远不修；紧急带只有 30%→40% |
| 纳米修复商店 | 脱战 8 秒后 | 0.1%/s/级，450 金属 | ≈2.2%/级 | 价格是“装甲强化”的 4.5 倍，效果却只在脱战生效 |
| 护盾充能 | 脱战 5 秒后 | 2% 容量/s，1 电/点 | 300 容量≈6 HP/s | 容量太小，几乎不可见 |

合计：无人机解锁前 ≈11%/波，解锁后 ≈26%/波。从 20% 回到 90% 需要约 3 波——而每波都在掉血，所以第三波后进入死亡螺旋。

### 1.4 升级节奏

| | 卡 1 | 卡 2 | 卡 3 | 卡 4 | 卡 5 | 卡 6 | 卡 7 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 当前阈值 | 35 | 100 | 200 | 340 | 540 | 810 | 1170 |
| 到达波次（85% 击杀） | 1 | 2 | 3 | 5 | 6 | 7 | 8 |
| 累计击杀 | 51 | 119 | 211 | 492 | 706 | 994 | 1300 |

- 第 3 波结束时通常 3 张卡，第 4 张要等到第 5 波（340 击杀）；Tier 2 又要第 4 张才解锁（`upgradeCount >= 3`）。所以第三、四波玩家仍在用 Tier 1 卡对抗已经 ×1.3~1.5 的敌人，中间正好卡着 2 波空窗。
- 每张卡的自动成长是线性的（+5%/张），而压力是指数的（×1.4/分钟）；即使每波 1 张卡也追不上，必须靠防御类卡本身。
- 卡池 22 项里防御类只有生命/护甲/护盾 9 项，且和攻击、移速、无人机混抽，**没有任何保底**。

### 1.5 商店性价比（按第 1 级）

| 项目 | 效果 | 价格 | 效果/金属 | 备注 |
| --- | --- | ---: | ---: | --- |
| 装甲强化 | +10% 最大生命 | 100 | 0.100%/金属 | 最强，且战斗内生效 |
| 残骸精炼 | +15% 残骸金属 | 120 | 0.125%/金属 | 滚雪球 |
| 冷却强化 | +8% 攻速 | 120 | 0.067%/金属 | 实际 DPS |
| 机动强化 | +6% 移速 | 100 | 0.060%/金属 | 生存向 |
| 火控强化 | +5% 射程 | 150 | 0.033%/金属 | |
| 武器强化 | +2% 武器伤害 | 80 | 0.025%/金属 | **被敌方血量公式抵消，接近 0** |
| 纳米修复 | +0.1%/s 脱战回复 | 450 | 0.005%/金属 | 比装甲弱 20 倍 |

### 1.6 数值来源分散

| 数值 | 当前写在哪 | 问题 |
| --- | --- | --- |
| 指挥官生命/移速/金属 | `units/armcom.lua`、`units/corcom.lua`、`units/Legion/legcom.lua` 直接改 | 不受 `roguelike_mode` 控制，会影响所有模式；Legion 漏改 |
| 指挥官武器 +40% | 同上三个 UnitDef | 同上；手册原写由 Tweaks 完成，已按实际位置修正 |
| Cortex 雷霆 30.8/0.85、护盾槽 4~9 | `unitbasedefs/roguelike_unit_tweaks.lua` | 只有 Cortex 有完整槽位 |
| 敌人数值/波次 | `game_roguelike_spawner.lua` | 与 Upgrades 的成长公式重复实现 |
| 卡片/阈值/回血 | `game_roguelike_upgrades.lua` | 与 UI 展示价格两套表 |

> 手册第 1 节要求“模式关闭时，Roguelike 专用 UnitDef 修改不应影响标准 BAR 对局”。当前直接改上游 UnitDef 的做法违反该约束，也是 Legion 漏改的根因。

### 1.7 开局武器、前 8 波与自爆单位体检（本轮改动前）

#### 指挥官实际武器

下表来自 `units/armcom.lua`、`units/corcom.lua`、`units/Legion/legcom.lua` 与加载期 Tweaks。上游普攻伤害仍乘既有 Roguelike `×1.4`；这里的“Roguelike 单发”已包含该倍率，DPS 按单发÷装填计算，不计雷霆步枪商店槽、D-Gun 或重复槽。

| 阵营 | 普攻 UnitDef / 目标类别 | 原版射程/装填/伤害 | 本轮前 Roguelike 有效值 | 普攻有效 DPS | 反空能力 |
| --- | --- | --- | --- | ---: | --- |
| ARM | `armcomlaser` / `NOTSUB` | 300 / 0.40s / 75 | 300 / 0.40s / 105 | 262.5 | 可打 VTOL，但有效射程仅 300；`armcomsealaser` 为 `NOTAIR`，不能补空 |
| Cortex | `corcomlaser` / `NOTSUB` | 300 / 0.40s / 75 | 300 / 0.40s / 105 | 262.5 | 可打 VTOL，但有效射程仅 300；海激光为 `NOTAIR` |
| Legion | `legcomlaser` / `SURFACE` | 300 / 0.80s / 175 | 300 / 0.80s / 245 | 306.25 | 普攻不能打空；原有 `aa_missile` 射程 300、装填 1.20s、VTOL 伤害 150（Roguelike 缩放后 210） |

三族视野原值都是 450。三族 D-Gun 不纳入普攻倍率目标：ARM/Legion 为 250 射程、0.9s、99999 伤害；Cortex 为 262 射程、0.9s、99999 伤害。本轮保持不动。

#### 前 8 波实际生成框架

Spawner 并非按 ARM/Cortex/Legion 轮换固定阵容。`ENEMY_ROSTERS` 虽在文件中定义，但当前生成调用使用所有符合条件的已加载移动战斗 UnitDef：先按生命值分成五个阶段池，再按远近程池随机抽取，每个普通候选基础权重为 2；每 5 波的 Boss 来自独立 Boss 池。全局战斗秒数不含清场/休整，因此当前阶段、目标存活数、预算与批次上限如下：

| 波次 | 累计战斗秒 | 阶段池 | 目标存活 | 生成预算 | 批次上限 | Boss |
| ---: | ---: | --- | ---: | ---: | ---: | --- |
| 1 | 0 | 轻型先遣军 | 20 | 60 | 8 | 无 |
| 2 | 70 | 轻型先遣军 | 27 | 81 | 8 | 无 |
| 3 | 140 | 快速混编军 | 36 | 108 | 12 | 无 |
| 4 | 210 | 中型主力军 | 47 | 141 | 18 | 无 |
| 5 | 280 | 中型主力军 | 63 | 189 | 18 | 1 个：`armbanth` / `corkarg` / `legkeres`，权重 2/2/4 |
| 6 | 350 | 重型突击军 | 84 | 252 | 24 | 无 |
| 7 | 420 | 重型突击军 | 113 | 339 | 24 | 无 |
| 8 | 490 | T3 终局军团 | 120（上限） | 360 | 30 | 无 |

改动前普通池没有自爆单位白名单、最低波次、生成间隔或并发上限。进入其自动分配的生命/威胁阶段池后，它们就可能被普通随机抽取；第 1、2 波都使用阶段 1。实际每局构成由 UnitDefs、阶段池、随机数和生成缺口决定，并非固定名单；旧日志只记总数，不足以证明某局每波具体抽到了哪些单位。

#### 当前普通刷怪池中的蓄意自爆单位

下表区分单位死亡时的 `explodeas` 与主动引爆时的 `selfdestructas`/炸弹武器。常规 BAR 单位普遍带普通死亡爆炸，本表只列本模式移动战斗候选池里具有蓄意自爆行为的单位；地雷建筑因非移动战斗单位而不进入该池。

| UnitDef | 原版级别 | HP / 速度 | 主动或撞击伤害 | 普通死亡爆炸 | 主动自爆爆炸 |
| --- | --- | ---: | --- | --- | --- |
| `legkam` | Legion T1 空中 Martyr | 160 / 220 | `martyrbomb` 空投，AoE 200，默认 440、指挥官 220；另有 500 射程触发武器，飞行脚本释放炸弹 | `tinyExplosionGeneric`；`selfdestructas` 为空 | 不是爬行炸弹式 self-destruct；高速度、炸弹撞击才是主要危险 |
| `armvader` | ARM T2 爬行炸弹 | 445 / 84 | `instantselfd` 近身引爆 | `crawl_blastsml`，AoE 280，默认 2000、指挥官 1000 | `crawl_blast`，AoE 400，默认 2700、指挥官 1000 |
| `corroach` | Cortex T2 爬行炸弹 | 620 / 76 | `instantselfd` 近身引爆 | `crawl_blastsml`，AoE 280，默认 2000、指挥官 1000 | `crawl_blast`，AoE 400，默认 2700、指挥官 1000 |
| `corsktl` | Cortex T2 Skuttle | 355 / 84 | `instantselfd` 近身引爆 | `crawl_blast`，AoE 400，默认 2700、指挥官 1000 | `corsktlSelfd`，AoE 480，默认 8300、指挥官 1110 |
| `legsnapper` | Legion T2 爬行炸弹 | 550 / 81 | `instantselfd` 近身引爆 | `crawl_blastsml`，AoE 280，默认 2000、指挥官 1000 | `crawl_blast`，AoE 400，默认 2700、指挥官 1000 |

爆炸数值来自 `weapons/crawl_blast.lua`、`weapons/corsktlSelfd.lua` 和对应 UnitDef/WeaponDef。自爆伤害没有被本轮修改。`armkam` 是普通攻击飞机，`legmineb` 投放地雷；它们有普通死亡爆炸或炸弹武器，但不是上述追身自爆单位，仍由普通敌军逻辑处理。

## 2. 设计目标（先定目标，再调数值）

| 指标 | 目标 |
| --- | --- |
| 每波战斗结束时生命 | ≥ 50%（普通水平），≥ 20%（失误一次） |
| 波间生命 | 待实测重定；旧“休整结束 ≥90%”目标失效 |
| 被围集火 TTK | ≥ 8 秒，留出撤退窗口 |
| 卡片节奏 | 第 1~8 波平均每波 1 张 |
| 每波可用防御成长 | 生命/护盾/护甲合计 ≥ +20% 有效 EHP |
| 武器 DPS/价格 | 每 1000 金属 150~260 点单体 DPS（AoE/射程另计） |
| 三阵营基础 | 同一套生命/移速/能量/金属 |

## 3. P0：先解决“第三波后暴毙”（小改动，建议先上）

> 本节各表的“建议”列即 2026-11-01 已落地的数值；“当前”列保留改动前的基线用于对照。

### 3.1 历史方案：休整阶段回血（已被零等待覆盖）

在 `game_roguelike_upgrades.lua` 增加一个常量并在 `GameFrame` 里按阶段回血：

```lua
-- 休整 30 秒内按 1.2%/s 回复，约 36%；与清场治疗、无人机修复叠加。
local RECOVERY_HEAL_PER_SECOND = 0.012
```

现有 `GameFrame` 的脱战回复改为：

```lua
local regenRate = 0
if GG.Roguelike and GG.Roguelike.phase == 3 then
    regenRate = RECOVERY_HEAL_PER_SECOND + cumulativeMultipliers.regenBonus
elseif frame - lastHealthDamageFrame >= HEALTH_REGEN_DELAY then
    regenRate = BASE_HEALTH_REGEN_PER_SECOND + cumulativeMultipliers.regenBonus
end
if regenRate > 0 then
    local health, maxHealth = spGetUnitHealth(playerUnitID)
    if health and maxHealth and health > 0 and health < maxHealth then
        spSetUnitHealth(playerUnitID, { health = math.min(maxHealth, health + maxHealth * regenRate) })
    end
end
```

同时：

| 常量 | 当前 | 建议 | 理由 |
| --- | ---: | ---: | --- |
| `WAVE_CLEAR_HEAL_FRACTION` | 0.08 | 0.10 | 清场奖励可感知 |
| `BASE_HEALTH_REGEN_PER_SECOND` | 0.0015 | 0.0025 | 脱战恢复不至于为零 |
| `HEALTH_REGEN_DELAY` | 8s | 6s | 减少“刚脱战又被摸一下” |
| `RECOVERY_HEAL_PER_SECOND` | — | 0.012 | 30 秒≈36%，配合其余来源可回满 |

旧方案预期：每波总恢复 ≈ 36%（休整）+ 6%（基础）+ 24%（2 架无人机）+ 10%（清场）≈ 76%。现代码波间为 0 秒，不能再使用这份预测作为当前续航结论。

### 3.2 战斗内保险（无人机）

`game_roguelike_orbit_drones.lua`：

| 常量/行为 | 当前 | 建议 | 理由 |
| --- | ---: | ---: | --- |
| `REPAIR_MAX_HEALTH_FRACTION_PER_DRONE` | 0.004 | 0.006 | 每架 +50% 治疗；两架名义 1.2%/s，尚未计入全局治疗上限 |
| `ENERGY_PER_REPAIR_HEALTH` | 1.0 | 0.75 | 每点有效治疗耗电降低 25%，减少低电力时修复损失 |
| `EMERGENCY_REPAIR_START/STOP` | 0.30 / 0.40 | 0.45 / 0.60 | 45% 就开始救，不会“修到 40% 立刻停” |
| `SEARCH_RADIUS` | 1500 | 800 | 搜索与无人机 800 视野一致，确保能发现并攻击其射程内目标 |
| 常规修复条件 | 无敌人 1500 内 | 无敌人 800 内；生命 <45% 时由紧急修复接管（持续到 60%） | 让“带伤作战”有持续回复 |

注意：无人机修复通过 `GG.Roguelike.HealCommander` 同步结算，只为实际治疗量扣电；全治疗来源仍受每秒 1.5% 最大生命值上限约束。

### 3.3 升级阈值与卡池保底

**阈值**（`UPGRADE_THRESHOLDS`）：

```lua
-- 目标：第 1 波 2 张、第 2~8 波每波 1 张，后期放缓
local UPGRADE_THRESHOLDS = { 25, 50, 100, 185, 280, 400, 550, 730,
    940, 1180, 1450, 1750, 2080, 2440 }
```

按 85% 击杀率的到达波次：1 / 1 / 2 / 3 / 4 / 5 / 6 / 7 / 8 / 9 / 10 / 11 / 12 / 12。
即第 1 波 2 张，第 2 波起每波 1 张，第 8 波累计 9 张、第 10 波累计 11 张，比当前曲线在第三波多 1 张、第四波多 1 张，正好补在死亡窗口。

**Tier 解锁**（`maxAvailableTier`）：

```lua
if upgradeCount >= 9 then return 3 end
if upgradeCount >= 4 then return 2 end
return 1
```

Tier 2 从第 5 张卡（约第 4 波）开始，Tier 3 从第 10 张卡（约第 9 波）开始。

**防御保底**：`pickRandomChoices` 先按权重抽 1 张防御类卡（生命/护甲/护盾），再用其余槽位抽通用池。

```lua
-- UPGRADE_POOL 中给 health1~3 / armor1~3 / shield1~3 加 category = "defense"
-- 抽卡时：defensePool 抽 1，再从剩余池抽 count-1，最后按原顺序返回。
```

这样玩家不会因为“三张全是移速/无人机”而在第三波裸奔；无人机卡 1.6 权重仍保留在通用池。

**生命卡即时回血**：`applyCommanderStats` 现在按比例保留血量，导致“残血时抽到 +20% 生命”几乎不回血。改为对生命类卡把新增的最大生命值加到当前生命：

```lua
-- applyCardUpgrade 里传 healDelta = (newMaxHealth - oldMaxHealth)
-- 仅 health 类型；护盾卡本来就会补满新增容量
```

### 3.4 指挥官基础参数统一

先修 Legion，再把三类数值收敛到一处。

| 参数 | armcom（P0 前） | corcom（P0 前） | legcom（P0 前） | 统一后 |
| --- | ---: | ---: | ---: | ---: |
| health | 10000 | 10000 | 3700 | 10000 |
| speed | 60 | 65（Tweaks） | 37.5 | 84 |
| energymake | 30 | 100 | 30 | 60 |
| metalmake | 0 | 0 | 2 | 0 |
| metalstorage | 10000 | 10000 | 500 | 10000 |
| 主武器 DPS | 542 | 542 | 481 | 保持 +40% 基线 |

做法：已把以上字段写进 `unitbasedefs/roguelike_unit_tweaks.lua` 的 `COMMANDER_BASE` 表，按 `armcom/corcom/legcom` 统一应用；`units/armcom.lua`、`units/corcom.lua`、`units/Legion/legcom.lua` 已回退到 BAR 原值，武器 +40% 改由 `COMMANDER_WEAPON_DAMAGE_SCALE = 1.4` 在 Tweaks 中缩放。这样才符合手册“模式关闭不影响标准对局”的约束。

本轮把 Roguelike 指挥官基础移速从 60 提升 40% 至 84；只改 `COMMANDER_BASE.speed`，普通 BAR 对局不受影响。2026-11 PokeBonk Phase 1 已移除旧的每次选卡自动移速成长；新的移速提升只来自商店或灵活推进模块。

如果希望第三波更宽容，把 `health` 作为唯一难度旋钮整体调到 12000（+20% EHP），不要只给某个阵营加。

### 3.5 商店与 UI 同步

| 项目 | 当前 | 建议 |
| --- | --- | --- |
| `regen` 价格 | 450 + 350/级，0.1%/s，8 级 | 250 + 220/级，0.3%/s，5 级 |
| `regen` 描述 | “脱战回复 +0.10%” | “休整/脱战额外回复 +0.30%/秒，购买后回满生命” |
| 护盾卡 | 300 / 800 / 1500 | 2000 / 3500 / 5000 |
| 护盾充能 | 2%/s，脱战 5s，1 电/点 | 3%/s，脱战 4s，0.8 电/点 |
| `health` 商店 | +10%/级，100 起 | 可保留；它是当前最划算的防御投资 |

护盾必须和生命同量级才有意义：300 容量只相当于 3% 最大生命，而一张生命卡是 +20%。

### 3.6 开局普攻与自爆单位拦截（本轮 P0）

本轮只调整 Roguelike 的 commander UnitDef、模式内防空目标优先级和 synced Spawner；没有改上游 commander UnitDef，也没有改敌人血量/伤害成长、目标数曲线、回血、升级、商店或 D-Gun。普攻伤害保留既有 `×1.4`，本轮只改射程和装填；DPS 增加来自更短装填，不是增加单发伤害。

#### 普攻和防空改动

| 项目 | 修改前 Roguelike 值 | 修改后 | 影响 |
| --- | --- | --- | --- |
| ARM 普攻 `armcomlaser` | 射程 300，装填 0.40s，单发 105，262.5 DPS | 射程 420，装填 0.30s，单发 105，350 DPS | 射程 +40%；DPS +33.3% |
| Cortex 普攻 `corcomlaser` | 射程 300，装填 0.40s，单发 105，262.5 DPS | 射程 420，装填 0.30s，单发 105，350 DPS | 射程 +40%；DPS +33.3% |
| Legion 普攻 `legcomlaser` | 射程 300，装填 0.80s，单发 245，306.25 DPS | 射程 420，装填 0.60s，单发 245，约 408.3 DPS | 射程 +40%；DPS +33.3% |
| 三族视野 | 450 | 520 | 能在普攻射程外更早发现敌军 |
| ARM/Cortex Roguelike 专属防空槽 | 无 | 克隆 Legion 原有 AA 导弹；射程 480、装填 1.20s、VTOL 单发 210 | 仅 Roguelike 增加，不挪用海激光/商店槽 |
| Legion `aa_missile` | 射程 300、装填 1.20s、VTOL 单发 210 | 射程 480，其他伤害/装填不变 | 保留 Legion 原防空定义 |
| `legkam` 自动目标优先级 | AA Targeting 按 AircraftBomb 分类，倍率 0.1 | Roguelike 标记目标优先级倍率 2 | 对 auto-target 的优先级提高 20 倍；仅本模式，不覆盖玩家手动目标 |

轨道无人机的攻击搜索范围和三族无人机视野统一到 800；ARM 电击无人机攻击槽明确只选 `SURFACE` 目标，避免目标发现与武器类别不一致。其攻击/治疗任务优先级保持不变。该目标发现修正尚未实机确认。

Armada/Cortex 普攻 `NOTSUB` 可打空中和地面，Legion 普攻 `SURFACE` 只打地面；三族现在另有 480 射程 AA 拦截能力。D-Gun 的射程、装填和伤害保持原值。Legion AA 的 150 VTOL 伤害受既有 `×1.4` 得到 210，能一发击落原版 160 HP Martyr；ARM/Cortex 新增槽也复用该导弹与伤害口径。自动锁定、弹道命中和飞行拦截时机仍需实机确认。

#### 自爆单位生成参数

所有蓄意自爆候选先从普通动态池排除，再由 synced Spawner 控制；普通候选权重仍为 2，不改目标数/预算成长。自爆触发机会按普通补兵批次检查，至少间隔 10 秒；波次中没有普通补兵缺口时不会额外越过缺口强行加怪。生成点经过地图边界裁切后仍须离玩家至少 800 距离，刷出后强制可见，并显示 3 秒 Roguelike 警报。死亡/自爆伤害字段完全未改。

| 波次 | 同时存活上限 | 首次尝试生成概率 | 特殊池权重 |
| ---: | ---: | ---: | --- |
| 1 | 0 | 0% | 不生成 |
| 2 | 1 | 100% | 仅 `legkam`，权重 4 |
| 3 | 2 | 50% | 仅 `legkam`，权重 4 |
| 4 | 2 | 50% | 仅 `legkam`，权重 4 |
| 5 | 3 | 45% | `legkam` 权重 4；四种 T2 爬行炸弹各 0.5 |
| 6 | 3 | 50% | `legkam` 权重 3；四种 T2 爬行炸弹各 1 |
| 7 | 3 | 55% | 同上 |
| 8+ | 4 | 60% | 同上 |

概率是每次满足生成缺口、并发上限和间隔后的抽取概率，不是“每波必刷数量”；单位权重只决定一次抽中后选哪一型。Wave 2 的首次有效抽取保证选中 `legkam`，但仍要等普通补兵缺口出现。T2 爬行炸弹（`armvader`、`corroach`、`corsktl`、`legsnapper`）从第 5 波才进入特殊池。并发计数只遍历 Spawner 自己跟踪的存活刷怪单位，不做每帧全图扫描；清场存活体也会占用后续波次上限。

#### 潜在问题和状态

- Legion 普攻有效 DPS 约比 ARM/Cortex 高 16.7%；这是保留阵营武器单发差异、只缩短既有装填后的结果，仍高于附件建议的 ±10%~15% 带宽边缘。本轮不通过降伤害来追平，需按相同地图与种子比较实际击杀节奏。
- 800 距离与强制可见能提供发现/射击窗口，但地图边缘、地形阻隔、飞行转向和目标抢锁会改变实际拦截时间。
- Spawner 的普通敌军仍按阶段池和随机数生成；生成缺口不出现时，自爆单位也会延后，10 秒是最短尝试间隔而不是固定时钟保证。
- T2 爆炸数值很高且没有削弱；如果第五波以后出现击杀即大范围爆炸，需区分普通死亡 `explodeas` 和主动自爆 `selfdestructas` 的伤害来源。
- `game_roguelike_spawner.lua` 仍按 `1.12^combatMinutes × playerDamageMult` 放大新敌 HP；这会抵消部分伤害投资，留待另一轮独立 A/B，不和本轮开局火力一起改。

**状态：代码已实施，未实机验证。** 目前没有实测 ARM/Cortex/Legion 普攻命中率、Martyr 拦截率、首波击杀率或第五波 T2 自爆存活情况。

## 4. P1：结构性调整（武器数值已实施，敌人曲线未实施）

> 商店武器 DPS/价格与扩展卡已在 2026-11-01 一并调整；敌方压力曲线和伤害陷阱仍未实施，建议先跑 P0+武器数值，再决定是否改敌人曲线。

### 4.1 敌方压力曲线

| 常量 | 当前 | 建议 | 说明 |
| --- | ---: | ---: | --- |
| `TARGET_GROWTH_PER_COMBAT_MINUTE` | 1.28 | 1.22 | 120 个目标存活对单指挥官过载 |
| `MAX_TARGET_ALIVE` | 120 | 90 | 降负载、降包围概率 |
| 敌方血量成长 | 1.12^m | 1.10^m | |
| 敌方伤害成长 | 1.09^m | 1.08^m | |
| `WAVE_BUDGET_MULTIPLIER` / `MAX_WAVE_BUDGET` | 3 / 450 | 3 / 360 | 与目标数同步 |

改后第 8 波目标存活约 90（原 120），波次总血量约 −35%；配合 P0 的恢复，玩家能“清得动”而不只是“撑 70 秒”。

### 4.2 伤害陷阱

`game_roguelike_spawner.lua` 的 `applyEnemyScaling`：

```lua
local healthMult = mMin(12, (1.12 ^ elapsedMinutes) * mMax(1, playerDamageMult) * bossHealthScale)
```

把玩家的伤害倍率 **全额** 乘进敌人血量，等于“每买一次武器强化，以后所有敌人多 2% 血”。建议改为弱耦合：

```lua
local playerPowerScale = 1 + 0.25 * (mMax(1, playerDamageMult) - 1)
local healthMult = mMin(12, (1.12 ^ elapsedMinutes) * playerPowerScale * bossHealthScale)
```

这样 +100% 玩家伤害只换来 +25% 敌人血量，伤害类投资仍有净收益；同时保留“无脑堆伤害不会让难度归零”的初衷。

### 4.3 武器数值

当前 DPS 与价格（Cortex 满槽位口径）：

| 武器 | 伤害/装填（前 → 后） | 单体 DPS（前 → 后） | 价格（前 → 后） | 状态 |
| --- | --- | ---: | ---: | --- |
| 雷霆步枪 | 30.8×10 / 0.85s | 362 | 1200 | 三阵营已统一 |
| Tzar 主炮 | 900 → 1100 / 3.5s | 257 → 314 | 1800 | 已实施 |
| 湮灭狙击 | 1800 / 4s | 450 | 3200 → 2800 | 已实施 |
| 凝固汽油炮 | 60 → 170 ×6，7 → 6s | 51 → 170（+燃烧） | 2700 | 已实施 |
| 冲击清场炮 | 190 → 340，1.8 → 1.3s | 105 → 262 | 2200 | 已实施 |

配套：

- 已修复 `plasma_weapon` / `sniper_weapon` / `barrage_weapon` / `shockwave_weapon` 缺少 `customParams.roguelike_shop_item` 的问题；此前这 4 件商品在 `findShopWeaponSlot` 阶段必然返回 `weapon_unavailable`。
- 扩展卡已提高：`lightning_extension` +12% → +25%；`plasma_extension` +18% → +25%；`barrage_extension` +15% → +25%；`shockwave_extension` +25% → +30%。否则 900~1500 金属的扩展只换来 8~46 点 DPS，远不如 80 金属的伤害强化。
- 早期审计记录过 `armcom`/`legcom` 商店槽缺失、Cortex 固定第4槽重复激光的风险；本轮已用动态追加方案替代写死槽位。新生成的三族 WeaponDef/weapon slot 最终加载结果仍待引擎实机核验。

### 4.4 护甲与集火保护

- 护甲卡 8%/12%/18%、上限 65% 可以保留；它是“配合回血”的乘算防御，越到后期越值钱。
- 集火保护的 10% 全额 + 35% 溢出，已经能把 5000 DPS 压到 24%/s；不建议再加强，否则被围也不会有压力。真正需要的是“撤退窗口”：移速卡、护盾和 45% 紧急修复已经够用。

## 5. 验证与埋点

P0 上线后先跑 3 局，记录以下数据（建议临时 `Spring.Echo`，或做成 `roguelike_diag` 调试开关）：

| 字段 | 用途 |
| --- | --- |
| 每波开始/结束 HP、最大 HP | 验证“结束 ≥50%、休整后 ≥90%” |
| 每波受到的总伤害（`UnitPreDamaged` 累加） | 判断压力曲线是否过陡 |
| 每波击杀数 / 预算 | 校准 85% 击杀假设 |
| 各来源回血量（休整/清场/无人机/击杀） | 确认没有重复叠加或漏算 |
| 每波残骸金属收入 | 校准商店价格 |
| 候选中出现防御卡的次数 | 验证保底逻辑 |

### 本轮开局火力与自爆拦截实机验证（未验证）

固定地图、模式难度和随机种子，分别用 ARM/Cortex/Legion 跑第 1–8 波；每族至少一局不用 D-Gun 清普通单位，另记录一次有意使用 D-Gun 的战略清场。先分组测试“旧版 A、仅普攻 B、仅自爆控制 C、两者 D”，避免把回血或整体敌人曲线改动混进对照。

记录每族的 UnitDef 普攻/AA 射程、装填、单发伤害、自动目标与 D-Gun 次数；记录波次、阶段、生成单位名、特殊单位出现帧/位置、存活峰值、死亡来源、波末/休整后 HP 和警报是否可见。查看 `infolog.txt` 中的 Spawner 输出，例如：

```text
Roguelike: dynamic enemy pool loaded ... suicide units held for controlled scheduling 5
Roguelike: wave 2 suicide spawn legkam (alive 1/1, interval 10s)
```

验收观察：第 1 波无蓄意自爆单位；第 2 波特殊池只允许一只 `legkam`，警报出现且至少 800 距离刷出；第 3–4 波没有 T2 爬行炸弹；第 5 波后允许特殊池引入 T2 类型且任何时刻不超过对应并发上限；Martyr 在自动防空目标优先级下有可观察的拦截机会，手动指定其他目标不会被 Rogue Gadget 改写。对局结束后关闭 `roguelike_mode` 启动标准 BAR/PVP，确认三族 commander 射程、装填、单发伤害和防空槽恢复原值。

本次没有增加单独的 `roguelike_diag` ModOption，也没有运行 Spring 实机对局；目前可用日志只确认特殊单位实际生成与存活数，武器运行时参数、命中率、波末生命及标准模式隔离仍要按上面步骤人工核实。上表的 DPS 是按 UnitDef 静态公式计算，不代表实战击杀速度。

P0 验收：

- 连续 3 波结束生命 ≥50%；被围时有约 8 秒撤退窗口，不再“瞬间暴毙”。
- 第 3 波结束时至少 4 张卡，其中至少 1 张防御卡。
- 三阵营同一起点：10000 HP、84 速、60 电、0 金属。
- 模式关闭时，`armcom`/`corcom`/`legcom` 的基础数值与上游 BAR 一致。
- 本轮开局火力与自爆拦截按上方实机验证步骤验收；当前尚未实机验证。
- 本轮修正待实机确认：三族无人机能攻击其 800 视野内敌人；普通爆炸不销毁待吸收残骸；D-Gun 击杀不获残骸金属且仍能摧毁残骸。

P1 验收：

- 商店里 5 把武器在三族都可购买，购买后 DPS 增量符合上表。


## 6. 调参旋钮速查

| 想改变什么 | 改哪里 |
| --- | --- |
| 整体难度（血量） | `COMMANDER_BASE.health`（三族统一） |
| 战后恢复 | `RECOVERY_HEAL_PER_SECOND`、`WAVE_CLEAR_HEAL_FRACTION` |
| 战斗内续航 | 无人机 `REPAIR_MAX_HEALTH_FRACTION_PER_DRONE`、`EMERGENCY_REPAIR_START` |
| 升级速度 | `UPGRADE_THRESHOLDS`、`maxAvailableTier` |
| 抽卡质量 | `pickRandomChoices` 的防御保底、`UPGRADE_POOL` 权重 |
| 敌人压力 | `TARGET_GROWTH_PER_COMBAT_MINUTE`、`MAX_TARGET_ALIVE`、`1.12/1.09` 两个底数 |
| 武器性价比 | `SHOP_ITEMS` 价格、`roguelike_unit_tweaks.lua` 的伤害/装填 |
| 商店经济 | `baseCost/costStep`、`ENERGY_INCOME_PER_UPGRADE`、`METAL_INCOME_PER_UPGRADE` |

## 7. 变更记录

| 日期 | 内容 | 状态 |
| --- | --- | --- |
| 2026-11-01 | 建立数值基线；确认 Legion 漏改、回血闭环缺失、伤害陷阱、武器/槽位不对称 | 已记录 |
| 2026-11-01 | P0：休整回血、清场 10%、脱战 0.25%/s、无人机 0.4%/架/秒与 45/60 救急带、阈值前移、Tier 4/9、防御保底、生命卡回血、护盾 2000/3500/5000、纳米修复降价、三阵营基础值统一、+40% 移入 Tweaks、修复 4 把商店武器缺 `roguelike_shop_item` | 已实施，待实机验证 |
| 2026-11-01 | P1 武器部分：Tzar 主炮 900→1100、狙击 3200→2800、覆盖炮 60→170/装填 7→6、冲击炮 190→340/装填 1.8→1.3、扩展卡 +25%/+30% | 已实施，待实机验证 |
| 2026-11-01 | 开局火力/自爆 P0：三族主普攻 420 射程、原装填×0.75、视野 520；Legion AA 与 ARM/Cortex Rogue AA 射程 480；Legkam 自动 AA 优先级提高；5 个自爆候选移出通用池，Wave 1–8 按权重/并发/间隔/距离/警报调度 | 代码已实施；未实机验证。敌人 HP 曲线、D-Gun、回血、升级、商店未改 |
| 2026-11-01 | Roguelike 指挥官移速 60→84（+40%）；无人机目标搜索/视野统一到 800，ARM 攻击槽指定 SURFACE；待吸收敌军残骸免疫普通武器/爆炸伤害，D-Gun 击杀排除回收 | 代码已实施；无人机攻击和残骸保留须实机验证 |
| 2026-11-01 | P1 结构部分：敌方压力曲线、伤害陷阱 | 未实施 |
| 2026-11-01 | 三阵营武器槽修复与 12 款专属武器：新增 catalog、synced 战斗结算、装备上限/切换、商店卡片与 L1-L3 | 代码已实施；静态检查完成，未实机验证 |
| 2026-11-01 | 单人及双人 Coop 波间 30→0 秒，商店全天开放；双人暂沿用单人敌人数、HP、伤害和击杀阈值，敌方 HP 不累加两人攻击倍率 | 代码已实施；仅双人无界面加载检查通过，续航和双客户端战斗未实机验证 |
| 2026-11-01 | 修正仍存在的 25 秒停刷清场：改为每秒补充刷怪额度、每 4 秒按时间目标数补兵，70 秒边界保留残敌并立即进入下波；HP/伤害公式不变 | 单人 headless 通过第 1→2、2→3 波时间边界，未见 Roguelike GameFrame 错误；实战敌人密度和续航未验证 |

### 三阵营专属武器参数记录（初始目标，未实测）

下表记录 UnitTweaks 与 catalog 当前配置，不代表实机有效射程、命中率或 DPS。专属武器修改前不存在（无 WeaponDef、槽位、商店项和升级等级）；本轮没有修改现有回血、升级卡、通用商店和 D-Gun 数值。专属武器原生 WeaponDef 伤害为 0，synced Gadget 在触发攻击行为时通过 `Spring.AddUnitDamage` 结算；手动伤害能否完整复用护盾/护甲、倍率和引擎调用次序仍须实机确认。

| 阵营 / ID | 修改前 | L1 修改后（射程 / 冷却 / 伤害与机制 / 价格） | L2 | L3 | 标签 |
| --- | --- | --- | --- | --- | --- |
| ARM `rl_arm_photon_cleave` | 不存在 | 320 / 0.9s / 252 每目标、100°扇形最多5目标 / 950 M | 扇形125° | 最多7目标、伤害×1.15 | 近战、群攻 |
| ARM `rl_arm_prism_array` | 不存在 | 650 / 1.2s / 3束×120、最多3目标 / 1700 M | 每束伤害×1.2 | 最多4目标 | 远攻、群攻 |
| ARM `rl_arm_sky_piercer` | 不存在 | 850 / 4.5s / 2250、穿透最多3目标、后续×0.45/×0.20 / 3200 M | 冷却4.0s | 首目标精英/Boss伤害×1.25 | 远攻、单发高伤害 |
| ARM `rl_arm_focus_annihilator` | 不存在 | 500 / 0.2s / DPS 100起、每秒+95、上限480 / 2700 M | 升温速度×1.2 | 换目标保留25%已积累超额DPS | 持续伤害 |
| COR `rl_cor_shock_maul` | 不存在 | 155 / 1.4s / 300、半径120、最多12目标、普通目标击退 / 1000 M | 半径140 | 伤害×1.2 | 近战、群攻 |
| COR `rl_cor_napalm_mortar` | 不存在 | 590 / 2.3s / 爆炸400、半径110、最多12目标、燃烧35 DPS×4s / 1850 M | 爆炸伤害×1.2 | 燃烧5s | 远攻、群攻、持续伤害 |
| COR `rl_cor_molten_core` | 不存在 | 650 / 5.0s / 2550、半径90、最多8目标、边缘最低×0.25 / 3300 M | 冷却4.5s | 伤害×1.25 | 远攻、群攻、单发高伤害 |
| COR `rl_cor_inferno_sprayer` | 不存在 | 270 / 0.2s / 65°锥体、30直伤/发+60燃烧DPS×1s / 2500 M | 锥体85° | 燃烧伤害×1.25 | 近战、群攻、持续伤害 |
| LEG `rl_leg_thermal_cutter` | 不存在 | 185 / 0.2s / DPS 130起、3s升至260，轻型目标减速12% / 950 M | 达峰2.5s | 峰值DPS×1.2 | 近战、持续伤害 |
| LEG `rl_leg_hive_hunters` | 不存在 | 630 / 2.0s / 每轮4×150、最多4目标、每目标最多2弹 / 1800 M | 每弹伤害×1.2 | 每轮5弹、每目标仍最多2弹 | 远攻、群攻 |
| LEG `rl_leg_rail_impaler` | 不存在 | 820 / 4.5s / 2000、最多穿透3目标、后续×0.65/×0.42 / 3100 M | 冷却4.0s | 衰减改为×0.75/×0.55 | 远攻、单发高伤害 |
| LEG `rl_leg_heat_suppression` | 不存在 | 480 / 0.2s / 最多2目标、DPS 150起至180、普通目标减速18% / 2450 M | 每束伤害×1.15 | 最多2邻近目标承受25%溅射 | 远攻、群攻、持续伤害 |

L2/L3 价格为基础价的55%/85%；同款复购用于升级，不生成新实例。首三款首次购买时在空位允许下自动装备；同时装备上限3。第4款仍可购买/升级但默认未装备，需先卸下一款再装备。表中 DPS 是静态目标计算值，不是实战测量值。

### 通用槽位前后与升级链路核对

| 阵营 | 改动前 | 改动后（仅 Roguelike） |
| --- | --- | --- |
| ARM | 原版槽1-3（普攻、海军激光、D-Gun）；无通用商店槽 | 2026-11-02 当前：主激光槽1、手动 D-Gun槽2、Rogue AA槽3、护盾槽4；已购通用/专属武器由 Synced 攻击控制器触发，不占实体槽位 |
| COR | 原版槽1-3（普攻、海军激光、D-Gun）；早期 Rogue 写死槽4重复普攻的风险 | 当前动态流程保留原槽1-3，Rogue AA槽4，通用商店槽5-9，COR专属槽10-13 |
| LEG | 原版槽1-4（普攻、鱼雷、D-Gun、AA）；无通用商店槽 | 原槽1-4保留，通用商店槽5-9，LEG专属槽10-13 |

2026-11-02 隔离 headless 检查：Recoil `2026.07.04` 的双玩家启动脚本加载了 `Roguelike Upgrades` 和 ARM 商店攻击 Gadget；日志报告 ARM 为 **4 个实体武器槽、9 个商店 WeaponDef**，第 1 波在第 150 帧生成。首次加载曾触发升级 Gadget 的 Lua 200 局部变量上限；将 30 个 Spring API 局部别名改为直接调用后，同一启动脚本可加载。此检查只证明定义与 Gadget 载入，**未实测**购买、开火、弹道、D-Gun 手动操作、盾反弹、击杀归属、回放或联机同步。实机需分别购买五款通用武器和四款 ARM 专属武器，并检查购买前零触发、购买后发射与升级词条。

新槽位使用独立 WeaponDef 副本与稳定 ID；原版基础普攻、D-Gun 与通用购买 ID 保留。静态调用链显示：伤害卡/商店伤害倍率在 `UnitPreDamaged` 作用于指挥官来源伤害；射程经 `roguelike_range_mult` 与 `SetUnitWeaponState`；装填、移速经 `GG.UpdateUnitAttributes`/RulesParam；生命经 `SetUnitMaxHealth`；护甲与护盾在承伤 `UnitPreDamaged` 中结算。以下是静态代码确认，不等于实机验证：

| 属性 | 指挥官写入/生效路径 | 当前静态状态 | 实机结果 |
| --- | --- | --- | --- |
| 伤害 | `cumulativeMultipliers.damage` → `UnitPreDamaged`；专属手动伤害传 attackerID/weaponDefID | 调用链存在 | 未验证实际倍率是否恰好一次 |
| ARM 初始武器池 | 主激光槽1、手动 D-Gun槽2、Roguelike AA槽3、护盾槽4；通用/阵营商店武器购买后由 Synced 触发 | 原有商店价格与等级沿用；虚拟通用武器复用 WeaponDef，阵营武器复用既有效果结算 | 源码已改；射击、弹道、护盾、Boss、双人同步未实机验证 |
| 射程 | `cumulativeMultipliers.range` → `applyWeaponRange` / `roguelike_range_mult` | 原生槽与专属效果均有路径 | 未验证武器实际射程 |
| 装填 | RulesParam `selfReloadSpeedChange` → `GG.UpdateUnitAttributes` | commander 有统一路径 | 未验证自定义类型冷却变化 |
| 移速 | RulesParam `selfMoveSpeedChange` → `GG.UpdateUnitAttributes` | commander 有统一路径 | 未验证游戏内移速 |
| 生命 | `SetUnitMaxHealth` 与 `SetUnitHealth` | commander 有统一路径 | 未验证升级、恢复量与 HUD |
| 护甲/护盾 | `UnitPreDamaged` 承伤钩子和护盾状态 | commander 有统一路径 | 未验证自定义伤害与防御交互 |

### 静态检查结果、风险和实机测试

- 静态核对三族各4个稳定 ID、五种标签覆盖、阵营/阶段/解锁/等级/槽位/金属校验、首次装备和3槽上限、UI 未解锁预览与等级状态。
- 已修正 WeaponDef 类型字段为 BAR 使用的 `weapontype`；修正 LEG 三级压制束把主目标重复计为溅射且绕过升温伤害；区分 `GetProjectileTarget` 的 ASCII 类型码与 `GetUnitWeaponTarget` 的数字枚举；DoT/减速在目标不再是敌军时清理。
- 风险：原生0伤害 Cannon/Missile 是否仍按预期触发 Projectile/Explosion 回调；手动伤害与伤害升级、护盾/护甲及自伤标志的交互；多目标密集波次的 CPU 开销。蜂巢武器的基础 WeaponDef 以4枚原生齐射作视觉，synced 命中按等级分配4/5次伤害；升级到L3后的第5次伤害目前没有额外可见导弹，需实机评估并在需要时补足表现。
- 当前环境没有 `lua`/`luac`/`luajit` 命令，也没有运行 BAR 对局。**引擎与实战测试均未验证**，不得将设计目标称为已验证结果。

实机步骤：固定地图/难度/随机种子，分别用 ARM/COR/LEG 检查开局与升级后普攻射程、装填和伤害；购买各自4款专属武器并记录 WeaponDef 槽、目标类别、射程、实际每发伤害、冷却、价格；逐款升 L2/L3；使用密集地面群、空军、高速敌人和首领检查扇形/爆炸/燃烧刷新/穿透衰减/追踪弹分配/升温/减速；验证装备3槽与卸装重装、回血、升级卡、D-Gun、通用武器无回归；记录日志、TTK和帧率。最后关闭 Roguelike 对比标准 BAR 三族 commander 参数。本表全部游戏内结果仍为“未验证”。

## 2026-11 Roguelike adjustment: ARM Photon Cleave and shield

| Item | Previous target | New code target | Status |
| --- | --- | --- | --- |
| ARM Photon Cleave | 160 range / 0.9 s / 180 damage per target | 320 range / 0.9 s / 252 damage per target / 100-degree frontal cone / up to 5 targets | Implemented in catalog and synced cone routine; engine/gameplay not tested |
| Commander shield | Virtual absorption only; 2000 / 3500 / 5000 capacity | Visible native projectile shield, repulses/intercepts projectiles; current power synchronized with virtual damage handling and energy-funded recharge | Implemented in Roguelike UnitDefs and synced gadget; engine/gameplay not tested |

Photon Cleave damage is 180 x 1.4 = 252. No enemy health growth, healing, upgrade cadence, shop, or D-Gun values were changed in this adjustment. The cone should face the active weapon target and hit eligible surface units within its range and angle. A UnitWeaponFired callback previously relied on an optional fifth WeaponDef argument; it now resolves the definition from the firing unit's weapon slot when absent, so BeamLaser-based cone effects can dispatch.

Risks: shield projectile interception uses the engine's `intercepttype=479` coverage and may not catch every custom projectile category. The visible shield radius and repulsion strength may need visual/gameplay tuning. Cone orientation follows the currently selected target, so behavior under rapid target switching needs in-game review. No live BAR match has verified these changes.

In-game checks: enable Roguelike and ARM; acquire shield capacity; verify the shield bubble appears, absorbs or repels incoming projectiles, current shield HUD decreases, and recharge begins after 4 seconds only while team energy is available (3% capacity per second, 0.8 energy per shield point). For Photon Cleave, equip it and attack a cluster of at least five surface units at 100, 300, and beyond 320 elmos; check targets inside/outside the forward 100-degree cone, damage near 252 per hit, 0.9-second cadence, level upgrades, and behavior when the target changes.

## 2026-11 Coop survivability expansion

Implementation status: code and static source checks only; no gameplay numbers below are marked as BAR-verified. The shared AllyTeam heal cap resolves the spec's Medical Beacon conflict: 12% total per target over 8 seconds is 1.5% max HP/second, matching the sustained-heal ceiling. Beacon duration is therefore 8 seconds (the input draft's 6-second duration would exceed that ceiling).

### Base skills, pickups, cards and faction skills

#### 第一阶段：基础生存、补给与升级卡

| System | Previous behavior | New configured value | Status |
| --- | --- | --- | --- |
| Emergency Nanorepair | No player-triggered baseline skill | 15% max HP over 5 sec; 180 energy; 50 sec cooldown | Implemented synced; not gameplay-tested |
| Emergency Thruster | No player-triggered baseline skill | +45% move speed for 2 sec; 30 sec cooldown | Implemented through UnitAttributes modifier; not gameplay-tested |
| Combat medkit | No Roguelike healing pickup | One per 14 kills solo / 19 kills with 2 teams; max 4 alive; 20 sec TTL; 100 elmo pickup; 6% max HP; per-player 5 sec pickup cooldown | Implemented as synced Gaia feature; not gameplay-tested |
| Combat Regeneration I-III | No in-combat card heal | 0.2% + 0.1% + 0.1% max HP/sec; maximum 0.4% | Card pool and synced heal path implemented; not gameplay-tested |
| Blood Recycle I-II | No kill healing card | 0.6%, then 0.8% max HP per eligible kill; 550 elmo; per-Team 2 sec cooldown | Implemented; not gameplay-tested |
| Blast Lining I-II | Existing armor and focus guard only | 20%, then 30% reduction against tracked `legkam`, `armvader`, `corroach`, `corsktl`, `legsnapper` damage | Spawner tags and synced mitigation implemented; damage channels not gameplay-tested |

#### 第二阶段：阵营主动技能与团队治疗

| System | Previous behavior | New configured value | Status |
| --- | --- | --- | --- |
| ARM Photon Buffer | Existing shield upgrade/native shield remains | Separate 1600-point barrier for 6 sec; 48 sec cooldown | Implemented; not gameplay-tested |
| COR Heavy Reinforcement | Existing armor/focus guard remains | 25% incoming damage reduction for 6 sec; 48 sec cooldown | Implemented; not gameplay-tested |
| LEG Nano Coordination Repair | Existing drone repairs remain | Self + most injured in-range teammate; 0.7% max HP/sec for 7 sec; 350 elmo; 55 sec cooldown | Implemented with shared 1.5%/sec recipient cap; not gameplay-tested |
| Medical Beacon | No team healing active skill | 350 energy; 350 elmo radius; up to 12% target max HP over 8 sec; 65 sec per-user cooldown; only one active beacon | Shop item and synced effect implemented; not gameplay-tested |

### Before/after healing and mitigation paths

| Path | Before | After implementation | Synced state |
| --- | --- | --- | --- |
| Drone commander repair | Drone gadget directly set commander HP after energy debit | Calls `GG.Roguelike.HealCommander`; 0.75 energy per actual HP, +50% nominal healing per drone and shared sustained cap | Per-Team heal budget and total |
| Passive and combat regeneration | Direct or isolated per-second health update | Central healing helper and shared sustained cap | Per-Team budget, rate and total |
| Wave-clear and purchased regen heal | Direct health write | Central helper; wave-clear/shop regen are discrete sources outside the sustained budget | Per-Team heal totals |
| Damage protection | Native shield, armor, focus guard | Add marked-suicide reduction, COR timed reduction and ARM barrier in the same synced damage pipeline; native shield remains independent | Per-Team barrier/cooldown; UnitRulesParams for HUD |
| Coop state | No survival-skill state | Cooldowns, heal budget, blood cooldown, barrier, and activity snapshot by Team; one global active instance for each team-aura type | RulesParams visible to the owner's HUD |

### Static arithmetic examples and remaining tests

At 10,000 max HP, the sustained cap is 150 HP per one-second bucket. Base regen at 0.25% is 25 HP/s, Combat Regeneration III at 0.4% is 40 HP/s, a tier-I blood-recycle event requests 60 HP, Nanorepair requests 1,500 HP over five seconds, a medkit requests 600 HP, and an eight-second beacon requests 150 HP/s for at most 1,200 HP per target. LEG Repair Link requests 70 HP/s to each of two commanders; each target is independently clamped to 150 HP/s. Those are code-derived examples, not observed in a match.

Potential issues: feature model path/visibility and collision need engine validation; `CreateFeature`/FeaturePreDamaged behavior can vary with the installed engine; explosive attacker attribution must be confirmed for each self-destruct weapon; native shield and temporary barrier ordering needs combat tests; short cooldowns and aura snapshots must be checked after player reconnect/death; current team-size drop threshold may make pickups too sparse in Coop; healing budget uses fixed one-second buckets rather than a rolling second. No normal BAR UnitDef or stock commander is changed, and the Roguelike gadgets return early when the mode is off.

Test data required before balance sign-off: record BAR/engine build, map, mode options, faction, team count, max/current HP, energy before/after, cooldown frames, observed heal per second, shield/barrier remaining, and feature spawn/pickup/expiry count. Run (1) source/RulesParam checks for all base abilities, (2) simultaneous drone+passive+combat regen to verify <=1.5%/s, (3) every suicide unit and ordinary attacker against Blast Lining 0/20/30%, (4) same-frame beacon/Repair Link requests from two clients, (5) one feature pickup race, TTL and four-feature cap, (6) damage then cooldown/reconnect/death, and (7) Roguelike-off vanilla BAR regression. Current static code confirmation: configured values and synced entry paths exist. Actual match/2-client result: **not tested**.

### 2026-11-01 combat log review: Blood Recycle and drone repair

Reviewed `D:/BeyondAllReason/Beyond-All-Reason/data/infolog.txt` (latest game session reached wave 3). The log records Blood Recycle I acquired at frame 2242, then continued wave kills and medkit spawn/pickup events. This confirms the shared tracked-kill callback is firing in that match. The old Blood Recycle path emitted no diagnostic result, and the log contains no BloodRecycle heal records, so it cannot distinguish out-of-range kills, full health, cooldown or the shared heal cap. No Upgrades/Spawner Lua error was found in the session; unrelated SSAO widget errors were present. The synced code now records those rejection counters in commander RulesParams and writes one summary line per 10 seconds while the upgrade is owned; positive heal amounts are included. This diagnostic patch has not yet been exercised in a new match.

Drone repair changed from 0.4% max HP/second per drone at 1 energy/HP to 0.6% at 0.75 energy/HP. At 10,000 max HP, two drones request 120 HP/s and cost 90 energy/s before the shared 150 HP/s sustained-heal ceiling. This gives 50% more nominal throughput and 33% more healing per energy than the previous setting; actual in-match throughput remains unverified.

## Roguelike special weapon effects — prototype values (2026-11-01)

These are implementation defaults for isolated test weapons, not final balance values. The test weapons are only inserted into the ARM Roguelike commander when `roguelike_weapon_effect_tests` is enabled. No successful match has loaded or fired them, so all numbers below are **unverified**.

**2026-11-02 visual/activation correction, unverified:** meteor activation is now a ground-target command on the ARM test commander, not a firing weapon slot. It queues the warning and spawns the payload at the target's ground position plus 900 elmos. The payload and every synced meteor spawn explicitly use the existing `meteor.s3o` model and `meteortrail` CEG tag. The earlier commander-weapon trigger could look like a projectile launched at the target; this correction has not yet been confirmed in a game.

| Prototype | Initial values in code | Upgrade range in code |
| --- | --- | --- |
| Ground-target Meteor Strike command | 900 elmos command range; 2.8 s cooldown; 1 meteor per cast; 45-frame warning (1.5 s at 30 FPS); visible projectile starts 900 elmos above the target at 24 elmos/frame downward; base damage 500 default / 300 subs / 250 VTOL; WeaponDef AoE diameter 260 | Count 1–5; damage radius 80–360 (runtime AoE diameter is twice the radius); interval 0.6–8 s; damage multiplier 0.5–3; split off/on |
| Splitter missile | MissileLauncher; range 700; reload 2.2 s; 180 default damage; tracking enabled; impact split by default | Child count 2–8; depth 0–3; homing off/on; damage falloff 0.25–0.95 per generation; impact/timed/in-flight mode |

Safety limits in `unitbasedefs/roguelike_weapon_effects.lua`: 256 active tracked projectiles globally, 48 per owner, 16 pending meteors per owner, at most 16 projectile spawns per simulation frame, and recursion depth 3. Timed split starts at 45 frames; in-flight split starts after 300 elmos of horizontal travel. These caps and split triggers need pressure testing. All player-facing progression remains per commander RulesParam; the current phase does not alter the faction weapon shop, existing shop levels or the proposed independent WeaponLevel Lv.1–6 system.

### Prototype verification status

- Static review confirmed the installed `spring-headless.exe` reports Recoil `2026.07.04`; the available documented APIs include `Spring.SpawnProjectile`, projectile target/damage setters, `ProjectileCreated`, and watched `Explosion` callins. The workspace Recoil Lua API submodule is not initialized, so local type stubs were unavailable.
- `git diff --check` passes. `lx --lua-version 5.1 test` and StyLua could not run because `lx` and `stylua` are not installed.
- Headless launch did not reach game loading: the isolated local start script could not resolve the installed map archive as `AcidicQuarry`. This is a pregame setup failure, not a successful Gadget test.
- Projectile trajectory, warning visibility, damage/radius scaling, shields, self/ally damage, elite/Boss response, replay determinism, two/four-player sync and four-player performance are **not tested**. Do not connect these prototypes to faction shop items until those cases pass in a real match.

# 2026-11 PokeBonk progression refactor — Phase 1 (implemented, unverified)

This entry records the first-stage progression rewrite based on `BAR_Roguelike_PokeBonk_Progression_Codex_Spec.md`. All values below are provisional test values. Code review only was performed; no BAR match, solo run, two-player run, HP measurement, weapon DPS measurement, desync check, or vanilla regression run has verified gameplay behavior.

## Audit findings before the change

- `game_roguelike_upgrades.lua` previously treated kills as direct upgrade thresholds: `25, 50, 100, 185, 280, 400, 550, 730, 940, 1180, 1450, 1750, 2080, 2440`. It held at most one pending choice per Team and advanced Tier 2/3 from the number of selected cards.
- The old `getDifficultyScaledGrowth()` ran on every selected card and multiplicatively added commander and summon health, damage, reload, movement, and range, plus armor and salvage radius. Its old per-card envelope was HP +4–8%, damage +2–6%, reload +1.5–5%, movement +1–4%, range +0.8–3.5%, armor +0.8–2%, and salvage radius +15–50 elmos, depending on combat time and target enemy count. That path has been removed to prevent new role levels and stat modules from stacking on top of it.
- Commander damage is applied once in the Rogue `UnitPreDamaged` attacker path. Store damage remains in the existing multiplier; role damage and the new damage module are separate additive bonuses in `effectiveDamageMultiplier()`. Existing weapon extensions still apply at their existing downstream branch. WeaponDef mode scaling (for example the Roguelike commander base weapon scale) remains a separate pre-existing factor.
- The shop's weapon extensions currently use their existing shop levels (several extend to level 3); these are not the proposed independent WeaponLevel Lv.1–6 system. No WeaponLevel storage, Lv.3/Lv.6 traits, or fusion was added in this phase.
- Spawner currently reports a single total-kill count and does not supply enemy-tier XP weights. The new XP conversion therefore uses total tracked kills normalized by Team count. The existing `GG.Roguelike.GetMultipliers()` still reports shop damage multipliers to the Spawner; the new role/module damage bonuses are not included there. The older shop-to-enemy-health coupling remains a separately tracked balance issue and was not redesigned here.

## Phase 1 values now in code

| System | Provisional value | Implementation note |
| --- | ---: | --- |
| Shared normalized XP thresholds | 25, 50, 75, 110, 145, 190, 245, 310, 395, 480, 565, 680, 850, 1100, 1400, 1750, 2150, 2600 | Cumulative team kills divided by roster normalization factor; no enemy class weight yet |
| Roster normalization | 1 / 1.6 / 2.1 / 2.6 for 1–4 players | Shared XP; not multiplied per player |
| Wave guaranteed offers | cumulative 2 / 4 / 6 / 8 / 10 / 12 / 13 / 14 / 15 / 16 by waves 1–10 | Uses max(XP offers, wave guarantee); XP may lead guarantee by at most one offer |
| Commander level | Lv.1 initial; +2% stable base HP and +1% direct damage for each gained level | Additive; level-up HP only fills the newly gained maximum HP |
| Stat modules | Four distinct module types per player; max 5 levels (range and regen max 4) | Only module slots count toward the four-type limit |
| Module per-level increments | Damage +8%, reload +8%, range +7%, health +12% base, move +5%, combat regen +0.1% max HP/s | Additive totals capped at +40%, +40%, +28%, +60%, +25%, +0.4%/s |
| Module rarity | Common / Uncommon / Rare / Epic = 1 / 1.25 / 1.5 / 2 times card increment | Module value clamps to its total cap |
| Rarity weights, waves 1–4 | 70% / 25% / 4% / 1% | Synced random roll |
| Rarity weights, wave 5+ | 55% / 32% / 11% / 2% | Synced random roll |
| Per-player controls | Refresh 2, Skip 1, Banish 1 per run | Skip gives 15 metal; requests validated in Synced |

The module types implemented are damage, reload, range, health, movement, and combat regeneration. Existing armor/shield, blast lining, blood recycle and drone cards keep their existing IDs and application code. An AoE module is deliberately absent: the current general WeaponDef path has no commander-local, per-Team radius modifier, so advertising it before implementing an authoritative path would make an ineffective card.

## Known risks and test plan

- Rarity multipliers may let one early Epic card reach a cap much sooner than a Common build. The strict cumulative caps prevent exceeding the listed bonus ceilings, but the feel and distribution are untested.
- The offer targets guarantee the target count only when each wave boundary callback occurs. A disconnect/reconnect, commander death/rebuild, or LuaUI reload must be checked to ensure queued offers remain visible and selectable exactly once.
- Team normalization currently uses configured roster size and raw tracked kills, not enemy health/elite/Boss weights. Measure each wave's XP/offers with one and two players before changing thresholds.
- Damage path static audit: level/module bonus is combined once with the existing shop damage multiplier and applied in `UnitPreDamaged`; verify native weapons, faction scripted `AddUnitDamage`, D-Gun exclusion, and weapon extensions in the engine.
- Role growth no longer automatically grows summoned units or salvage radius. Check whether the existing player-facing experience depended on these old automatic effects.
- The old shop damage multiplier's interaction with enemy health scaling is not changed in this phase. Check it separately before future balance tuning so player damage does not silently make enemies tougher.

In-game verification: enable Roguelike, record build hash and seed, then run ARM/COR/LEG solo and with two same-AllyTeam players. At each wave boundary record team XP, each player's level and offer count, max/current HP before and after a level, commander direct damage, attack interval, shop damage/range/reload levels, module level/value/rarity, healing per second, and current metal. Exercise refresh/skip/banish including repeated messages, LuaUI reload, commander death and recovery, and simultaneous Coop picks. Confirm D-Gun, shop, weapons, shield, healing skills and drone repair remain functional. Disable Roguelike and compare vanilla commander stats/weapons. Until those steps are run in BAR, mark every result **unverified**.

## 2026-11-01 native XP audit and fast role progression (implemented, unverified)

This change separates Roguelike commander role levels from card offers. The earlier Phase 1 table above records the prior implementation and is superseded for role-level values by this section; card thresholds, wave guarantees, stat-module values and weapon levels remain unchanged.

### Audit and implementation

- `game_roguelike_spawner.lua` reports one authoritative cumulative kill count for tracked enemy deaths. `game_roguelike_upgrades.lua` divides that count by the configured 1/1.6/2.1/2.6 roster coefficient and shares the normalized XP with each participating Team. Coop state already stores role level, XP, card offers and loadout separately per Team; this implementation continues that path.
- Roguelike role XP does not use `Spring.AddUnitExperience`, `Spring.SetUnitExperience` or `Spring.SetExperienceGrade`; it uses normalized tracked kills. Native UnitXP and its HUD rank remain on the original BAR engine path. BAR's global `modrules.lua` sets native `healthScale = 2.5` and `reloadScale = 1.25`, so native veterancy can independently affect commander health/reload as well as Rogue role growth. The two XP values are not mirrored or summed into one another; card offers are also independent of role levels. Measure their combined effect in game before final balance tuning.
- `commanderLevel` no longer increments when a card offer is granted. Role level is calculated from cumulative role XP and capped at Lv.60. The XP threshold for the next level is `ceil(22 + 2.5*(L-1) + 0.18*(L-1)^2)` from current level L.
- Each role level adds +1.2% of stable base maximum HP and +0.8% direct commander damage. Damage is applied once by the existing Roguelike `UnitPreDamaged` commander attacker path alongside shop and stat-module bonuses. The level-up HP path adds only the maximum-HP delta to current HP; it does not fully heal or repeatedly compound the stable base.
- `roguelike_role_xp`, `roguelike_role_next_xp` and `roguelike_level_max` RulesParams now provide the actual within-level HUD progress. Card offer thresholds and wave guarantees are unchanged, so role levels do not add cards. Weapon Lv.1–6, shop, D-Gun, healing and other modes are untouched by this patch.

### Static progression estimates

The following levels are calculated from the proposal's historical normalized-XP assumptions, not measured in a game. Lv.60 requires 17,610 cumulative normalized XP with the implemented curve.

| Wave end | Assumed cumulative normalized XP | Calculated role level | Role HP bonus | Role direct-damage bonus | Runtime status |
|---:|---:|---:|---:|---:|---|
| 1 | 51 | 3 | +2.4% | +1.6% | Estimate; unverified |
| 2 | 119 | 5 | +4.8% | +3.2% | Estimate; unverified |
| 3 | 211 | 7 | +7.2% | +4.8% | Estimate; unverified |
| 4 | 331 | 10 | +10.8% | +7.2% | Estimate; unverified |
| 5 | 492 | 12 | +13.2% | +8.8% | Estimate; unverified |
| 6 | 706 | 15 | +16.8% | +11.2% | Estimate; unverified |
| 7 | 994 | 18 | +20.4% | +13.6% | Estimate; unverified |
| 8 | 1300 | 20 | +22.8% | +15.2% | Estimate; unverified |

| Level milestone | Cumulative normalized XP required |
|---:|---:|
| Lv.10 | 328 |
| Lv.20 | 1,233 |
| Lv.30 | 3,053 |
| Lv.40 | 6,149 |
| Lv.50 | 10,882 |
| Lv.60 | 17,610 |

### Test record and remaining risks

- Static code review and arithmetic only. No BAR runtime test has confirmed the first-eight-wave XP, levels, health, damage, Coop synchronization, disconnect/rebuild recovery, LuaUI display, or Lv.60 cap. All are **待实机验证**.
- Run a solo ARM/COR/LEG match and a two-player Coop match. At each wave boundary record `roguelike_shared_xp`, `roguelike_level`, `roguelike_role_xp`, `roguelike_role_next_xp`, `roguelike_offers_earned`, current/max HP, and commander direct damage. Confirm levels match between Coop players while card/loadout states remain independent.
- Confirm exactly one tracked enemy death increments shared XP once; test self-destructing enemies and player-owned meteor/splitter damage for duplicate XP; exercise commander death/rebuild and a late join/reconnect; confirm level remains 60 after further kills.
- Confirm native UnitXP stars remain visible while shared normalized XP advances separately. Measure native veterancy health/reload deltas independently from role-level HP/damage and verify card offers do not change role level. D-Gun, self-damage, allied damage, shields, periodic damage and weapon extensions require separate in-game checks.
- Disable `roguelike_mode` and compare standard BAR and other PVE modes. No global modrules, UnitDef veterancy parameters, weapon definitions, or non-Roguelike Gadget behavior was changed; the new role XP path is gated by the Roguelike-only Gadget.
# Roguelike effect framework P1 source implementation (2026-11-01)

This section records the first source implementation for `BAR_Roguelike_Mechanics_Expansion_Codex_Spec_v1.md`. The values below are provisional. **No new effect has been validated in a BAR match**, so code presence and static caps must not be reported as gameplay or performance validation.

## Implemented IDs and first-pass values

| Effect ID | Initial behavior and values | Current hookup | Verification |
|---|---|---|---|
| `chain` | 18% base chance × attack proc coefficient; radius 230; two jumps at 45% and 32% primary-hit damage; 12-frame owner cooldown | ARM prism array and LEG heat suppression upgrades; primary hit bus | Source only; unverified |
| `ricochet` | 20% × proc coefficient; radius 220; one secondary target at 35%; 12-frame cooldown | ARM photon cleave and LEG hive hunters upgrades | Secondary damage is applied directly; visible projectile redirection is not implemented; unverified |
| `burst` | 20% × proc coefficient; radius 120; 30% source-hit damage; at most 8 targets; 30-frame cooldown. ARM focus annihilator uses a 12% base on-kill chance × its 0.6 attack proc coefficient | ARM focus annihilator and shop shockwave extension | Hit/kill routes are source-implemented; kill callback ordering and damage attribution unverified |
| `burn_zone` | Radius 110; 24% primary-hit damage every 12 frames for 90 frames; at most 12 targets/tick; 45-frame cooldown | COR napalm/inferno, LEG thermal cutter, shop barrage extension; automatic meteor weapon Lv.2 attaches the same capped zone at impact | Generic and meteor impact area state exists; damage/visual timing unverified |
| `aftershock` | Radius 100; 35% primary-hit damage; delay 18 frames; 90-frame cooldown; at most 12 targets | COR shock maul/molten core and shop plasma extension | Source only; unverified |
| `delayed_strike` | Radius 130; 45% primary-hit damage; delay 30 frames; 45-frame cooldown; at most 12 targets | ARM sky piercer/LEG rail impaler and shop sniper extension | Source only; unverified |

Effect unlocks use the existing three-level faction weapon catalog's first upgrade level; no new shop state system or weapon slot was created. Standard projectile extension mapping currently covers plasma, sniper, barrage and shockwave shop weapons. This does not yet constitute a general projectile count/level upgrade for every projectile attack.

## Code-level limits (not measured performance)

| Budget | Current cap in source | Meaning |
|---|---:|---|
| Effect proc depth | 1 | Proc damage does not re-enter the effect bus |
| Effect starts | 16/frame, 4/owner/frame | Extra effects are rejected and counted |
| Burn zones | 3/owner | Duplicate nearby zone refreshes the existing zone |
| Area status records | 12/owner; 48 global | Current global cap assumes at most four owners |
| Targets per area tick | 16 | Target selection holds only the nearest capped set |
| Tracked projectiles | 48/owner, 256 global | Existing meteor/splitter tracking caps retained |
| New projectiles | 16/frame | Existing synced spawn queue cap retained |
| Split depth | 3 | Existing split prototype cap retained |

Static worst-case note: the area status code can have up to 48 global records; current registry entries select at most 12 targets each, so at most 576 area damage applications could align on one frame. This is a source-derived upper bound, not an observed frame cost; staggered ticking/bucketing has not yet been implemented. `GetUnitsInCylinder` still traverses returned nearby units even though only a capped nearest set is retained. Measure Gadget time and sim speed in a 4-player late-wave match before raising any cap.

## Changed files and verification record

- `unitbasedefs/roguelike_weapon_effects.lua`: registry, common projectile extension mapping, caps, and existing meteor/splitter definitions.
- `unitbasedefs/roguelike_weapon_catalog.lua`: effect unlocks on current ARM/COR/LEG weapon progression.
- `luarules/gadgets/game_roguelike_weapon_effects.lua`: Roguelike-only synced executor, event and area states, owner cleanup, diagnostics, and purchasable automatic meteor attack source reusing the existing warning/falling payload.
- `luarules/gadgets/game_roguelike_faction_weapons.lua`: existing scripted faction damage path calls the shared effect bus.
- `weapons/roguelike_meteor_payload.lua`: expose the existing payload to the Roguelike shop attack independently of the developer test flag.
- `effects/roguelike_weapon_effects.lua`: low-cost groundflash markers for burn zones, aftershocks and delayed strikes.
- `luarules/gadgets/game_roguelike_upgrades.lua`, `luaui/RmlWidgets/gui_roguelike/gui_roguelike.lua`: meteor shop entry.
- `docs/roguelike/current-implementation-audit.md`: audit snapshot and implementation gaps.

Static source review confirms the mode guard and source-level limits. Lua parser/test runner was not available in the current environment, and no BAR match was run. **Runtime correctness, multiplayer determinism, replay, shield interaction, Boss mitigation, damage/XP attribution, simulation cost, FPS, and standard BAR/Raptors regression remain unverified.** The meteor shop item is an automatically scheduled attack source, not a spawned autonomous UnitDef. `ricochet` is not visual projectile redirection. Follow the test matrix in `RoguelikeMaintenanceManual.md` before treating P1 acceptance as complete.

## 2026-11-01 综合审计修复：派生伤害与预算口径

本节覆盖前文效果框架同日首次实现记录的对应项。机制修复见维护手册，完整证据见 [综合审计](../docs/roguelike/audit-2026-11-01.md)。

| 项目 | 修复前 | 当前 | 验证 |
|---|---|---|---|
| 通用弹丸派生伤害基数 | UnitDamaged 的最终伤害，再走 AddUnitDamage 成长 | WeaponDef default 基础伤害 × 弹丸自身damageScale，再经原Synced伤害管线一次 | 模拟100基础/200最终命中，余震输入35而非70；实机待验证 |
| 各种目标防御、溅射边缘 | 以首个目标最终承伤为基数，会把首目标减伤与成长带到其他目标 | 以母弹基础伤害为基数，各派生受击者走自己的防御管线；不复制首目标的溅射边缘比例 | 实机护盾、装甲、Boss限伤待验证 |
| 每帧新增弹丸16 | 分裂调用上下两层各扣1次，有效最多约8次尝试 | 单个生成尝试扣1次；保持总预算16 | 模拟2份预算可生成2颗，未提高配置上限 |
| 已排队陨石 | 到期先出队，满容量或Spawn失败丢失 | 容量不足/生成失败留队重试 | 玩家上限、全局上限、生成失败3种模拟均通过 |
| 主弹和附加效果预算 | 跟踪预算满可能删除通用主弹 | 保留通用主弹，只跳过本次附加效果并计拒绝 | 模拟通过 |
| 火区3/owner | 总区域数也被当作火区数 | 火区数量独立计数，总区域仍12/owner、48全局 | 3个余震不再阻止首个火区；模拟通过 |

连锁/反弹/爆裂概率、半径、伤害比例、陨石等级、角色成长、商店价格、敌人HP/伤害曲线均未重新调参。此次用于消除逻辑冲突，不能据此宣布平衡达标。

历史审计时待修项目：敌人HP随玩家攻击倍率增长、D-Gun通用伤害倍率、选卡0.1金属/秒；这些已在本轮源码修正，以上方新节为准。原生老兵生命/装填与角色成长的叠加仍待实机核查。

本轮22/22 Lua5.1语法、11/11模拟回调通过。未运行新BAR对局，暂无实测DPS、Boss TTK、帧耗、模拟速度或FPS。此前“工具未安装”是历史记录；现可按 `tools/roguelike/README.md` 重跑隔离验证。

## 2026-11-01 伤害吸血与战斗治疗

本节为本轮代码建议值；未在 BAR 对局实测。规则仅由 Roguelike 模式 Gadget 执行，使用现有 `HealCommander` 入口和 Coop Team 状态。

| 机制 | 初始/升级值 | 限制与结算 |
|---|---:|---|
| 能量汲取 I/II | 12% → 18% 有效直伤 | 伤害触发治疗独立上限 0.6% MaxHP/秒；和 1.5% 持续治疗总预算同时受限 |
| 纳米回馈 I/II | 每次 0.12% → 0.20% MaxHP | 同目标 0.25 秒最多一次；与吸血共用 0.6% MaxHP/秒 |
| 陨石中心命中 | 有效伤害 × 50% | 需有吸血卡；陨石边缘按范围伤害处理 |
| 分裂弹直击 | 有效伤害 × 35% | 归因保留 owner/team/root attack；同根攻击同目标去重 |
| 范围汲取 I/II | 范围有效伤害 × 20% → 25% | 需持有吸血卡和范围汲取卡；没有该卡时为 0 |
| 持续汲取 I/II | DoT 有效伤害 × 10% → 15% | 需持有吸血卡和持续汲取卡；以 0.25 秒窗口去重 |
| 战利品回收 | 击杀恢复 0.6% → 0.8% MaxHP | 保留 550 范围和每人 2 秒冷却，仍走 1.5% 持续预算 |

实际伤害通过目标击中前后生命差计算，并封顶在击中前生命；护盾吸收不扣目标 HP，因此不产生吸血。拒绝同队/友军、Gaia、中立、麻痹伤害和派生伤害回调。命中回血也要求目标实际掉血。每名玩家单独存储卡、归因事件和两类预算。普通 BAR 的加载不经过此 Roguelike Gadget。

举例（MaxHP=10,000、缺血充足、当秒无其他触发治疗）：直伤实际扣血 1,000 时 Lv1 名义吸血 120、Lv2 为 180，均因 60 HP/秒上限最多实际恢复 60；残血目标仅剩 50 HP 被 3,000 伤害击杀，只能贡献 6 HP 名义治疗（仍受同一 60 HP 预算）；命中回血 Lv1/Lv2 分别请求 12/20 HP/次。上限截断不结转到下一秒。

验证：Lua 5.1 语法解析 25/25；伤害规则纯函数用例 15/15；特殊武器模拟回调 14/14。性能：伤害回调仅在攻击者为拥有相关卡牌的 Roguelike 指挥官，或专属武器明确登记归因时记录生命快照；去重状态每 30 帧清理一次，事件保留 10 秒。Fengari 对纯规则函数运行 2,000,000 次约 2.522 秒（约 793,000 次/秒）。此基准不包含 Gadget、Spring API、Team 快照/恢复或引擎开销，不能外推为 BAR 帧耗。BAR Gadget 毫秒耗时、模拟速度和四人后期压力均未测，实机待验。

变更文件：`game_roguelike_upgrades.lua`、`game_roguelike_weapon_effects.lua`、`game_roguelike_faction_weapons.lua`、`gui_roguelike.lua/.rml`、`roguelike_damage_healing.lua`。验证用例和命令见 `tools/roguelike/README.md`。伤害回调顺序、过量伤害、护盾、多人归属、回放及UI需按维护手册实测后才可标为已验证。

## 2026-11-02 个人反弹盾审计修复

Roguelike 个人盾原先使用 `intercepttype=479`，且一些敌方武器明示 `interceptedbyshieldtype=0`，两处都会漏掉可拦截弹丸。现为 Roguelike 个人盾配置专用位 `16384`，并在模式开启时给所有非 Shield WeaponDef 加上该位；只有 Rogue 个人盾匹配此位，普通 BAR Shield 不改变拦截行为。盾仍使用原生 `repulser=true`，由引擎处理弹丸偏转和盾值消耗。`UnitPreDamaged` 仅同步原生盾值，不再对到达机体的溢出伤害二次扣盾，避免原生盾结算与 Lua 结算重叠。Roguelike 关闭时不添加该拦截位。

项目中未发现挂到 ARM 指挥官 UnitDef 的测试武器：ARM 只接入正式 Roguelike 商店/阵营武器槽与盾槽；`armcom_lus.lua` 的 `aux` 映射只是额外槽位动画/瞄准回调。分裂弹的 `testWeapons` 表仍是未挂载的原型数据，测试开关也排除 ARM。房间选项说明已改正。语法/模拟检查未覆盖 Recoil 原生盾拦截，反弹范围、耗电和弹丸偏转仍需实机验证；BeamLaser/LightningCannon 没有实体弹丸可反向飞回，只能拦截，不应标称“反射光束”。
