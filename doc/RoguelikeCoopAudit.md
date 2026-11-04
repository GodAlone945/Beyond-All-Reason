# Roguelike Coop 双人阶段审计与交付记录

> 当前总览见 [RoguelikeOverview.md](RoguelikeOverview.md)，最新问题和测试见 [综合审计](../docs/roguelike/audit-2026-11-01.md)。本页保留双人阶段历史证据；旧引擎加载检查不覆盖后续效果系统修改。当前源码仍强制恰好两支玩家Team。

> 2026-11-01。依据实际仓库代码与 `BAR_Roguelike_Multiplayer_Development_Plan.md` 审计。设计文档中的数值和后续玩法均不视为已实施或已实测。

## M0：代码审计（完成）

| 模块 | 修改前的实际单实例假设 | 双人风险与 M1 处理 |
| --- | --- | --- |
| `game_roguelike_spawner.lua` | 只保存 `playerTeamID/playerUnitID`；开局清理除一名指挥官外的单位；只给一人写波次和击杀；敌军只追一人 | 改为排序的两支人类 Team、同一 AllyTeam、各一名玩家；保留两名指挥官，共享一套敌人/波次/击杀；刷点围绕存活指挥官轮换，敌军追最近的存活指挥官。全部死亡后停止推进。`GetTeamInfo` 的 AllyTeam 是第六返回值。 |
| `game_roguelike_upgrades.lua` | 升级次数、候选、商店等级、护盾、属性倍率和武器槽缓存均是一个变量；购买 sender 虽有 Team 校验，却只认一个 `playerTeamID`；个人结果向所有客户端广播 | 每个 Team 独立状态；按真实 sender `playerID` 查询 Team；每人独立选卡/购买/扣自己的资源；个人事件只转发给所属 Team；同步请求恢复 UI 快照。共享击杀阈值触发每人一次独立候选。 |
| `game_roguelike_orbit_drones.lua` | 一名指挥官、一份等级与无人机列表 | 等级、成长、实例、修复目标按 Team 隔离；无人工智能和资源共用。 |
| `game_roguelike_salvage.lua` | 一名回收者、一份奖励总额；无人机回收默认属于同一 Team | 以请求单位真实 Team 找指挥官；资源只给该 Team，累计回收额按 Team 保存。敌方残骸白名单仍全局只结算一次。 |
| `game_roguelike_faction_weapons.lua` | 只认最后注册的一名指挥官；同款 DoT/减速/蜂群节流键会跨玩家覆盖 | 识别每名指挥官，武器等级取 owner 的 RulesParam；持续效果和蜂群节流按 owner 分键。 |
| `gui_roguelike.lua` | 已按本地 Team 找指挥官；商店只能休整打开，弹窗请求暂停全局游戏 | 商店随时打开；Coop 不发送全局暂停；重新连接或 `/luaui reload` 时向 synced 请求个人状态。 |
| 武器槽与 UnitDef | ARM：主激光1、手动 D-Gun2、AA3、护盾4；已购商店武器由 Synced 攻击控制器触发。COR：基础1–3、AA4、通用5–9、专属10–13；LEG：基础1–4、通用5–9、专属10–13 | ARM 攻击冷却按指挥官 UnitID 独立存放；所有队伍的购买、伤害归属、弹道和同步需双客户端实测。 |

## 分阶段改动计划

1. **M1 双人同步骨架（本轮）**：`roguelike_mode=1` 且 `roguelike_coop=1` 时恰好两名非观战玩家，各占一个 Team、同属 AllyTeam；共享波次/击杀，个人属性、武器、无人机、商店与金属独立。波间等待 0 秒，商店任何阶段可用；单人 Roguelike 同样采用这两项新规则。玩法关键结算仍在 Synced Gadget。
2. **M2 队友生存与恢复（后续）**：倒地/有限复活、队友状态面板、死亡后的商店/选卡处理，恢复同一 Team 的成长状态。M1 只保证单人倒下时幸存者继续，全部倒下时停止刷怪。
3. **M3 难度与经济（后续）**：双人前八波掉落、时间边界治疗、共享击杀阈值与持续刷怪速率调参；本轮单人和双人使用相同的时间目标数及 HP/伤害曲线，敌方 HP 只参考当前最强玩家伤害倍率，不累加两人倍率。
4. **M4 联机压力与扩人数（后续）**：双客户端真实同步、掉线重连、延迟/desync、三至四人以及性能上限；未经 M1 实机验收不扩人数。

## M1 本轮文件与结果

**变更文件：** `modoptions.lua`、`language/en/interface.json`、`game_roguelike_spawner.lua`、`game_roguelike_upgrades.lua`、`game_roguelike_orbit_drones.lua`、`game_roguelike_salvage.lua`、`game_roguelike_faction_weapons.lua`、`gui_roguelike.lua`、`RoguelikeMaintenanceManual.md`、`RoguelikeArchitecture.md`、`RoguelikeBalance.md`、本文件。

**已检查：** 使用 Recoil 2026.07.04 的 `spring-headless.exe`，用两支人类 Team、同一 AllyTeam、`roguelike_mode=1`、`roguelike_coop=1` 的 startscript 加载至 `[Game::Load][8]`；五个 Roguelike synced Gadget 均加载。首次加载发现 AllyTeam 返回值读取错误，已修正为 `GetTeamInfo` 第六项。最终代码复测日志位于 `.preview/roguelike-coop-smoke/run9/infolog.txt`，未出现 Coop 队伍拒绝或 Roguelike Gadget 初始化错误。该测试停在双方玩家就绪前，没有运行实际波次；随后一处低风险的指挥官查找频率优化未再重跑加载检查。

**未实机验证：** 双客户端从开局到第八波、两人同帧购买/选卡、重连后 Team 归属与 UI 补发、同阵营双人、不同阵营武器效果、掉线时角色保留、一人死亡后幸存者继续、两人死亡后房间结算、单人回归、普通 BAR 回归。测试时要逐客户端比对资源、RulesParam、伤害、敌人数、波次、同步错误和 `infolog.txt`。

**当前未解决：** M1 不提供死亡复活或中途加入角色；无队友状态面板；双人共享击杀阈值及残骸先到先得经济尚未调参；现有 `coop` ModOption 是 BAR 的同 Team 多指挥官功能，本模式房间应只启用 `roguelike_mode` 与 `roguelike_coop`，并把两名玩家分到不同 Team。所有这些项目继续保持“未验证/待后续阶段”状态。

### M1 实机测试步骤（待执行）

1. 两个客户端分别占 Team 0、Team 1，同属 AllyTeam 0，分别选择 ARM、COR；开启 `roguelike_mode=1`、`roguelike_coop=1`，进入游戏后核对两名指挥官都保留、双方波次和击杀一致。
2. 战斗阶段分别打开 F1 商店，连续购买、装备各自阵营专属武器并选卡；确认只扣本 Team 金属、只改变本指挥官 RulesParam、另一客户端没有收到个人弹窗，二人均不暂停游戏。
3. 从第一波进入第二波记录时间边界：两波之间不得停止补兵或清除残敌；核对边界治疗 10% 最大生命，残骸只结算一次且资源归实际吸收者 Team。
4. 让一人掉线并重连或执行 `/luaui reload`，检查已购列表、待选卡、指挥官归属和攻击；随后让一人死亡，确认幸存者继续推进，最后双人死亡确认不再刷怪。
5. 再用 ARM+ARM、LEG+ARM 组合检查武器槽和攻击，最后分别做单人 Roguelike 与普通 BAR 回归。逐客户端对照 `infolog.txt` 是否出现同步错误和 Lua 错误。
