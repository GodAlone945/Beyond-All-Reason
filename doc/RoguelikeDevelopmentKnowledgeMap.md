# BAR Roguelike 开发知识地图

> 源码快照：2026-11-04。本页是学习和定位入口，按当前工作区源码核对；不是实机验收报告。玩法规则看 [维护手册](RoguelikeMaintenanceManual.md)，模块契约看 [架构说明](RoguelikeArchitecture.md)，数值看 [平衡表](RoguelikeBalance.md)。这些旧文档中的历史测试结论需要按测试时间和当前代码重新核验。

## 先建立三层心智模型

| 层 | 何时执行 | 在本项目做什么 | 主要入口 |
| --- | --- | --- | --- |
| 定义加载 | 一局开始、创建单位前 | 按模式选项修改 `UnitDef` 和内嵌 `WeaponDef`，决定指挥官实际有哪些武器槽 | `modoptions.lua` → `gamedata/alldefs_post.lua` → `unitbasedefs/roguelike_unit_tweaks.lua` → `gamedata/weapondefs_post.lua` |
| LuaRules Synced | 游戏模拟帧，在各客户端执行相同的权威逻辑 | 波次、刷怪、资源消费、升级、伤害、残骸、无人机 | `luarules/gadgets/game_roguelike_*.lua` |
| LuaRules Unsynced / LuaUI | 每个客户端本地 | 把模拟结果通知本地界面；展示状态、收集输入 | Upgrades 的 unsynced 分支 → `luaui/RmlWidgets/gui_roguelike/` |

**先分清 `UnitDef` 和 `UnitID`。** `UnitDef` 是整局共享的单位模板，武器槽在定义加载时确定；`UnitID` 是场上一名指挥官实例，其购买等级、射程、生命等可在运行时变化。购买不能临时给已有单位追加模板武器槽，所以新加武器槽后必须重新开局。`WeaponDefID` 指武器模板，`weaponNum` 指这名单位的武器槽序号，两者不能混用。

## 源码导航：从哪里找、由谁负责

建议先打开这些源码锚点：[模式选项](../modoptions.lua#L2238) → [定义处理入口](../gamedata/alldefs_post.lua#L671) → [指挥官武器安装](../unitbasedefs/roguelike_unit_tweaks.lua#L498) → [波次主循环](../luarules/gadgets/game_roguelike_spawner.lua#L966) → [购买校验](../luarules/gadgets/game_roguelike_upgrades.lua#L1708) → [ARM 瞄准回调](../scripts/Units/armcom_lus.lua#L1171) → [阵营武器结算](../luarules/gadgets/game_roguelike_faction_weapons.lua#L415) → [商店请求](../luaui/RmlWidgets/gui_roguelike/gui_roguelike.lua#L85) → [详细信息计算](../luaui/Widgets/gui_unit_stats.lua#L516)。锚点对应本次源码快照，后续改动可能使行号移动，以函数名为准。

| 需求或现象 | 先读的文件与函数 | 需要追踪的状态 / 调用 |
| --- | --- | --- |
| 模式开关与普通模式隔离 | `modoptions.lua` 的 `roguelike_mode` / `roguelike_coop`；`gamedata/alldefs_post.lua` 调用 `roguelikeUnitTweaks`；`unitbasedefs/roguelike_unit_tweaks.lua:roguelikeUnitTweaks` | `modOptions` 的布尔或字符串形式；仅对指定指挥官/敌人修改定义 |
| 指挥官武器池、槽位、伤害模板 | `unitbasedefs/roguelike_unit_tweaks.lua:installCommonShopWeapons`、`installFactionWeapons`；`unitbasedefs/roguelike_weapon_catalog.lua`；`gamedata/weapondefs_post.lua:ExtractWeaponDefs` | `unitDef.weapondefs` 是定义表；`unitDef.weapons` 是槽列表；加载后在 `UnitDefs` / `WeaponDefs` 用 ID 查询 |
| 波次与敌军 | `game_roguelike_spawner.lua:findTeams`、`startCombatPhase`、`GameFrame`、`UnitDestroyed` | `currentWave`、生成额度、`aliveEnemies`、`GG.Roguelike.totalKills` |
| 击杀、角色成长、升级卡 | `game_roguelike_upgrades.lua:processEffectiveKill`、`processKillCount`、`offerUpgradeChoices`、`receivePersonalMessage`、`applyCardUpgrade` | 共享 XP 与个人 Team 状态；`choiceId` 与待选卡；`roguelike_pick` 请求 |
| 商店扣费与装备 | `game_roguelike_upgrades.lua:RecvLuaMsg`、`buyShopItem`、`setFactionWeaponEquipped`、`applyCommanderStats`、`applyWeaponRange` | `shopLevels`、`equippedFactionWeapons`、Team 金属、`roguelike_shop_*_level`、`roguelike_weapon_equipped_*` |
| ARM 武器实际开火 | `scripts/Units/armcom_lus.lua:AimWeapon` / `FireWeapon`；`game_roguelike_faction_weapons.lua:OnWeaponFired`、`ProjectileCreated`、`Explosion` | 已购与装备门禁；`weaponNum` → `WeaponDefID`；阵营机制伤害和原生弹道 |
| 其他指挥官的商店槽 | `unitbasedefs/roguelike_unit_tweaks.lua`；`scripts/Units/corcom_roguelike.cob`、`legcom_roguelike.cob` | COR/LEG 使用 Roguelike 专用 COB；不能假设 ARM Lua 脚本会运行在它们身上 |
| 特效、连锁、陨石、分裂 | `game_roguelike_weapon_effects.lua:Initialize`、`ProjectileCreated`、`UnitDamaged`、`Explosion`、`GameFrame`；`unitbasedefs/roguelike_weapon_effects.lua`；`effects/roguelike_weapon_effects.lua` | `GG.RoguelikeWeaponEffects` 事件上下文、投射物归属、伤害只结算一次 |
| 残骸变金属 | `game_roguelike_salvage.lua:UnitDestroyed`、`FeatureCreated`、`GameFrame`；`GG.Roguelike.AbsorbWrecksForUnit` | 敌军来源白名单、D-Gun 排除、半径/速度倍率、Team 金属 |
| 无人机攻击与修复 | `game_roguelike_orbit_drones.lua:spawnDrone`、`updateDrones`、`repairCommander` | 阵营无人机定义、任务优先级、`GG.Roguelike.HealCommander` 与成长倍率 |
| 商店/HUD/选卡界面 | `gui_roguelike.lua:personalRequest`、`handleBuyShopItem`、`RoguelikeShopResult`、`Update`；同目录 `.rml` / `.rcss` | 请求 nonce、RulesParam、异步回执、F1 商店暂停、UI 本地缓存 |
| 指挥官详细信息 | `luaui/Widgets/gui_unit_stats.lua:computeContent`、`drawStats` | 已购武器筛选；`roguelike_shop_revision` 触发重新计算。`gui_info.lua` 是另一块概览 UI，别把两者混为一谈 |
| 调试与回归 | `tools/roguelike/Validate-Sources.cjs`、`Test-ArmShopWeapons.lua`、`Test-FactionShopWeapon.lua`、`Test-WeaponEffects.lua`、`Test-DamageHealing.lua` | 分别覆盖语法、定义、模拟回调；不能替代引擎、画面、联机或性能测试 |

### 读代码时先看这四条调用链

**1. 商店购买与装备**

```text
F1 商店点击
  → LuaUI gui_roguelike.lua:personalRequest("roguelike_shop", itemId)
  → Spring.SendLuaRulesMsg("roguelike_shop:<frame>-<counter>:<itemId>")
  → Synced Upgrades:RecvLuaMsg → receivePersonalMessage → buyShopItem
  → 校验玩家/Team/阵营/解锁/槽位/价格 → 扣 Team 金属
  → shopLevels + 1 → applyCommanderStats → applyWeaponRange
  → SetUnitRulesParam(等级与界面刷新版本) → sendShopResult
  → SendToUnsynced → Unsynced AddSyncAction → Script.LuaUI.RoguelikeShopResult
  → RML 提示、卡片刷新；详细单位信息读取等级和刷新版本
```

`shopLevels` 是 Synced 的权威状态；RulesParam 是给引擎其他 Lua 环境和 UI 读取的镜像。看到“购买成功”只说明请求通过、扣费和状态更新，不能据此证明武器已经瞄准、发射或显示特效。已购阵营武器若装备槽满，会成功购买但不自动装备，需再检查 `roguelike_weapon_equipped_<itemId>`。

**2. ARM 商店武器开火**

```text
开局前 UnitTweaks 安装原生武器槽
  → 引擎给已购、射程非零的槽选择目标
  → armcom_lus.lua:AimWeapon 再查等级/装备规则参数
  → 引擎发射原生弹丸或光束；FireWeapon 调 GG.RoguelikeFactionWeapons.OnWeaponFired
  → 阵营光束由 handleSpecialWeapon / applyWeaponEffect 结算机制伤害
  → 炮弹/导弹由 ProjectileCreated 记目标，Explosion 结算机制伤害
```

这里有两个不同的“效果”：可见弹道由原生武器定义和模型枪口负责，阵营特效的额外伤害由 Gadget 负责。`ProjectileCreated` 与 `Explosion` 可能针对一束光出现多次，排查重复伤害时必须区分“视觉事件数”和“逻辑开火次数”。普通商店武器的原生 `WeaponDef.damage` 自行结算，不能再按阵营机制加一遍。

**3. 波次、击杀和选卡**

```text
Spawner:GameFrame → startCombatPhase / 定时生成 / 敌人追击
  → 敌军 UnitDestroyed → totalKills + 1
  → GG.Roguelike.OnKill(totalKills, 死亡位置)
  → Upgrades:processEffectiveKill → processKillCount → offerUpgradeChoices
  → Synced 发选择事件 → 本地 LuaUI 展示
  → 玩家 roguelike_pick:<choiceId>:<upgradeId>
  → Upgrades 核对待选项和 Team → applyCardUpgrade → 属性/RulesParam 更新
```

当前 `GameFrame` 每 `Game.gameSpeed` 帧推进主要波次逻辑；战斗波次按 70 秒时间边界切换，旧敌人不在边界清空。`UnitDestroyed` 统计的是 Spawner 跟踪的敌军，因此燃烧、无人机等击杀路径不应只看最终 `attackerTeam`。别把“波次编号”“累计作战秒数”和“角色等级”当成同一个计数器。

**4. 残骸经济与无人机**

```text
敌军死亡 → Salvage 标记合格来源
  → FeatureCreated(sourceID) 验证该来源 → 合格残骸进入待吸收集合
  → 指挥官附近吸收，或 Drones 调 GG.Roguelike.AbsorbWrecksForUnit
  → Spring.AddTeamResource(teamID, "metal", reward)
  → 金属成为下一次商店购买的可消费资源
```

不要把 `FeatureCreated` 直接等同于敌军残骸；地图初始残骸和友军残骸不应被计入这条收益链。

## 学 Recoil / Lua 时最值得抓住的概念

1. **Call-in 不是普通函数调用。** `gadget:GameFrame`、`UnitDestroyed`、`ProjectileCreated` 等由引擎按事件调用；同名 call-in 的签名和触发次数需要核对。`script.AimWeapon` / `FireWeapon` 则属于单位脚本回调，和 Gadget call-in 是不同入口。
2. **`GG` 是 Synced Gadget/单位脚本间的共享接口。** 例如 Spawner 调 `GG.Roguelike.OnKill`，ARM 单位脚本调 `GG.RoguelikeFactionWeapons.OnWeaponFired`。接口由对应 Gadget 在 `Initialize` 注册、在 `Shutdown` 清理；调用方须容忍尚未注册。
3. **RulesParam 是镜像，不是购买授权。** `Spring.SetUnitRulesParam` 给其他模块和 UI 读状态；消费资源和合法性始终由 Upgrades 的 Synced 表决定。`INLOS_ACCESS` 决定可见性，联机时不能随意把私有状态写成所有人可读。
4. **Lua 中 `0` 仍为真。** 代码用 `(level or 0) > 0`、`equipped == 1` 判断，不能写成 `if level then`。`ipairs` 顺序遍历连续武器槽，`pairs` 遍历按 key 保存的状态；Team 表的访问不能假定只有一人。
5. **Lua 文件的加载方式有环境边界。** `VFS.Include` 从游戏虚拟文件系统载入配置；`require` 有模块缓存；Synced、Unsynced、LuaUI 不是共享同一份普通 Lua 局部变量。`SendToUnsynced`、`Script.LuaUI`、`SendLuaRulesMsg` 才是跨边界通信路径。
6. **帧数和秒数要显式换算。** `Game.gameSpeed` 用在波次、冷却、持续效果中；`widget:Update(dt)` 是本地 UI 更新，不适合作为权威战斗计时。F1 商店暂停单人模拟时，画面仍可能刷新而 `GameFrame` 不前进。

联机时尤其要看 `Spawner:findTeams` 和 `Upgrades:withTeam`：当前 Coop 限定两支同盟人类 Team、每队一名玩家；波次和击杀共享，选卡、购买、装备按 Team 保存。`withTeam` 在一次回调前切换当前 Team 的局部状态，回调后再写回并恢复；在这段路径增加早退或异步行为时要检查状态归属。性能上，Spawner 的敌军遍历、阵营武器的 `GetUnitsInCylinder`、Weapon Effects 的弹丸追踪都随场上对象数增加；代码审计只能定位热点候选，真实开销仍需长局计时。若以后修改引擎 C++ 或升级 Recoil，须单独核对 call-in 签名、事件注册、同步确定性和引擎版本，不能凭 Lua 模拟测试通过就推断兼容。

## 建议学习顺序与可独立完成的小练习

| 顺序 | 学习范围 | 读完应能独立回答的问题 | 最小练习（只观察，不改功能） |
| --- | --- | --- | --- |
| 1 | 模式入口与定义加载 | `roguelike_mode=0/1` 怎样影响 ARM 武器槽？为什么旧对局不能加载新槽？ | 在 `UnitTweaks` 中顺着 `armcom` 分支数出槽位，运行 `Test-ArmShopWeapons.lua` 对照结果 |
| 2 | 商店请求到回执 | 谁决定价格、扣金属、写等级？购买成功消息来自哪里？ | 从 UI 的 `personalRequest` 追到 `buyShopItem`，列出每一步失败原因 |
| 3 | 武器开火和伤害 | 原生弹道与 Gadget 机制伤害各负责什么？如何避免双算？ | 沿 ARM `AimWeapon` → `FireWeapon` → Faction Weapons 画一条自己的调用链 |
| 4 | 波次和升级卡 | 一次敌军死亡如何变成选卡？时间边界为何不等于清怪？ | 追踪 `totalKills`、`sharedXP`、`choiceId` 三个值的写入点 |
| 5 | 残骸、治疗、无人机 | 金属与治疗的权威入口在哪里？ | 追踪一个 `sourceID` 从敌军死亡到金属增加 |
| 6 | 联机与性能 | 哪些状态共享，哪些按 Team 保存？哪些循环随敌人数增长？ | 阅读 `withTeam`、Spawner `findTeams`、各 `GameFrame` 的执行频率，再设计双客户端验证表 |

先读 1–3，再扩展到 4–6。Upgrades 文件很长，不需要从第一行顺读；沿上述函数链跳转，更容易看出状态的所有者。

## 用近期“购买成功但看不到武器”练习最小排错

固定条件：新开一局、`roguelike_mode=1`、ARM 指挥官、购买一件初期通用武器、关闭 F1、让一个敌对地面单位进入射程。只改变一个变量，记录商品 ID、指挥官 UnitID、目标 UnitID、游戏帧和当前源码版本。

| 检查点 | 看什么 | 如果不符合，应先查哪里 |
| --- | --- | --- |
| ① 定义 | `UnitDefs[commanderDefID].weapons` 是否存在标记 `roguelike_shop_item` 的槽 | `alldefs_post` → `UnitTweaks` → `weapondefs_post`；先确认新对局和模式选项 |
| ② 购买 | `shopLevels[itemId]` 与 `roguelike_shop_<itemId>_level` 是否为 1；金属是否扣一次 | UI 请求 nonce、`RecvLuaMsg`、`buyShopItem` 的 Team/价格/槽校验 |
| ③ 激活 | 对应 `weaponNum` 的 `Spring.GetUnitWeaponState(unitID, weaponNum, "range")` 是否大于 0；阵营武器装备参数是否为 1 | `applyWeaponRange`、`GG.UnitAttributes`、`AimWeapon` |
| ④ 开火与结算 | 是否有引擎投射物/单位脚本 `FireWeapon`；目标 HP 是否下降、伤害事件归属哪个 `WeaponDefID` | 原生武器参数、模型枪口、Faction Weapons、Weapon Effects |
| ⑤ 展示 | 详细信息是否出现等级和武器；实际客户端是否见到光束/弹道 | `gui_unit_stats.lua` 的缓存刷新、RML 回执、可见武器参数；必须实机目视确认 |

必要日志应只在指定 UnitID、weaponNum 和短时间窗口打印，并标记 `[frame][team][unit][slot][item]`。长期逐帧打印会改变性能表现。先获得失败的第一个检查点，再改最小模块；不要把“回执成功”解释为“开火已验证”，也不要把模拟回调等同于真实画面。

## 测试证据分级与今后协作输出

| 等级 | 能证明什么 | 不能证明什么 |
| --- | --- | --- |
| 源码分析 | 配置、分支、调用链和潜在风险 | 引擎一定按预期执行 |
| Lua 解析 / 模拟回调 | 语法和被模拟的函数输入输出 | Recoil 真实事件顺序、图形、联机 |
| Headless 引擎 | 实际定义加载、Synced 事件、资源和伤害 | 可见特效、交互布局、双客户端一致性 |
| 图形客户端实测 | 界面、弹道、手动操作 | 双人同步或长局性能，除非专门测试 |
| 双客户端 / 长局实测 | 状态隔离、重连与帧耗趋势 | 未覆盖的地图、版本或配置 |

从仓库根目录开始可运行 `node tools/roguelike/Validate-Sources.cjs`；模拟回调和审计命令见 [工具说明](../tools/roguelike/README.md)。工具依赖放在 `.preview`，缺少依赖时应按工具说明安装。`git status` 当前包含大量已有未跟踪的 Roguelike 文件，所以审查不能只依赖 `git diff`；同时核对文件清单。每次功能任务建议交付：**触发条件与首个失败检查点 → 修改前调用链 → 最小变更及可回滚文件 → 副作用/联机或性能风险 → 分级测试证据 → 你可复述的关键机制**。这份文档本身只经过源码核对和链接检查，不代表新一轮游戏验证。
