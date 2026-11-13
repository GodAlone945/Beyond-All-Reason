# Roguelike 模式源码文件对照表

> 用途：按功能快速定位 Roguelike 模式相关代码。路径均相对于游戏仓库根目录 `BAR-PVE`。本索引按当前工作区源码核对，涵盖直接实现、模式接入、界面、资源、辅助工具与文档；不表示每个文件都只服务于 Roguelike。若要修改玩法规则，先改对应源码，再同步维护手册或平衡文档。

## 从哪里开始找

| 我想查找…… | 先看文件 |
|---|---|
| 模式开关和联机选项 | `modoptions.lua` |
| 三阵营指挥官初始属性、武器和护盾定义 | `unitbasedefs/roguelike_unit_tweaks.lua` |
| 波次、敌军生成和结束条件 | `luarules/gadgets/game_roguelike_spawner.lua` |
| 升级卡、商店、玩家属性和伤害处理 | `luarules/gadgets/game_roguelike_upgrades.lua` |
| 商店商品/阵营武器配置 | `unitbasedefs/roguelike_weapon_catalog.lua` |
| HUD、选卡与购买界面 | `luaui/RmlWidgets/gui_roguelike/` |
| 某个机制由哪些文件协作 | `doc/RoguelikeArchitecture.md` |
| 如何安全修改与验证机制 | `doc/RoguelikeMaintenanceManual.md` |

## 模式入口与定义加载

| 文件 | 作用 | 何时查它 |
|---|---|---|
| `modoptions.lua` | 定义 `roguelike_mode`、`roguelike_coop` 和隐藏测试选项 `roguelike_weapon_effect_tests`。 | 模式怎样启用、选项默认值或房间可见选项。 |
| `gamedata/alldefs_post.lua` | UnitDef/WeaponDef 后处理入口；调用肉鸽单位改造，并在模式开启时设置个人护盾专用拦截位。 | 指挥官定义何时被改、武器护盾拦截掩码如何处理。 |
| `gamedata/unitdefs_post.lua` | 加载、规范化并遍历单位定义，调用统一 UnitDef 后处理。 | 单位定义何时进入后处理流程。 |
| `gamedata/weapondefs_post.lua` | 提取内嵌 WeaponDef、规范化并调用武器后处理。 | WeaponDef 从 UnitDef 转为引擎武器定义的流程。 |
| `unitbasedefs/roguelike_unit_tweaks.lua` | 按模式改造 ARM/COR/LEG 指挥官：基础属性、初始武器、AA、公共/阵营商店槽、电能球和个人护盾；也标记 `legkam` 自爆威胁。 | 指挥官初始配置或肉鸽单位标记。 |
| `unitbasedefs/roguelike_weapon_catalog.lua` | 阵营专属商店武器目录及其数值、目标类别、攻击类型和效果元数据。 | 新增/调整 ARM、COR、LEG 专属武器。 |
| `unitbasedefs/roguelike_damage_healing.lua` | 伤害与治疗计算所用的纯逻辑/数值规则模块。 | 修改伤害倍率、治疗或相关公式。 |
| `unitbasedefs/roguelike_multishot.lua` | 多重射击配置、允许的武器和约束数据。 | 调整多重射击支持范围或参数。 |
| `unitbasedefs/roguelike_weapon_effects.lua` | 特殊武器效果定义、升级字段、参数限制和生成预算。 | 修改陨石、分裂弹等特殊效果定义。 |
| `unitbasedefs/roguelike_electric_orb.lua` | ARM 电能球 WeaponDef。 | 调整电能球本体参数。 |

## 同步玩法逻辑（LuaRules）

| 文件 | 作用 | 何时查它 |
|---|---|---|
| `luarules/gadgets/game_roguelike_spawner.lua` | 权威波次状态机、敌军池与生成、敌军强化、击杀/存活统计及失败/胜利流程。 | 波次节奏、刷怪、敌人属性或结束条件。 |
| `luarules/gadgets/game_roguelike_upgrades.lua` | XP/等级、选卡和升级、商店请求校验与扣费、指挥官属性、护甲/护盾/治疗及伤害结算；也转发界面事件。 | 升级、商店、玩家成长、护盾数值或伤害异常。 |
| `luarules/gadgets/game_roguelike_salvage.lua` | 合法残骸回收、吸收请求验证和金属奖励。 | 残骸消失、回收半径、回收奖励。 |
| `luarules/gadgets/game_roguelike_orbit_drones.lua` | 无人机等级、补位生成、轨道移动、任务优先级、扣电修复和召唤物成长。 | 无人机跟随、维修、生成或成长。 |
| `luarules/gadgets/game_roguelike_faction_weapons.lua` | 阵营武器购买/装备状态相关的权威攻击效果与特殊结算。 | 阵营武器命中效果、DoT、弹药/冷却或装备校验。 |
| `luarules/gadgets/game_roguelike_weapon_effects.lua` | 特殊弹丸效果的 synced 状态、归属、生成/分裂预算和伤害处理；含测试原型路径。 | 陨石、分裂弹等真实弹丸的运行时效果。 |
| `luarules/gadgets/game_roguelike_multishot.lua` | 为允许的商店武器执行多重射击逻辑。 | 多重射击触发、限制或弹丸处理。 |
| `luarules/gadgets/unit_aa_targeting_priority.lua` | 根据自爆威胁标记调整自动防空目标优先级。 | `legkam` 等自爆威胁为何被防空优先选择。 |

## 界面与玩家可见资源

| 文件 | 作用 | 何时查它 |
|---|---|---|
| `luaui/RmlWidgets/gui_roguelike/gui_roguelike.lua` | 读取 RulesParam、组织 RML 数据模型、发送选卡/购买请求并管理弹窗。界面发送请求，不负责权威结算。 | UI 状态、按钮行为或请求消息。 |
| `luaui/RmlWidgets/gui_roguelike/gui_roguelike.rml` | HUD、升级卡、商店的结构和数据绑定。 | 元素、面板结构或绑定 ID。 |
| `luaui/RmlWidgets/gui_roguelike/gui_roguelike.rcss` | 界面尺寸、布局、颜色、滚动和交互表现。 | 样式、排版或可点击区域。 |
| `luaui/Widgets/gui_unit_stats.lua` | 将肉鸽购买/装备状态反映到单位详细信息中。 | 单位信息面板显示的武器或数值。 |
| `luaui/Widgets/gui_buildmenu.lua` | 与肉鸽相关的建造菜单/UI 接入（若本模式功能触及建造菜单）。 | 肉鸽期间建造菜单表现或入口。 |

## 单位脚本、单位定义、武器与特效资源

| 文件 | 作用 | 何时查它 |
|---|---|---|
| `scripts/Units/armcom_lus.lua` | ARM 指挥官新增武器槽的瞄准、开火和辅助回调。 | ARM 商店武器不瞄准、不发射或枪口动画问题。 |
| `scripts/Units/corcom_roguelike.cob` | COR 肉鸽专用 COB，保留原动画并为新增槽位提供回调。 | COR 新增武器槽或 COB 构建问题。 |
| `scripts/Units/legcom_roguelike.cob` | LEG 肉鸽专用 COB，保留原动画并为新增槽位提供回调。 | LEG 新增武器槽或 COB 构建问题。 |
| `units/RoguelikeDrones/arm_electric_drone.lua` | ARM 电能无人机 UnitDef。 | 电能无人机模型、移动或武器槽。 |
| `units/RoguelikeDrones/arm_fire_drone.lua` | ARM 火焰无人机 UnitDef。 | 火焰无人机模型、移动或武器槽。 |
| `units/RoguelikeDrones/leg_laser_drone.lua` | LEG 激光无人机 UnitDef。 | 激光无人机模型、移动或武器槽。 |
| `features/roguelike_medkit.lua` | 医疗包 Feature 定义。 | 医疗包的模型、碰撞或基础定义。 |
| `weapons/roguelike_meteor_payload.lua` | 测试/特殊效果用陨石 payload WeaponDef，受对应模式/测试选项控制。 | 陨石载荷定义或测试武器注册。 |
| `effects/roguelike_weapon_effects.lua` | 特殊武器效果的 CEG 表现定义。 | 警告圈、爆炸等特殊效果的视觉定义。 |
| `effects/roguelike_drone_repair.lua` | 无人机维修成功时使用的纳米效果。 | 修复粒子效果。 |
| `effects/roguelike_electric_orb.lua` | 电能球的视觉/碰撞效果定义。 | 电能球特效。 |

## 本地化、启动器、构建和验证

| 文件 | 作用 | 何时查它 |
|---|---|---|
| `language/en/commands.json`、`language/zh/commands.json` | 英文、中文命令名称与提示文案。 | 自定义命令或相关提示缺失。 |
| `language/en/units.json`、`language/zh/units.json` | 英文、中文单位名称/描述等文本。 | 肉鸽无人机或单位文本。 |
| `tools/pve-launcher/Program.cs` | 开发启动器界面和模式选择接入。 | 启动器如何提供肉鸽选项。 |
| `tools/pve-launcher/scripts/Invoke-BarPveMode.ps1` | 启动器生成游戏 startscript/模式参数的脚本。 | 启动器选项没有传进对局。 |
| `tools/roguelike/Build-RoguelikeCommanderCob.ps1` | 从原始 COR/LEG COB 生成肉鸽专用 COB 并核对回调。 | 修改 COB 后需要重新构建时。 |
| `tools/roguelike/Validate-Sources.cjs` | 解析选定 Lua 源文件，检查 Lua 5.1 语法。 | 修改 Lua 后做静态语法检查。 |
| `tools/roguelike/Test-ArmShopWeapons.lua` | 检查 ARM 指挥官肉鸽武器槽/商店武器安装。 | ARM 武器槽变更后。 |
| `tools/roguelike/Test-FactionShopWeapon.lua` | 模拟检查阵营商店武器相关 Gadget 行为。 | 阵营武器攻击结算改动后。 |
| `tools/roguelike/Test-DamageHealing.lua` | 检查伤害/治疗纯逻辑模块。 | 修改对应公式后。 |
| `tools/roguelike/Benchmark-DamageHealing.lua` | 伤害/治疗逻辑基准工具。 | 对比数值计算开销或性能时。 |
| `tools/roguelike/Test-Multishot.lua` | 检查多重射击 Gadget。 | 修改多重射击规则后。 |
| `tools/roguelike/Test-WeaponEffects.lua` | 模拟特殊武器效果 Gadget 的回调、归属和生成限制。 | 修改特殊弹丸效果后。 |
| `tools/roguelike/Get-RoguelikeAudit.ps1` | 生成本机源码/启动配置审计快照。 | 排查运行目录与工作区是否一致。 |
| `tools/roguelike/README.md` | 验证工具运行方法和覆盖边界。 | 执行测试前确认命令与限制。 |

## 相关文档

| 文档 | 适用问题 |
|---|---|
| `doc/RoguelikeOverview.md` | 当前开发进度、游玩入口、房间设置与部署说明。 |
| `doc/RoguelikeArchitecture.md` | 模块职责、synced/unsynced 边界、调用链和接口。 |
| `doc/RoguelikeMaintenanceManual.md` | 玩法约束、权威状态、常见修改流程和维护要求。 |
| `doc/RoguelikeBalance.md` | 数值、公式、价格和调参记录。 |
| `doc/RoguelikeDevelopmentKnowledgeMap.md` | 学习路径、入口索引和机制定位路线。 |
| `doc/RoguelikeCoopAudit.md` | 双人 Coop 的实现与审计结论。 |
| `doc/RoguelikeElectricOrb.md` | ARM 电能球机制与实现细节。 |
| `doc/RoguelikeMultishot.md` | 多重射击机制与实现细节。 |
| `docs/roguelike/current-implementation-audit.md` | 当前实现审计入口与未完成验证事项。 |
| `docs/roguelike/audit-2026-11-01.md`、`docs/roguelike/fixes-2026-11-01.md` | 指定日期的审计和修复历史；历史记录不等于当前源码状态。 |

> 范围说明：此表列的是当前仓库中可确认的主要 Roguelike 相关文件。部分文件为通用引擎入口，只在内部包含肉鸽分支；`docs/roguelike/` 下的 JSON/TXT 是审计快照或结果，不是运行时代码。修改完成后仍应按 [维护手册](RoguelikeMaintenanceManual.md) 检查调用链和验证边界。
