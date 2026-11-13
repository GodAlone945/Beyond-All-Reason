# Roguelike 模式维护手册

## 2026-11-01 本轮机制修复守则

- Roguelike 指挥官金属产量保持 0，卡牌跳过不给金属；经济进账由 `game_roguelike_salvage.lua` 的残骸吸收发放。新增奖励或恢复存档路径不得重新引入被动金属。
- Coop 的 `withTeam` 必须在进入目标 Team 前保存当前别名状态，回调后先存目标状态再恢复原 Team；出错也要恢复。新增跨 Team 同步回调时按此顺序处理，转队/断线重连仍需引擎实测。
- 残骸 D-Gun 排除同时检查运行时 `WeaponDef.type/manualFire` 与定义兼容字段；不能只读 `weapontype/commandfire`。保持普通武器击毁的小残骸保护，D-Gun 可破坏残骸。
- Roguelike 开启时禁用 Raptor 与 Scav 的独立刷怪 Gadget；普通模式仍沿用各自 Gametype 判断。新增 PVE 模式也应在刷怪器入口建立互斥。
- BeamLaser 没有追踪弹丸时走 `UnitDamaged` 回退，仅对已购买对应扩展的真人指挥官触发；以武器装填间隔限次，派生效果仍由 Synced 效果总线结算。检验无 projectileID、同帧多目标、敌我归属、死亡清理和回放一致性。
- 派生直伤使用临时 `currentProcTargetID` 标记，供 Upgrades 在角色/商店倍率后施加 Boss 5% 限值；嵌套结算后必须恢复旧标记。原生弹丸护盾与 AddUnitDamage 直伤盾语义仍是独立验收项。
- 启动器开发模式勾选“Roguelike 模式”才在隔离单人 startscript 写入 `roguelike_mode=1`；不勾选为普通开发对局。房间联机仍通过最终 startscript 和 SPADS 预设确认；开发测试陨石地图命令另需 `roguelike_weapon_effect_tests=1`。

验证等级：本轮 Lua 解析、模拟回调、启动器编译均不等于 Recoil 对局；详见 [本轮修复记录](../docs/roguelike/fixes-2026-11-01.md)。

> 当前开发进度、游玩/房间设置见 [统一总览](RoguelikeOverview.md)，本轮修复和遗留问题见 [综合审计](../docs/roguelike/audit-2026-11-01.md)。历史章节中的计划/未验证结论须结合最新记录阅读；四人和武器Lv.1–6尚未实现。

本文是 Roguelike 模式后续逻辑、平衡和界面修改的执行依据。架构背景和跨模块接口见 [RoguelikeArchitecture.md](RoguelikeArchitecture.md)；当前数值体检、目标曲线和调参清单见 [RoguelikeBalance.md](RoguelikeBalance.md)。修改时应同时遵守本文和架构文档；若代码与本文不一致，应先确认实际行为，再修正代码或更新本文，不能让两套规则长期冲突。

## 1. 模式目标与范围

- 单人模式以一名玩家指挥官为核心；双人 Coop 使用每人独立 Team、同属一个 AllyTeam、每人一名指挥官。两种玩法共享一套敌人、波次和击杀进度，个人养成与资源按 Team 隔离。
- 模式由 `roguelike_mode` ModOption 控制；双人还需打开 `roguelike_coop`。模式关闭时，Roguelike 专用 UnitDef 修改、Gadget 和 LuaUI 不应影响标准 BAR 对局。双人阶段审计和实测状态见 [RoguelikeCoopAudit.md](RoguelikeCoopAudit.md)。
- 优先通过本项目的 `unitbasedefs/roguelike_unit_tweaks.lua` 做模式内指挥官武器调整，不要为了 Roguelike 直接改写上游 `BAR.sdd` 的基础单位定义。
- 引擎、LuaRules、LuaUI、RML 和房间/SPADS 设置属于不同层。修改前先确定状态的唯一所有者。

## 2. 当前玩法基线

### 波次与阶段

Spawner 当前阶段常量如下，平衡调整后应同步更新本文：

| 阶段 | 当前时长 | 约定行为 |
| --- | ---: | --- |
| 开局准备 | 5 秒 | 给玩家短暂部署时间 |
| 连续作战 | 每 70 秒更新波次编号 | 敌人目标存活数随累计作战秒数增长；每秒积累刷怪额度，每 4 秒在目标缺口内补兵，旧波敌人保留 |
| 波次边界 | 0 秒 | 按时间结算 10% 最大生命治疗与里程碑，同帧进入下一波；不停止刷怪或清除残敌，商店始终可打开 |

开局准备和波次编号由 `game_roguelike_spawner.lua` 管理。敌军目标数、持续补充的刷怪额度、单位池、刷新间隔和 Boss 波次也由 Spawner 管理；不要在 LuaUI 中自行计算或猜测波次状态。

### 自爆单位与防空拦截

- 当前普通动态池中会主动追击并引爆的单位为 `legkam`、`armvader`、`corroach`、`corsktl`、`legsnapper`。普通单位带有 `explodeas` 不等于蓄意自爆；地雷建筑不属于移动刷怪候选。新增自爆单位时，必须同时登记在 Spawner 的特殊配置中，并从通用候选池排除，不能仅依靠生命阶段池自然延迟。
- 自爆单位由 synced Spawner 的特殊池调度。每次特殊生成仍占用持续补充的刷怪额度；存活并发计数只遍历 Spawner 追踪的自爆 ID，跨波存活者继续占用上限，单位销毁后释放。生成尝试受间隔、波次上限和普通补兵缺口共同约束；具体波次门槛、概率、权重、距离和并发值以 [数值平衡文档](RoguelikeBalance.md) 为准。
- 自爆单位生成位置必须在地图边缘裁切后重新验证与玩家的安全距离。生成后设置为始终可见，并通过 `RoguelikeSuicideWarning` 从 Spawner 经 Upgrades 的 unsynced 转发显示本地警报；警报只提示，不改变伤害或同步规则。
- `unit_aa_targeting_priority.lua` 仅在 `roguelike_mode` 打开时读取 Roguelike 自爆威胁标记并提升 `legkam` 的自动防空优先级。玩家手动指定的攻击目标保持优先。ARM/Cortex 的 Roguelike commander 增加独立防空槽，Legion 调整原有防空槽；不得覆盖 D-Gun 或商店武器槽。模式关闭时该目标优先级与 UnitDef 均按 BAR 原值工作。
- 自爆弹、普通死亡爆炸和主动 `selfdestructas` 是不同伤害来源。调参前先对照 UnitDef 与 WeaponDef，不能因为死亡爆炸伤害而错误缩放普攻或重复削弱自爆伤害。

### 角色等级、共享经验与升级卡

- Roguelike 角色从 Lv.1 开始，角色等级与卡牌次数是两条独立进度。Spawner 每次追踪到的敌人死亡仅增加一次累计击杀；升级 Gadget 按有效玩家数 1/2/3/4 对应系数 1/1.6/2.1/2.6 转为团队共享 XP。角色经验使用累计升级曲线 `ceil(22 + 2.5*(L-1) + 0.18*(L-1)^2)`，角色等级上限 `MAX_COMMANDER_LEVEL = 60`。原生 UnitXP 不参与 Roguelike 角色等级计算，也不被 Roguelike 覆盖；保持 BAR 老兵经验与星级显示。不要把原生 XP 映射成角色 XP，也不要让发卡次数改变角色等级。原生生命/装填经验增益与角色成长的实机叠加效果需单独测量。
- 角色每级相对稳定基础生命 +1.2%、直接伤害 +0.8%；Lv.60 不再继续增加。升级只将新增最大生命值补入当前生命，不重置已损失血量。移速、护甲、范围、攻速和回收半径仍由商店/卡牌管理。
- 卡牌仍由 `UPGRADE_THRESHOLDS` 与波次保底控制，XP 提供的卡数最多比已结算波次保底领先 1。第 1–10 波累计保底卡数为 `2/4/6/8/10/12/13/14/15/16`，采用 `max(XP 卡数, 波次保底卡数)`，角色等级提升不会额外发卡。
- 不再使用旧 `getDifficultyScaledGrowth()` 的“每次选卡按战斗压力复利叠加生命/伤害/攻速/移速/射程/护甲/回收半径”。它已从选卡路径移除；商店/属性卡的倍率与角色等级分开保存。修改伤害时核查 `effectiveDamageMultiplier()` 与 `UnitPreDamaged` 只有一处全局结算。
- 属性模块最多选择 4 种不同类型；模块最多 5 级，射程/战斗再生最多 4 级。模块增量加法累计并受上限保护：伤害/攻速 +40%、生命 +60%、移速 +25%、射程 +28%、战斗再生 +0.4%/s。血量模块增加上限时只补新增 HP。
- 普通/优秀/稀有/史诗模块值比例为 1/1.25/1.5/2；第 1–4 波权重 70/25/4/1，第 5 波后为 55/32/11/2。品质由 synced 随机决定，只作用于该次卡值；达到模块上限后该模块移出候选。
- 每次只显示当前 Team 的一个候选组；多次升级在该 Team 内排队，处理完一组再显示下一组。Coop 的每个 Team 各自持有 `commanderLevel/sharedXP/offersEarned/statModuleLevels/statModuleBonuses/pendingChoices/activeChoiceId` 与重抽资源；选择与商店/武器/生存状态互不覆盖。玩家倒地时仍记录等级和待选卡，指挥官恢复后重发候选。
- 每局每 Team 有 2 次重抽、1 次跳过、1 次移除候选；Synced 从消息发送者映射 Team 并验证 active choice、卡牌 ID 和余额。跳过发放一次 15 金属，不增加选卡经济产出。移除只记录精确候选 ID（模块等级候选也按等级区分）。
- 卡池至少含 1 张防御候选；不足 3 张时以生命/伤害/攻速基础训练补足，卡池耗尽也不阻塞角色升级。现有护甲、护盾、自爆防护、击杀回复、无人机和自动里程碑继续使用原有处理逻辑。
- 第 2 波作战时间结束、紧接着第 3 波开始前自动解锁 2 架轨道无人机；它不是一次普通选卡，不应额外增加角色等级或选卡次数。
- `UPGRADE_THRESHOLDS` 与角色等级曲线都读取归一化击杀 XP；Spawner 仍只提供累计击杀数，没有精英/Boss 经验权重。本轮曲线和系数属于初步值，须实机记录单人/双人各波累计 XP、角色等级与抽卡数后再平衡。

### 指挥官、资源与残骸

- 指挥官基础体质统一由 `unitbasedefs/roguelike_unit_tweaks.lua` 的 `COMMANDER_BASE` 写入：三阵营均为 10000 生命、84 移速、60 电力产出、0 金属产出、10000 金属容量；移速相对既有 Roguelike 基础值 60 提高 40%。初始武器伤害统一按 `COMMANDER_WEAPON_DAMAGE_SCALE = 1.4` 缩放（跳过 DGun 与商店武器）。上游 `units/*.lua` 不再保存 Roguelike 专用改动，模式关闭时保持 BAR 原值。
- 仅开局准备阶段（Spawner phase 3）仍可触发 `RECOVERY_HEAL_PER_SECOND = 1.2%/s`；之后连续作战，脱战 `HEALTH_REGEN_DELAY` 后按 `BASE_HEALTH_REGEN_PER_SECOND = 0.25%/s` 与商店纳米修复回复。每 70 秒波次边界治疗最大生命的 10%，即使旧波敌人仍存活也结算。连续受压时的续航待实机复核。
- 开局指挥官不应自带被动金属收入；商店金属的主要来源是吸收符合条件的敌军残骸。
- 当前卡片升级还会按 `METAL_INCOME_PER_UPGRADE` 增加少量金属产出（当前常量为每次 0.1）；这是升级成长，不是开局收入。改经济规则时必须明确区分开局收入、升级收入和残骸收入，并同步检查 HUD、商店说明和 UnitResourcing。
- 残骸奖励由 Salvage Gadget 结算：只接受追踪到的敌方死亡来源及其残骸，按残骸金属值与回收倍率计算，销毁 Feature 后再给玩家队伍发放金属。不得把地图初始残骸、友军残骸或客户端传入的 Feature ID 直接当作奖励。
- 已登记为可回收的敌军残骸在被吸收前免疫普通武器/爆炸的 Feature 伤害，避免小单位残骸刚生成就被后续爆炸清除；D-Gun 伤害仍可破坏残骸，且 D-Gun 击杀不会登记回收奖励。改动只作用于 Roguelike Salvage 白名单中的敌军残骸。
- 当前基础回收半径为 220，升级半径成长和回收速度由 RulesParam 与 Salvage Gadget 共同管理。升级 Gadget 写入权威值，Salvage Gadget 读取；不要各自维护一套升级次数。

### 商店、武器与护盾

- 商店在任何阶段开放。LuaUI 只提交商品 ID 和请求编号；synced Gadget 从真实 sender 查询 Team，检查本队指挥官、前置解锁、最高等级、武器槽、金属与重复请求，再从本队扣款。Coop 的商店和选卡事件必须只转发到所属 Team。
- 商店、UnitDef 和武器槽必须使用同一个稳定 ID。例如雷霆步枪使用 `lightning_weapon`；相关 UnitDef `customParams.roguelike_shop_item`、`SHOP_ITEMS`、武器槽映射和 UI 卡片都必须一致。
- 新增或修复可解锁武器时，逐阵营检查武器槽是否存在、武器定义是否已加载、商店 ID 是否映射到正确槽位、购买后是否更新 RulesParam，以及重复购买是否被限制。
- 护盾卡应将容量写入权威护盾状态。受伤顺序为虚拟护盾吸收、溢出部分经护甲减伤、单秒集火保护，最后才扣生命；脱离受击 4 秒后，护盾按队伍可用电力充能（3% 容量/秒，0.8 电/点）。当前三级护盾容量为 2000 / 3500 / 5000。不得只改 HUD 数字而不改伤害和充能逻辑。
- 商店纳米修复当前为 250 金属起步、每级 +220、5 级、每级 +0.30% 最大生命/秒（开局准备或脱战后生效，购买后回满生命）。波间等待已取消，不能再按固定休整期收益估算其强度。
- 初始武器平衡目标为各阵营指挥官武器属性提高约 40%，由 `COMMANDER_WEAPON_DAMAGE_SCALE = 1.4` 在 Tweaks 中统一缩放（跳过 DGun 与商店武器），不再写在上游 UnitDef 里。雷霆步枪三阵营统一为伤害 30.8、装填 0.85。
- 商店 5 件通用武器均有 `customParams.roguelike_shop_item`，三阵营槽位通过动态追加兼容。当前数值：雷霆 362 DPS / 1200；Tzar 1100 伤害（314 DPS）/ 1800；狙击 450 DPS / 2800；覆盖炮 170×6、装填 6 秒（170 DPS + 燃烧）/ 2700；冲击炮 340、装填 1.3 秒（262 DPS）/ 2200。扩展卡每级 +25%（冲击 +30%）。这些静态数值与槽位均待实机核验；专属武器详细参数见 [RoguelikeBalance.md](RoguelikeBalance.md)。

### UI 与房间设置

- `gui_roguelike.lua` 只读 RulesParam 并显示状态、候选卡、商店和已购升级列表；它不能决定升级效果、扣款、伤害或资源奖励。
- 顶部状态条显示波次/阶段、倒计时、存活敌军数和击杀数。数据从 Spawner 写入的 RulesParam 读取。
- 升级卡片和商店打开期间会自动收起指挥官建造菜单；关闭界面后按当前弹窗状态恢复。不要通过取消指挥官选择来“关闭”菜单，以免改变玩家的选择状态。
- “已升级选项”列表包含已选升级卡和已购买商店项目及其等级/说明；标题栏可拖动，列表内容可滚动。权威端通过 `RoguelikeUpgradeList` 同步事件发送列表。若更改事件字段或分隔格式，必须同时修改 synced 发送端、unsynced 转发端和 LuaUI 解析端。
- 房间设置/ESC 设置界面打开时，Roguelike HUD、商店、升级提示和已升级列表都应隐藏并释放输入；设置关闭后，原本打开的 Roguelike 弹窗应按有效状态恢复。
- SPADS 报错“Choose in game but no start box”说明房间起点类型要求地图提供起始框但没有可用框。应优先在房间设置中选择有效起点/起始框；`!forceStart` 是绕过检查的应急命令，不应当作常规配置修复。

## ARM 初始武器、商店攻击与测试回退

- ARM Roguelike 原生槽位为主激光1、手动 D-Gun2、防空3、通用商店4–8、阵营商店9–12、电球13、个人护盾14。普通 BAR 的 `armcom` 不改；海底激光不进入 Roguelike 武器池。
- ARM 商店武器由 `unitbasedefs/roguelike_unit_tweaks.lua` 安装。未购买/未装备槽位射程为0，ARM AimWeapon 再复查 RulesParam。FireWeapon 经 `GG.RoguelikeFactionWeapons.OnWeaponFired` 触发零原生伤害的阵营武器机制，原生弹丸/光束负责画面；不要恢复旧虚拟攻击控制器。
- COR/LEG 保留既有原生商店槽位。ARM 原生购买/发射路径已做 headless 引擎验证；画面、Boss、重放与双人同步仍需相应实测，不能将无窗口引擎测试等同于画面验收。
- 每次测试性代码改动，必须先在 `tools/roguelike/rollback/<改动名>/` 保存被改文件的原始快照，并提供 `Restore.ps1` 与文件清单；测试入口需有明确模式/选项门控。验证失败时可以直接运行对应恢复脚本。不得用旧快照覆盖快照之后的其他文件改动。
- `game_roguelike_upgrades.lua` 曾碰到 Lua 主函数 200 个局部变量的编译上限。新增顶层常量、Spring API 别名或函数后必须重新执行隔离 headless 加载，确认日志出现 `Loaded synced gadget: Roguelike Upgrades`；现有 30 个 Spring 调用已改为直接调用以留出空间。

## 3. 权威状态和跨层规则

遵循 [RoguelikeArchitecture.md](RoguelikeArchitecture.md) 中的模块职责、`GG.Roguelike` 契约与 RulesParam 原则，并额外遵守以下要求：

1. 同步战斗状态、资源、随机抽取、升级应用、伤害、无人机和残骸奖励必须由 LuaRules synced Gadget 决定。
2. LuaUI 输入只是请求。请求到达后必须验证玩家、队伍、待处理 choice、项目 ID、前置条件和价格；只有受阶段限制的动作才验证阶段。商店购买在所有阶段合法。
3. synced 与 unsynced 通知只用于跨层传递；RML DOM、CSS class 和 LuaUI 缓存不得成为游戏规则的数据源。
4. 新增 RulesParam 时注明写入者、读取者、所属 Unit、默认值、访问权限和有效时机。优先复用唯一权威值，不复制状态。
5. synced 随机数只能在 synced 代码中按稳定顺序使用；不能依赖 `pairs()` 的不稳定遍历顺序来决定结果。需要展示稳定顺序时，显式排序。
6. `SHOP_ITEMS`、武器槽映射、UnitDef customParams、LuaUI 商店定义和已升级列表中的 ID 必须一致。不要把显示名称作为逻辑 ID。

## 4. 后续修改流程

1. 先阅读本文相关规则和 [RoguelikeArchitecture.md](RoguelikeArchitecture.md)，再查找状态的实际写入者与调用链。
2. 为本次改动列出受影响模块：Spawner、Upgrades、Salvage、Orbit Drones、UnitTweaks、LuaUI/RML、房间/SPADS 设置。只改必要模块。
3. 修改前写清预期输入、状态变化、边界条件、失败行为和阵营覆盖范围。涉及 UI 时同时明确对应的权威 synced 逻辑。
4. 保持状态单一所有权，避免新增重复计数、客户端权威状态或绕过 Gadget 的直接资源修改。
5. 更新对应代码注释、本文的玩法基线/变更记录，以及架构文档的接口表或调用链。只改样式时无需改玩法公式；一旦改变数据结构、事件或规则，必须更新文档。
6. 实施后至少按第 5 节的相关验收项检查；涉及实时输入、引擎 API、暂停、RML 拖动或多人一致性时，必须在实际游戏环境验证，并明确记录未验证的部分。

## 5. 修改验收清单

- [ ] 模式关闭时没有 Roguelike 专用属性或 UI 副作用。
- [ ] 开局 5 秒后连续刷怪；每 70 秒波次编号更新时没有停刷和清场；共享 XP 与波次保底按本手册发卡。
- [ ] 升级候选无重复/越级/绕过前置；只有有效选择能改变属性。
- [ ] 连续作战期间任意时刻可打开商店；错误队伍、未解锁项目、满级、重复请求和金属不足时不扣费、不生效。
- [ ] 雷霆步枪等阵营武器槽映射正确；购买后对应武器可用且等级 RulesParam 正确。
- [ ] 护盾实际吸收伤害并按电力充能；HUD 容量和当前值同步真实状态。
- [ ] 残骸回收只奖励敌军有效 Feature，Feature 不会被重复结算。
- [ ] 无人机低生命紧急修复、敌人攻击、残骸回收、普通修复优先级及扣电条件正确。
- [ ] 三族轨道无人机视野覆盖 800 搜索范围；ARM 无人机能自动攻击视野内 `SURFACE` 敌人。普通爆炸不能清除待吸收残骸，D-Gun 击杀不产生回收奖励且 D-Gun 仍能摧毁残骸。
- [ ] 商店/升级弹窗收起建造菜单；ESC 设置层级正确；升级列表可滚动、拖动并显示当前购买内容。
- [ ] 单机结果正确；若涉及多人，所有客户端看到一致的阶段、击杀、升级、资源和伤害结果。
- [ ] 文档和实现同步；新增/修改的事件、RulesParam、ID 或数值均有记录。

## 6. 变更记录与待核对事项

| 主题 | 已确定的设计/实现基线 | 后续注意 |
| --- | --- | --- |
| 指挥官初始状态 | 三阵营统一 10000 生命、84 移速、60 电力、0 金属、10000 金属容量，由 `COMMANDER_BASE` 写入；上游 UnitDef 保持 BAR 原值 | 后续改基础值只改 Tweaks，不要再改 `units/*.lua` |
| 金属来源 | 吸收符合条件的敌军残骸获得金属；升级卡当前另加每次 0.1 金属产出 | 如未来决定彻底取消所有被动金属产出，需同时改 `METAL_INCOME_PER_UPGRADE`、UnitResourcing、升级说明和本手册 |
| 商店解锁 | 商店通过稳定 `itemId` 在 synced 端验证并扣款 | 雷霆步枪解锁问题按 UnitDef、槽位映射、商店 ID 三处一起排查 |
| 护盾卡 | 虚拟护盾由 synced 伤害和充能逻辑管理；容量 2000/3500/5000，3% 容量/秒、0.8 电/点 | 只修改 RML/HUD 不算修复完成 |
| ARM 初始武器 | 主激光1、D-Gun2、防空3、商店4–13、护盾14；未购买槽禁用 | 电球图形表现、实际命中与双人同步待验证 |
| 商店武器 | 五款通用商店武器动态追加到三族；阵营专属武器配置集中于 catalog | 按实机 DPS 与金属收入复核价格、目标类别和槽位索引 |
| 升级节奏 | 归一化 XP 阈值 25/50/75/110/145/190/245/310/395/480/565/680/850/…；波次累计保底 2/4/6/8/10/12/13/14；Tier 2 从角色 Lv.5、Tier 3 从 Lv.9；每次候选保底 1 张防御卡 | 改阈值时同时核对 XP 正规化、波次保底、Team 状态、`maxAvailableTier` 和 HUD |
| 数值一致性 | P0 已把指挥官基础值、+40% 武器、雷霆数值收进 `roguelike_unit_tweaks.lua`，并回退上游 UnitDef | 商店槽位与重复激光仍需逐阵营核对 |
| 生存与回血 | 波间等待 0 秒；每 70 秒时间边界治疗 10%、脱战 0.25%/s、无人机 0.6%/架/秒、每 HP 治疗耗电 0.75；紧急修复 45%/60% | 持续治疗总量仍受 1.5% 最大生命/秒共享上限约束；按连续波次实测续航，详见 [RoguelikeBalance.md](RoguelikeBalance.md) |
| 连续刷怪 | 70 秒波次边界不进入清场；旧敌人保留，目标数按累计作战秒数增长，刷怪额度每秒补充、每 4 秒按缺口补兵 | 新一波可能因旧敌人已达到目标数而不立刻额外生成；实机检查存活总数、补兵节奏和性能 |
| 双人 Coop | `roguelike_coop` 开启时两支人类 Team 同一 AllyTeam；共享波次/击杀，个人养成、商店、武器、无人机和金属按 Team 隔离 | 必须双客户端验证同帧购买、掉线重连、队友死亡和同步日志；详见 [RoguelikeCoopAudit.md](RoguelikeCoopAudit.md) |
| 状态与弹窗 UI | 顶栏含击杀数；设置/房间覆盖层/全局隐藏UI时隐藏并停止快捷键交互；商店/升级弹窗期间收起建造菜单 | 实机需检查 F1 购买/装备、ESC、属性/武器/阵营武器三列及列内滚动；`.shop-overlay.hidden`、`.upgrade-overlay.hidden` 必须覆盖各自的 `display:flex` |
| 已升级列表 | 可拖动与滚动，列出升级卡和商店等级/说明 | 修改同步列表数据格式时，同步更新发送、转发和解析三处 |
| SPADS 开局 | “Choose in game”必须有可用 Start Box | 优先配置正确起始框；`!forceStart` 仅用于绕过应急 |
| 自爆单位 | 特殊名单从普通动态池排除；Synced 端维护跨波并发、门槛、间隔和警报 | 新单位必须核对主动自爆/死亡爆炸两种伤害；确认模式关闭无变化 |
| 无人机攻击 | `game_roguelike_orbit_drones.lua` 的搜索半径与三族 Rogue 无人机视野同为 800；ARM 主攻击槽限定 `SURFACE` | 检查敌人视野、目标类别和 `CMD_ATTACK`；紧急修复期间无人机按既定优先级暂停攻击 |
| 残骸保留 | Salvage 白名单残骸免疫普通武器/爆炸 Feature 伤害；D-Gun 击杀不入回收白名单，D-Gun 可破坏残骸 | 只保护本模式登记的敌军残骸；确认不会阻止 reclaim 或重复发放金属 |
| 自动防空 | Roguelike 自爆威胁标记只改变自动目标优先级；Legion 保留原 AA 定义，ARM/Cortex 使用独立 Rogue AA 槽 | 实机检查高速 Martyr 的可见、自动选敌和拦截；玩家手动指定目标不得被覆盖 |
| 近身索敌与开火 | ARM 的第 3–16 槽进入辅助武器分支，不会误入 D-Gun 瞄准；COR/LEG 使用模式专用 COB 补足新增槽位回调；伤害回调读取 `GetUnitWeaponTarget` 第三项 | 静态回调表检查和无界面加载已完成；多敌贴身时的实际开火、命中与伤害仍未实机验证 |

### 三阵营专属武器维护守则

- `unitbasedefs/roguelike_weapon_catalog.lua` 是 ARM/COR/LEG 12 款专属武器的唯一数值与显示配置来源；同步升级、UnitTweaks 与 LuaUI 都从这里读取。不要在 UI 或 Gadget 复制参数表。数值和验证状态记录在 [RoguelikeBalance.md](RoguelikeBalance.md)。
- 新武器只通过 `roguelike_unit_tweaks.lua` 在 Roguelike 开启时加入三族 commander UnitDef。使用独立 WeaponDef ID 和 `customParams.roguelike_shop_item` / `roguelike_custom_weapon`；基础武器、D-Gun、五个通用商店 ID 不复用、不覆盖。WeaponDef 字段使用 BAR 约定的小写 `weapontype`。
- `game_roguelike_faction_weapons.lua` 在 synced 端结算专属攻击行为；`game_roguelike_upgrades.lua` 权威处理购买、升级和装备；LuaUI 只展示 catalog、读 RulesParam 并发 `roguelike_equip:<itemId>` 请求。伤害通过 `Spring.AddUnitDamage` 带 commander attacker 与原 WeaponDef，预期复用 `UnitPreDamaged` 伤害倍率；射程、装填、生命、移速沿用 `applyCommanderStats` / UnitAttributes。修改这些路径时核查没有重复乘伤害和原版副作用。
- 每款专属武器支持 L1-L3；同时最多装备3款。首次购买在有空位时自动装备；满槽时购买的武器保持未装备，玩家需先卸一款再装备。更改上限时同步更新 catalog、synced 校验、RulesParam、UI 状态与文档。
- 新机制须核对目标类别、有效射程、引擎武器类型、CEG、0伤害 WeaponDef 的 Projectile/Explosion/UnitWeaponFired 调用、自伤和友伤。DoT、升温、减速须在目标死亡/过期/卸装时清理；多目标扫描、目标数、弹数和结算周期有明确限制（当前 shock/napalm 12目标、molten 8目标）。
- 改槽位时逐阵营检查 UnitDef `weapondefs`/`weapons[]`、`customParams.roguelike_shop_item`、SHOP_ITEMS、购买消息、RuleParams 与装备状态；通用商店仍使用既有 ID 和购买记录。
- 静态检查不能验证 WeaponDef 引擎解析、真实命中/DPS、爆炸、自伤、联机同步和压力下性能。结果逐项标注“实测通过 / 失败 / 未验证”，记录地图、阵营、等级与实测数值；未运行游戏不得把目标值写为已验证。
- `Spring.GetUnitWeaponTarget(unitID, weaponNum)` 返回 `targetType, isUserTarget, target`。Synced 攻击回调必须读取第三项作为目标；不能把第二项布尔标志传给 `ValidUnitID` 或伤害结算。多目标锁定但无伤害可能由这类返回值错位导致，修复后实测自动目标和手动目标两种情况。
- 新增武器槽还必须有对应的单位动画脚本回调。ARM 原脚本把 4–32 槽当成 D-Gun，反复索敌时会置位 `isAimingDgun` 并阻止主激光瞄准；Roguelike 开启时将 3–16 槽映射为独立辅助武器，覆盖电球13与护盾14。COR 原 COB 缺少第 4 槽的 `AimWeapon` 和第 5–13 槽回调，LEG 原 COB 缺少第 5–13 槽回调；本模式用 `corcom_roguelike.cob`、`legcom_roguelike.cob` 补足，保留原动画和第 1–3 槽（LEG 第 1–4 槽）的行为。更改槽位数量时同步维护这三份脚本，不能只修改 UnitDef 或伤害 Gadget。
- COR/LEG 专用 COB 由 `tools/roguelike/Build-RoguelikeCommanderCob.ps1` 从原 COB 生成。修改原脚本或追加槽位后，运行 `powershell -NoProfile -ExecutionPolicy Bypass -File tools/roguelike/Build-RoguelikeCommanderCob.ps1`，核对原回调入口与新增 `AimFromWeaponN`、`QueryWeaponN`、`AimWeaponN`、`FireWeaponN`。生成器的静态检查只能证明文件结构与回调表一致；必须在新开的一局中分别测试三族基础激光、D-Gun、自动防空、通用武器与阵营武器。测试时让多名敌人在近身和射程边缘同时移动，分别记录持续开火、目标切换、命中和伤害；这项实机验证目前未完成。


## 商店界面维护记录

商店商品固定分为「属性」「武器」「阵营武器」三列，各列内部独立纵向滚动。属性列收纳 damage、health、reload、move、range、salvage 等属性强化（health 分类也包含回血）；武器列收纳通用武器及其扩展；阵营武器列只显示当前指挥官阵营的专属武器。分栏由 LuaUI 商品 category 与 faction 字段决定，新增商品时需要同步检查分类。

购买成功后，LuaUI 以 synced 商店回执中的等级作为界面状态下限，同时继续读取指挥官 RulesParam。这样可覆盖 RulesParam 尚未复制到本地界面的短暂窗口；游戏逻辑、购买校验、扣款和武器装备状态仍由 synced Gadget 决定。阵营匹配只代表该商品属于当前阵营；未购买时显示「可购买」，购买后才显示已拥有或已装备。

本次界面代码已修改，尚未进行 BAR 实机验证。测试时依次检查 ARM/COR/LEG 三个阵营的三列分类、每列独立滚动、通用武器前置解锁、阵营武器购买后的等级/拥有状态/装备切换，以及关闭后重新打开商店时状态保持。
商店打开时通过受保护的刷新入口构建商品 RML；渲染错误会记入 infolog 的 `Roguelike shop render error`，并保留商店/主 HUD 的显示状态，避免单次商品渲染异常卸载整个 Roguelike Widget。F1 仍由该 Widget 处理为商店开关。
实机日志定位到 F1 打开商店时的 LuaUI 异常：缺失的 UnitRulesParam 会让 Spring API 返回零个值，不能直接写成 `tonumber(Spring.GetUnitRulesParam(...))`。应先用 `or 0` 规范为空值，再传给 `tonumber`。该异常会卸载 Roguelike Widget，因此商品选项卡和 HUD 都消失；现已修正读取顺序。该修正尚未重新实机验证。
Roguelike HUD/商店需订阅 `LobbyOverlayActive1/0` LuaUI 消息：进入 Chobby 房间/设置界面时调用 Rml Document 的 `Hide()`；返回对局时调用 `Show()` 并重新同步选项界面可见性。保留商店/升级弹窗状态，避免丢失待选择的升级卡。此处通过隐藏整个 Document 解决覆盖房间 UI 的问题，单独降低 RCSS z-index 不足以处理界面切换。
三栏商店现在使用横向 flex 布局，列宽以 `.shop-items` 的实际 `client_width` 减去两处 12dp 间距后平均分配。各列和滚动容器使用固定 DOM ID；LuaUI 通过 `GetElementById` 读取实际宽度，并设置列、滚动层和商品卡片的像素宽度。卡片宽度按滚动容器 `offset_width` 计算，不能用 `client_width`，因为长列表显示滚动条后该值会扣掉滚动条宽度，导致属性和武器列卡片比没有滚动条的阵营武器列窄。垂直滚动条宽 6dp，并用负右边距放入列的右侧留白。商店商品重建或窗口宽度变化后，LuaUI 会重新计算。该布局尚待 BAR 实机验证。

验证商店样式时先在游戏内执行 `/luaui reload` 或重新进入游戏，让 RML/RCSS 重新加载；然后按 F1 检查三列卡片是否占满列内宽度，分别滚动每列并点击卡片，最后改变窗口尺寸再检查一次。若布局计算报错，查看 `infolog.txt` 中的 `Roguelike shop layout error`。
- 本地 SPADS 的 Boss 只在当前 battle 中有效。Boss 批量加载房间配置时，允许其绕过命令和房间消息防刷门槛；其他玩家及全局阈值保持原设置。该逻辑位于本地服务器 `spads.pl`，修改后需重启 SPADS 才会载入；重启会关闭当前房间。

## Commander shield and Photon Cleave maintenance

The Roguelike UnitTweaks layer adds `roguelike_personal_shield` and one Shield weapon slot only when Roguelike mode is enabled. Do not edit the stock commander UnitDefs for this feature. The synced upgrades gadget owns shield capacity, energy cost, recharge delay, and HUD RulesParams. The native shield supplies the visible bubble and projectile interception/repulsion; its maximum power covers all three upgrade tiers (10500). BAR's `unit_shield_behaviour.lua` normally consumes hits on shields it does not register, so it explicitly lets the marked Roguelike shield use engine repulsion and charges its native power once per projectile (or per beam frame). The synced upgrade state reads that native power back each second. Damage that reaches `UnitPreDamaged` has passed the native shield and must not be absorbed a second time. Keep native automatic recharge and upkeep at zero; energy is charged explicitly by the synced gadget. If adding or changing a shield slot, preserve per-Team state in `selectTeam` / `storeTeam` and verify all three commander UnitDefs expose the marked slot.

Faction special weapon dispatch must resolve WeaponDef from `UnitDefs[unitDefID].weapons[weaponNum]` when UnitWeaponFired does not provide a WeaponDef ID. Cone effects are implemented in `game_roguelike_faction_weapons.lua` and use the live unit target as the forward direction; tests should cover angle edges, range edges, target-class filters, target switching, and max-target limits. Keep numerical weapon values in `RoguelikeBalance.md`; this manual records mechanism and maintenance constraints.

Validation record: static code inspection only. The engine shield rendering/interception API, Lua callback timing, and cone damage in a live match remain unverified. Use the in-game test steps in `RoguelikeBalance.md`; record build/version, faction, shield tier, projectile type, energy level, and observed values before calling any result verified.
For shield repulsion, test ARM, COR, and LEG separately after selecting the Shield I upgrade card. Fire a Cannon or missile projectile at full charge: it should change direction at the bubble, leave commander health unchanged, and reduce the shield HUD value. Repeat until the shield reaches zero; the next projectile should reach the commander. Repeat with two players on different Teams to verify their shield pools remain independent. Native beams can be blocked but cannot be physically reflected like ballistic projectiles.
## Shop repeat purchases and scroll retention

Attribute and weapon shop purchases may be issued more than once during the same simulation frame. The shop can pause a single-player game, so per-frame purchase throttles are invalid; rely on the request nonce deduplication in the synced message handler instead. If shop DOM is rebuilt after a purchase, preserve each category scroll container's `scroll_top` and restore it after layout widths settle. Keep the three columns independent and clamp restored positions to each column's new `scroll_height - client_height` range. Live UI behavior still requires an in-game check.

## Roguelike survival and cooperative healing contract

All of this section is gated by `roguelike_mode`; the Coop-specific ownership and team-aura paths are additionally gated by `roguelike_coop`. Keep survival state attached to the owning Team in `selectTeam` / `storeTeam`. The single-player Rogue path also initializes a Team state so the same pickup and heal code is exercised. Do not put cooldowns, healing budgets, blood-recycle cooldowns, or beacon cooldowns in an unscoped shared variable.

`game_roguelike_upgrades.lua` is the synced authority for skill requests, cooldowns, shield/barrier/mitigation, healing, medkit spawn and pickup. LuaUI reads commander RulesParams and sends only `roguelike_skill:<frame>-<nonce>:<skillId>`; it never changes health or cooldowns. Drone healing calls `GG.Roguelike.HealCommander(teamID, source, amount, context)` instead of setting commander health itself. Keep all commander HP changes in this central helper, except max-health recalculation in `applyCommanderStats`. `context.sustained=true` places passive/shop regen, drone repair, combat regen, kill leech, Repair Link and Medical Beacon under the shared per-commander cap of 1.5% max HP per second. Emergency nanorepair, medkits and wave-clear healing are discrete capped events and do not consume that sustained budget. Energy-funded effects must charge only for the amount actually healed.

Blood Recycle diagnostics are per-Team: `roguelike_blood_recycle_seen`, `..._healed_events`, `..._healed_amount`, `..._out_of_range`, `..._cooldown_blocks`, `..._full_health`, `..._cap_blocks` and `..._missing_position`. While the upgrade is owned, Synced emits a 10-second summary to `infolog.txt`. A missing summary after a full interval means the upgrade was not active or kills were not reaching the callback; a nonzero reason counter identifies the filter. Do not remove this instrumentation until the range, cooldown and heal-cap behavior have been verified in a real match.

Damage order for the owning commander is: marked suicide-threat reduction, COR Bastion reduction, existing native/virtual shield absorption, ARM temporary barrier absorption, armor, then the existing focus guard and HP damage. Blast Lining only recognizes the Spawner-tagged `legkam`, `armvader`, `corroach`, `corsktl`, and `legsnapper`; do not infer explosion types from unrelated units. Keep the barrier as a separate synced points pool and mirror it through `roguelike_barrier_current`; it must not consume or refill the engine shield pool.

Medkits are Gaia-owned, non-reclaimable and indestructible Rogue features; `medkitsByFeature` is their synced registry and the spawner's tracked kill callback supplies their position. The feature is removed on pickup or 20-second expiry and is capped at four alive. Pickup is a nearest eligible injured Rogue commander within 100 elmos; per-Team pickup cooldown is five seconds. It is not a Salvage feature, so do not add it to Salvage's wreck whitelist. Global team kill progress is intentional for shared progression; the spawn threshold is `14 + 5*(team count - 1)` kills.

Only one Repair Link or Medical Beacon instance of each type may run at once across the AllyTeam. Each target still passes its own sustained-healing budget; this is the anti-stacking guard and must remain per target commander. New heal sources must be added to `HEAL_SOURCES`, state snapshot/load/store, RuleParams/UI if visible, the sustained budget decision, and the balance table. New damage sources must be marked in synced code and composed in the one `UnitPreDamaged` path. Test one, two and four players with different missing HP, simultaneous skill requests, pickup races, low energy, player death and reconnect; compare each client's Team-specific cooldown, HP, energy and heal totals. Current code has static inspection/smoke evidence only; real multi-client behavior remains unverified.

## Survival system test protocol

Use Roguelike + Coop with ARM/COR/LEG commanders. Check two same-AllyTeam clients then repeat with four clients if the room supports it. In one run, verify 180 energy / 50-second Nanorepair, 30-second Thruster, ARM 1600-point barrier, COR 25% Bastion, LEG self-plus-one teammate Repair Link, and the shop-purchased 350-energy Medical Beacon. Damage a commander with ordinary weapons, a tracked suicide unit and a projectile; only marked suicide attackers should receive Blast Lining mitigation. Buy each heal card and compare the RulesParam/HP delta. Spawn enough kills for medkits, race both commanders into one pickup, then check the next drop threshold, 4-item cap and 20-second expiry. Exercise drone repair and passive regen together to confirm total sustained HP gain never exceeds 1.5% max HP in any one-second bucket. Finally disable Roguelike and confirm no Rogue feature, HUD, skill, mitigation or heal hook is active. No item in this protocol is marked gameplay-verified until run in an actual BAR match; see `RoguelikeBalance.md` for current evidence and outstanding cases.

## Synced special weapon effect framework

> **2026-11-01 update:** The original paragraphs in this section below document the earlier test-only prototype. They are superseded by the P1 rules here: the shared effect bus runs when `roguelike_mode` is enabled; only prototype test weapons and the map-click test command require `roguelike_weapon_effect_tests`.

### P1 effect bus maintenance rules

- Keep effect definitions and provisional values in `unitbasedefs/roguelike_weapon_effects.lua`; stable effect IDs are `chain`, `ricochet`, `burst`, `burn_zone`, `aftershock`, and `delayed_strike`. Add new effect behavior in the Synced `game_roguelike_weapon_effects.lua` executor, not in LuaUI. The meteor payload WeaponDef is needed by the shop attack and loads in Roguelike mode; only its developer map-click command remains dev-gated.
- Groundflash-only telegraphs and markers belong in `effects/roguelike_weapon_effects.lua`; do not put gameplay damage or timing in CEG definitions.
- `game_roguelike_faction_weapons.lua` is an adapter: it passes the current attack event through `GG.RoguelikeWeaponEffects.OnHit`. Keep its existing damage path authoritative. Do not independently apply the same primary weapon damage in the effect bus.
- Effects are scoped by owner and event. Proc descendants do not call the bus. Preserve these provisional caps from the catalog: proc depth 1; 16 proc events per frame and 4 per owner; 3 burn zones per owner; 12 area states per owner; 16 targets per area tick. The existing split projectile ceilings remain depth 3, 48 per owner, 256 globally and 16 spawns per frame.
- Existing common projectile extension IDs map only the tracked plasma, sniper, barrage and shockwave commander weapons to an effect. Extend the mapping only after checking the actual `roguelike_shop_item`, weapon slots and extension purchase rules. Do not mark unrelated beams or scripted attacks as projectile-compatible by assumption.
- The shop's `meteor_weapon` is currently an automatically scheduled attack source reusing the warning and falling meteor projectile. It finds the nearest enemy within 900 elmos every 15 frames while purchased; Lv.2 adds the capped burn-zone state on impact. It is not currently a spawned autonomous UnitDef. If changing this architecture, reuse the same projectile/queue path and preserve the player's Team as projectile owner.
- `burst` supports both hit and kill trigger entries. Kill contexts are same-frame, owner/weapon matched and cleared at the next `GameFrame`; validate actual `UnitDamaged`/`UnitDestroyed` ordering in BAR before relying on kill effects. `ricochet` currently deals a bounded secondary hit rather than visibly redirecting the projectile.
- All numeric values are first-pass suggestions. Distinguish static caps from measured simulation cost. Do not report synced multiplayer, replay, shield, elite/Boss, reconnect or performance validation until each scenario has been run in BAR and recorded.

### P1 test checklist

Run one player and two players first. Four-player stress testing requires a separately implemented and verified expansion of the current exactly-two-Teams gate. Buy each mapped extension and faction weapon upgrade independently on both Coop Teams. Verify owner attribution, no ally/self damage, one proc per attack event, no recursive procs, split children remain within existing caps, status expiry after owner death, correct elite/Boss mitigation, no duplicate metal charge, and replay consistency. Compare Roguelike off in standard BAR and Raptors/Scavengers. Record active projectile peak, zones/status peak, proc/reject counters, Gadget update time, simulation speed, client FPS and error log. Current code has static counter RulesParams, but no measured results yet.

`unitbasedefs/roguelike_weapon_effects.lua` owns the prototype effect and upgrade data; `unitbasedefs/roguelike_unit_tweaks.lua` adds the splitter test weapon to the ARM commander and the Synced Gadget adds a ground-target Meteor Strike command to Roguelike commanders only when the `_DEV` `roguelike_weapon_effect_tests` option is enabled. The meteor payload WeaponDef is defined in `weapons/roguelike_meteor_payload.lua` and loads in Roguelike mode for both the auto-targeting shop item and test command. `effects/roguelike_weapon_effects.lua` contains visuals only. `luarules/gadgets/game_roguelike_weapon_effects.lua` returns early unless `roguelike_mode` is enabled; prototype-only weapons/commands retain their dev gate.

The test Gadget accepts upgrade writes only through `GG.RoguelikeWeaponEffects.SetUpgrade(unitID, effectID, key, value)`. Values are clamped to the effect catalog and stored on the owning commander as `roguelike_effect_<effect>_<key>` RulesParams. Keep timers, pending volleys, active projectile counts and damage multipliers keyed by owner/projectile; never store player-specific weapon upgrades in one shared mutable number. Spawned bullets must inherit the root attacker's UnitID and TeamID. Keep the global projectile ceiling, per-owner ceiling, recursion limit and per-frame spawn budget in the catalog.

Use native WeaponDef projectiles for the actual hit and shield interception. The Synced Gadget may change runtime projectile AoE and must apply per-projectile damage scaling in `UnitPreDamaged`, preserving the existing Rogue attacker and target damage pipeline. Any future delayed AoE that does not use a native projectile must explicitly reproduce self/ally filtering, shield behavior, elite/Boss mitigation and attacker attribution before it is considered reusable. Do not modify Recoil C++ or activate these test weapons in standard BAR/Raptors games.

The first test prototypes are intentionally not connected to the shop, faction catalog or independent Lv.1–6 WeaponLevel system. Do that only after the base projectile paths pass the balance document's shield, friendly-fire, replay and multiplayer checks. No engine match has loaded this prototype yet; the current headless attempt stopped at local map dependency resolution, and the unit test/formatter CLIs are not installed. Treat all prototype values and runtime API interactions as unverified.

To test meteor, select the ARM commander, choose its `Meteor Strike` map command, then click a ground point within 900 elmos. The synced gadget rejects out-of-range and other-team requests, shows the warning for 45 frames, then spawns a real projectile 900 elmos over the clicked ground point. There is no commander-fired meteor projectile. The WeaponDef and each `Spring.SpawnProjectile` payload specify `model = "meteor.s3o"` and `cegTag = "meteortrail"`. Confirm the full visible fall and impact in a fresh match; this activation correction has not yet been runtime tested.

If the Meteor Strike command is missing, first inspect the generated SPADS `startscript.txt`. `roguelike_mode=1` alone is insufficient: `roguelike_weapon_effect_tests=1` must also be present before match start. The effect gadget returns without registering the command when the test option is false. This option is visible in the room's Roguelike mod options; SPADS must reload the SDD option list before it can be selected. The current session's startscript had the test flag absent, explaining its missing command.

## 2026-11-01 综合整理后的强制维护规则

1. 默认触发器是 onHit，只有显式声明 onKill 的条目可被击杀回调消耗；事件去重必须保留。测试既覆盖“不该触发”，也覆盖显式击杀仍能触发一次。
2. 观察通用原生弹丸的登记失败不得删除主弹。分裂生成端独占一次预算扣减；衍生子弹记录自身出生坐标，否则二代飞行距离触发失效。
3. 已经入队的陨石，仅在成功创建并登记后移出队列；玩家/全局容量满或引擎返回nil时保留等待。预算拒绝和排队延迟是不同状态，不写成满额即时输出。
4. 火区上限只计算火区；另行保留所有区域状态的总上限。新的状态类型不得复用错误的计数器。
5. UnitDamaged的最终伤害不得直接反馈进再次应用成长的AddUnitDamage路径；母弹基础伤害和最终承伤必须明确区分。具体数值口径见Balance最新节。
6. 设置框、房间覆盖层、全局隐藏UI共享同一输入屏蔽条件；只Hide文档而继续处理F1/选卡/鼠标属于缺陷。返回对局后恢复已存在的商店/卡片状态，不额外发送购买请求。
7. 当前Coop恰好两Team；四人是待扩展功能。角色Lv.60不等于武器Lv.60，当前阵营武器仍为Lv.1–3。
8. 新测试记录必须注明“源码解析 / 模拟Spring回调 / 引擎加载 / 单人实机 / 双人联机”；本轮模拟通过不覆盖RML排版、引擎伤害/护盾、回放或网络同步。
9. 发版前核对本机目录链接、发布状态与朋友客户端游戏包；开发模式同名源码不能代替完整包的校验。外部SPADS权限补丁需另外维护，不认为它已包含在游戏仓库里。

执行入口和文件指纹工具见 [总览](RoguelikeOverview.md)；本轮运行文件备份、用例结果及未解决项见 [综合审计](../docs/roguelike/audit-2026-11-01.md)。

## 战斗吸血与治疗预算维护规则

1. 伤害吸血必须通过 `game_roguelike_upgrades.lua` 的 `applyDamageTriggeredHealing` 和现有 `healCurrentCommander` 结算；不得由武器 Gadget 直接设置指挥官生命。
2. 伤害使用击中前后目标生命差，最多按击中前 HP 计。不得使用 WeaponDef 理论伤害或 UnitDamaged 的 damage 参数当作有效扣血量。
3. 生命偷取卡只有一个类型，分 I–V 五级，每级增加 25 个百分点命中概率；每次实际命中回复 500 + 5% MaxHP，与伤害值无关。概率超过 100% 时，每次命中先保证 `floor(probability)` 次回复，再按小数部分额外判定一次。
4. 商店“吸取”每级将实际生命伤害的 5% 转为治疗。生命偷取与“吸取”都不走旧的触发治疗预算，但回复不得超过缺失生命；击杀回血仍使用持续治疗总预算和每人 2 秒冷却。主动治疗和补给仍按既有预算。
5. 满血不记预算；护盾吸收、友军/自伤、中立目标、无生命损失、死亡攻击者、EMP 麻痹、D-Gun 禁止触发。一次目标伤害不得重复结算，DoT 只能按有限时间窗再次结算。
6. Coop 中卡牌、攻击归属、每秒治疗额、去重表和击杀冷却均按 Team 存取；所有实际回血仍由 Synced 负责。增加/修改卡时同步 RulesParams、卡牌当前/升级描述、HUD 和 Balance 数值记录。
7. 验证顺序：运行 Lua 语法解析、纯数值规则用例、武器效果模拟；之后在单人三阵营测试直伤/陨石/分裂/范围/DoT、友军、自伤、护盾和 50 HP 残血过杀；最后双人同 AllyTeam 测各自伤害、预算隔离、死亡重建及回放。纯模拟不能代替实机确认。

## 指挥官个人反弹盾

1. Roguelike 指挥官使用原生 Repulsor shield，读取 `roguelike_unit_tweaks.lua` 中的专用拦截位。`alldefs_post.lua` 仅在 Roguelike 模式为所有非 Shield WeaponDef 加上此位，包括原版标成 `interceptedbyshieldtype=0` 的弹丸；专用位只被 Rogue 指挥官盾匹配，不沿用原版 commander shield 的 479 掩码。
2. 引擎负责弹丸拦截、偏转与盾能量扣除。`UnitPreDamaged` 对单位生命收到的伤害只做其他 Roguelike 防御处理，不能再次从盾值扣相同伤害；否则引擎盾吸收和 Lua 盾值会重复计算。
3. 可反弹的实体弹丸由 Recoil 原生 Repulsor 改变轨迹；BeamLaser/LightningCannon 没有可返航的实体弹丸，效果是被盾拦截/吸收，不会变成反向光束。AoE 穿盾、`interceptedByShieldType` 未覆盖的特殊武器及实机碰撞效果需逐类核对。
