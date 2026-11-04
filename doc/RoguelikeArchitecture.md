# Roguelike 模式架构与逻辑注释规范

> 开发、游玩与部署入口：[统一总览](RoguelikeOverview.md)。最新效果接口修复和风险：[综合审计](../docs/roguelike/audit-2026-11-01.md)。

> **维护入口：** 后续玩法规则、平衡目标、界面行为和修改流程以 [Roguelike 模式维护手册](RoguelikeMaintenanceManual.md) 为准；本文件保留模块架构、权威状态和跨模块调用契约。玩法或接口变化时需同步更新两份文档。

本文档说明 Roguelike 模式各模块的职责、权威状态、调用链和注释要求。目标是让后续修改能够先找到真正的数据所有者，再修改最小范围的代码。

## 1. 运行层与权威边界

Spring 同一局游戏里有三个相关层次：

- **LuaRules synced Gadget**：保存和修改权威游戏状态。波次、生成、资源、升级、伤害、无人机修复都必须在这里决定，并保证所有客户端执行相同结果。
- **LuaRules unsynced Gadget**：接收 synced 事件并转发到本地界面，只承担跨层通知。
- **LuaUI / RML Widget**：显示状态和收集玩家输入。它可以发送请求，但不能自行决定扣费、回血、升级结果或伤害。

基本原则：UI 发出的 `Spring.SendLuaRulesMsg` 只是请求；synced Gadget 必须重新验证玩家、队伍、当前待选项、商品 ID、前置条件和价格。

双人 Coop 的共享状态是 Spawner 的 `GG.Roguelike.phase/currentWave/totalKills/teamIDs/teams[teamID].commanderUnitID`；个人状态在 Upgrades、Drones、Salvage 和 Faction Weapons 内按 Team 或 owner UnitID 保存。`GetPlayerInfo(sender)` 每次请求重新获取 Team，避免掉线重连后依赖旧 playerID。个人同步事件携带 TeamID，unsynced 只转发给本地 Team；LuaUI 重载时发送 `roguelike_sync` 拉取已购列表和未选卡。`roguelike_coop` 需与 `roguelike_mode` 同时开启，且仅支持同一 AllyTeam 的两支人类 Team。验收状态见 [RoguelikeCoopAudit.md](RoguelikeCoopAudit.md)。

## 2. 模块职责

| 文件 | 运行层 | 负责的状态与行为 | 不负责 |
| --- | --- | --- | --- |
| `luarules/gadgets/game_roguelike_spawner.lua` | synced | 波次状态机、敌军池、生成预算、敌军强化、追击、存活数和击杀数 | 升级奖励、商店、残骸奖励、无人机任务 |
| `luarules/gadgets/game_roguelike_upgrades.lua` | synced + unsynced 转发 | 共享 XP/个人等级、选卡与模块、商店验证与扣费、指挥官属性、护甲/护盾/治疗、伤害扩展 | 波次生成、RML 排版、无人机移动 |
| `luarules/gadgets/game_roguelike_salvage.lua` | synced | 敌军残骸白名单、指挥官/无人机吸收请求验证、金属奖励 | 决定无人机当前任务、商店消费 |
| `luarules/gadgets/game_roguelike_orbit_drones.lua` | synced | 无人机等级、生成补位、轨道移动、任务优先级、扣电修复、召唤物成长 | 选卡抽取、波次编号、UI |
| `luarules/gadgets/game_roguelike_weapon_effects.lua` | synced | 测试专用陨石与分裂弹的弹丸状态、归属、伤害倍率、升级 RulesParam 和生成上限 | 商店购买、WeaponLevel 1–6、原版武器效果 |
| `luarules/gadgets/unit_aa_targeting_priority.lua` | synced | 原版自动防空目标优先级；Roguelike 开启时读取自爆威胁标记，提高 `legkam` 自动拦截优先级 | 手动目标、单位伤害或波次生成 |
| `luaui/RmlWidgets/gui_roguelike/gui_roguelike.lua` | LuaUI | RulesParam 读取、RML 数据模型、选卡/购买请求、弹窗与输入隔离 | 权威属性、资源和伤害结算 |
| `gui_roguelike.rml` | LuaUI 结构 | HUD、升级卡、商店的元素层级与数据绑定 | 游戏逻辑 |
| `gui_roguelike.rcss` | LuaUI 表现 | 尺寸、网格、滚动、指针事件、类别悬浮发光 | 卡牌权重、商品合法性、战斗结果 |
| `unitbasedefs/roguelike_unit_tweaks.lua` | UnitDef 加载期 | 三阵营指挥官基础值、初始武器 +40% 缩放、雷霆参数、商店武器槽与 Tzar 主炮深拷贝 | 运行时状态与购买判断 |
| `scripts/Units/armcom_lus.lua`、`corcom_roguelike.cob`、`legcom_roguelike.cob` | Unit Script | Roguelike 新增槽位的瞄准、枪口和开火回调；COR/LEG 原有动画与基础武器回调保持原样 | 武器数值、商店解锁、实际伤害结算 |
| `tools/roguelike/Build-RoguelikeCommanderCob.ps1` | 构建工具 | 从原 COR/LEG COB 生成模式专用脚本，检查回调表和原入口 | 实机命中与伤害验证 |
| `units/RoguelikeDrones/*.lua` | UnitDef 加载期 | 无人机模型、基础移动/碰撞和武器槽 | 轨道、AI、回收、真实修复和成长 |
| `effects/roguelike_drone_repair.lua` | 表现定义 | 实际修复成功后的纳米粒子 | 回血、电耗与触发条件 |

旧 HUD 路径 `luaui/Widgets/gui_roguelike_hud.lua` 当前仓库未发现；当前界面入口是 `luaui/RmlWidgets/gui_roguelike/`。

## 3. 关键调用链

### 3.1 波次与首批无人机

```text
Spawner GameFrame
  → updateTimedSpawnParameters：按累计作战秒数更新目标数和敌人阶段
  → 每秒补充刷怪额度，每 4 秒按目标缺口生成敌人
  → 70 秒时间边界 advanceWave：旧波敌人保留，下一波尚未递增
      → GG.Roguelike.OnWaveCleared(currentWave)
          → Upgrades 收到 clearedWave == 2
              → unlockFirstDroneMilestone()
                  → GG.Roguelike.AddDroneLevel(teamID, true)
                      → Orbit Drones 生成 2 架无人机
      → startCombatPhase：currentWave + 1，继续刷新敌人
```

时间语义必须保持一致：

- 第二波战斗期间不生成首批无人机。
- 第二波的 70 秒时间结束后调用结算回调，同帧开始第三波；旧波敌人不清除，波间没有停刷阶段。
- 首批 2 架无人机在时间边界回调中生成，紧接着第 3 波开始。
- `currentWave` 只在下一次 `startCombatPhase` 开始时递增到 3。

后续无人机等级 `drone2` 至 `drone4` 进入普通升级候选池，当前权重为普通卡的 1.6 倍，但不固定占用候选槽。

### 3.2 共享 XP、个人等级与选卡

```text
敌军 UnitDestroyed
  → Spawner 更新 roguelike_kills
  → GG.Roguelike.OnKill(totalKills, deathPosition)
  → Upgrades 将全队累计击杀按团队人数系数换算为共享 XP
  → XP 解锁数与波次保底取最大值，并限制 XP 最多领先波次保底 1 张
  → 每位 Team 独立提升 CommanderLevel 并排队私有候选
  → 当前玩家的 synced 卡池抽取三张候选
  → SendToUnsynced("RoguelikeOfferChoices", teamID, ...)
  → Upgrades unsynced 仅向本地 Team 转发 Script.LuaUI.RoguelikeShowChoices
  → RML 显示卡片
  → 玩家选择/重抽/跳过/移除候选，LuaUI 仅发送意图
  → Upgrades synced 校验 Team、active choice、资源次数和候选 ID
  → 只修改该 Team 的角色基础属性与模块状态
```

共享 XP 与卡数保底在 `game_roguelike_upgrades.lua` 中结算。XP 阈值是归一化击杀值，目前尚无敌军层级 XP 权重。角色等级每级增加稳定基础 HP 2% 与全局直接伤害 1%；属性模块以 Team 独立的类型等级和加成值保存，最高四种类型，品质、重抽、跳过及移除候选都由 synced 管理。若同一时间跨过多级，后续候选延迟到前一张处理后生成，避免多个候选显示过时等级。

旧 `getDifficultyScaledGrowth()` 已从选卡结算路径删除。不能再把旧按卡自动加生命/伤害/攻速/移速/射程/护甲/回收范围与角色等级、模块或商店加成同时套用。`effectiveDamageMultiplier()` 合并角色等级、伤害模块和原商店倍率，在指挥官攻击者的 `UnitPreDamaged` 路径结算一次；武器扩展维持其已有下游倍率。现有 `GG.Roguelike.GetMultipliers()` 仍把商店伤害倍率提供给 Spawner 的敌军生命曲线；这一历史耦合未在本阶段改动，也不会接收新增等级/模块伤害。

### 3.3 商店

LuaUI 发送 `roguelike_shop:frame-counter:itemId`，装备操作发送同格式的 `roguelike_equip`；旧格式仍可解析。Upgrades synced 从真实 sender 重新读取 Team、商品定义、当前等级、前置商品、武器槽和队伍金属，以请求编号与同帧商品键阻止重复结算，再使用 `Spring.UseTeamResource` 从该 Team 扣费。商店在所有阶段开放；UI 中显示的价格不能作为结算依据。

1800 金属的 `plasma_weapon` 在 UnitDef 加载期从 `units/CorVehicles/T2/corgol.lua` 深拷贝 Tzar 主武器 `cor_gol`，避免在 Roguelike 文件中维护一份容易过时的手抄武器参数。

### 3.4 残骸吸收

```text
敌军 UnitDestroyed
  → Salvage 暂存 source unitID
  → FeatureCreated(featureID, ..., sourceID)
  → 命中 source 白名单后把 Feature 标记为可吸收
  → 指挥官周期扫描，或无人机调用 GG.Roguelike.AbsorbWrecksForUnit
  → Salvage 验证单位归属、销毁 Feature、发放金属
```

这个白名单防止地图初始残骸、友军残骸或客户端伪造目标被兑换成奖励。白名单 Feature 在被吸收前由 Salvage 的 `FeaturePreDamaged` 阻止普通武器/爆炸伤害，保住刚生成的小残骸；D-Gun 伤害可以通过，且 D-Gun 击杀不会加入来源白名单。

### 3.5 无人机任务状态机

无人机的权威优先级为：

1. 指挥官生命低于 45%：停止攻击和回收，全部进入紧急修复；恢复到 60% 后退出。45%/60% 的滞回避免临界值附近频繁切换，并让救急带足够宽，能在多轮交火中真正回血。
2. 非紧急状态且检测到 800 范围内的敌人：攻击敌人。无人机视野与搜索半径一致，ARM 电击无人机主攻击槽限制为 `SURFACE`，避免搜索半径超出视野或攻击槽目标类别不匹配。
3. 没有敌人：优先通过 Salvage 接口吸收周围残骸。
4. 没有敌人、没有吸收到残骸且指挥官未满血：消耗队伍电力修复。
5. 无任务：保持轨道环绕。

真实修复由 synced 端每秒结算：先按无人机数量和最大生命计算期望修复量，再按队伍可用电力限制，成功扣电后才回血。纳米 CEG 只在该次结算成功后播放。

### 3.6 指挥官承伤顺序

`game_roguelike_upgrades.lua:UnitPreDamaged` 的顺序是：

1. 虚拟能量护盾吸收伤害；
2. 溢出部分经过护甲减伤；
3. 再经过单秒集火保护；
4. 最终剩余伤害进入生命值。

护盾脱离受击一段时间后使用队伍电力充能。RulesParam 只用于公开当前容量和数值，不能由 UI 写入。

## 4. 跨模块契约

### `GG.Roguelike`

| 名称 | 写入者 | 读取者 | 语义 |
| --- | --- | --- | --- |
| `currentWave`, `totalKills` | Spawner | Upgrades/诊断 | 当前已进入的波次、累计击杀 |
| `playerUnitID`, `playerTeamID` | Spawner | Upgrades/Salvage/Drones | 玩家指挥官与权威队伍 |
| `OnKill(kills, deathX, deathY, deathZ)` | Upgrades 注册，Spawner 调用 | Upgrades | 共享 XP、个人待领升级、击杀治疗与补给入口 |
| `OnWaveCleared(wave)` | Upgrades 注册，Spawner 调用 | Upgrades | 70 秒时间边界的治疗与里程碑入口；可能仍有旧波敌人，下一波尚未递增 |
| `AddDroneLevel(silent)` | Drones 注册，Upgrades 调用 | Drones | 增加一级并补齐 2 架无人机 |
| `SetSummonGrowthMultipliers(...)` | Drones 注册，Upgrades 调用 | Drones | 更新已有和未来无人机成长 |
| `AbsorbWrecksForUnit(...)` | Salvage 注册，Drones 调用 | Salvage | 验证并结算无人机回收请求 |

### 主要消息

| 消息 | 方向 | 说明 |
| --- | --- | --- |
| `RoguelikeOfferChoices` | synced → unsynced → LuaUI | 一次性升级候选通知 |
| `RoguelikeUpgradeApplied` | synced → unsynced → LuaUI | 升级/里程碑表现通知 |
| `RoguelikeShopResult` | synced → unsynced → LuaUI | 权威购买结果 |
| `RoguelikeUpgradeList` | synced → unsynced → LuaUI | 已选升级卡与商店升级等级的完整展示快照 |
| `RoguelikeSuicideWarning` | synced Spawner → unsynced Upgrades → LuaUI | 特殊自爆单位出现提示；只展示，不改变权威规则 |
| `roguelike_pick:choiceId:upgradeId` | LuaUI → synced | 选卡请求 |
| `roguelike_shop:itemId` | LuaUI → synced | 购买请求 |

### RulesParam 使用原则

- 连续状态（波次、倒计时、属性倍率、护盾、修复量、回收范围）使用 `UnitRulesParam`。
- 写入者必须是 synced Gadget；LuaUI 只读取。
- 新增参数时，代码注释应写明写入者、读取者、单位、初始值和有效时机。
- 一次性通知使用同步事件，不用 RulesParam 模拟事件队列。

## 5. 后续逻辑改动的注释规范

涉及游戏逻辑的新增或修改必须补充“为什么”和“调用关系”，尤其包括：

- 文件头：运行层、模块职责、权威状态、明确不负责的内容。
- 状态机：进入条件、退出条件、阶段顺序和跨阶段变量语义。
- 游戏公式：输入来源、增长/上限、加法还是乘法、帧与秒的换算。
- Spring Call-in：谁调用、此时哪些对象已经创建或销毁。
- `GG` 接口、RulesParam、LuaRules 消息和 RML 事件：写入者、读取者、格式和校验边界。
- 多人确定性：随机数执行位置、稳定遍历要求、为何不能使用本地 UI 状态。
- 性能限制：扫描周期、半径、单位/Feature 上限和为何需要限流。
- 兼容或兜底路径：适用的旧环境、缺失数据时如何降级。

以下内容通常不要注释：

- `i = i + 1`、普通赋值、`if`/`for` 的语法含义。
- 函数名和变量名已经完整表达的操作。
- 与附近注释重复的逐行中文翻译。

当模块职责、调用时机、消息格式、GG 接口或 RulesParam 契约发生变化时，必须同步更新本文档。

## 6. 实机验收清单

- 第二波战斗期间没有无人机。
- 第二波结算提示出现后、第三波战斗开始前生成 2 架无人机。
- 第三波之后的升级候选中，无人机卡随机出现且权重略高。
- 无人机任务优先级符合“紧急修复 → 攻击 → 回收 → 常规修复 → 环绕”。
- 电量不足时不回血，也不持续显示虚假的纳米修复效果。
- 选卡和商店请求在错误玩家、错误 `choiceId`、非法商品或金属不足时不生效。
- 单人运行正常；多人客户端看到相同的波次、无人机数量、资源和伤害结果。

Lua/RML 静态检查只能确认结构和引用关系；上述时机、动画、输入隔离和多人同步仍需在 Spring 实机中验证。

### 专属武器调用链

`unitbasedefs/roguelike_weapon_catalog.lua` 是 ARM/COR/LEG 共12款专属武器配置源。三阵营均由 `roguelike_unit_tweaks.lua` 加载原生商店槽；ARM 使用主激光1、手动 D-Gun2、防空3、通用商店4–8、阵营商店9–12、护盾13。`game_roguelike_upgrades.lua` 管理购买、等级、装备上限及未购买槽位的射程禁用。ARM Lua 单位脚本在 AimWeapon 中复查购买/装备状态，并通过 FireWeapon 调用 `GG.RoguelikeFactionWeapons.OnWeaponFired` 结算阵营机制；弹道和光束由引擎发射，不再另行虚拟攻击。详细单位信息按购买状态列出武器，购买/装备后使用 `roguelike_shop_revision` 刷新缓存。

新增 synced 消息 `roguelike_equip:<itemId>` 用于装备或卸下已购买的阵营武器；synced 端重新校验玩家、阵营、阶段、所有权与3槽上限。自定义伤害通过 `Spring.AddUnitDamage(target, damage, 0, commanderID, weaponDefID)` 进入引擎伤害链，供 `UnitPreDamaged` 识别指挥官攻击并复用伤害升级。`Spring.GetUnitWeaponTarget` 返回 `targetType, isUserTarget, target`，目标 ID 必须取第三个返回值；错用第二项会让自动目标攻击被跳过。装填和单位属性由 `GG.UpdateUnitAttributes` 更新，专属射程另乘 `roguelike_range_mult`。这些是静态调用链结论；WeaponDef、Projectile/Explosion call-in 与最终运行值仍需实机验收。

### 特殊投射物效果原型

`unitbasedefs/roguelike_weapon_effects.lua` 保存特殊效果的测试 WeaponDef 数据、每个效果的升级字段和递归/生成预算。`weapons/roguelike_meteor_payload.lua` 在 Roguelike 模式注册陨石 payload；测试用地面命令仍受隐藏测试选项控制。当前 ARM UnitDef 不挂测试发射槽，分裂弹原型定义也未装到 ARM。`effects/roguelike_weapon_effects.lua` 只负责警告圈和爆炸 CEG。

Synced Gadget `game_roguelike_weapon_effects.lua` 通过 `GG.RoguelikeWeaponEffects.SetUpgrade(unitID, effectID, key, value)` 设置经目录限幅的个人参数，并用 UnitID RulesParam 保存；弹丸状态另存 owner、Team、递归深度、分裂触发模式和伤害倍率。使用 Recoil `Spring.SpawnProjectile` 生成真实 Cannon/MissileLauncher 弹丸，`ProjectileCreated` 与 watched `Explosion` 处理归属和分裂，`UnitPreDamaged` 只叠加该枚弹丸的伤害衰减。当前仅是隐藏测试原型，尚未接入阵营商店和角色/武器等级；地图、护盾、队友伤害、Boss、回放与多人同步都未实测，接口变更须先更新此段与维护手册。
