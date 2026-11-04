# BAR PVE 性能优化记录

日期：2026-10-29。源码版本：`modinfo.lua` 中的 `0.1.0-dev.2`；起点提交 `3f5b4d94feff3b11c698b8ac39b2b6e970b4599d`。工作分支：`pve/performance-optimization`。

## P0：源码与基线

| 范围 | 实际入口 | 结论 |
|---|---|---|
| Raptors 与 Scavengers 生成 | `luarules/gadgets/raptor_spawner_defense.lua`、`scav_spawner_defense.lua` 的 `Wave`、`SpawnRaptors`/`SpawnScavs`、`GameFrame` | 原来只有 `Game.maxUnits * 0.8` 的敌方队伍总数守门；波次队列无界，一次调用可创建一整支小队。Scavengers 另有被俘单位的替换生成队列。 |
| 虫族决策 | 两个 spawner 的 `manageAllSquads`、`refreshSquad`、`getRandomEnemyPos` 和每 7 帧的队伍遍历 | 现有小队已经共享目标与命令；目标候选集合由事件维护，Raptors 的目标选择还有已有的 Tracy 标记。应先减少实际的周期成本，不另建并行控制器。 |
| 玩家单位与炮台 | `unit_weapon_smart_select_helper.lua`、`unit_preaim.lua`、单位和武器定义 | 智能武器 Gadget 已按 unitID 分帧检查；基础自动索敌主要由引擎负责。当前缺少显示这些路径是 PVE 热点的实测数据。 |
| 开发测量 | `dbg_benchmark.lua`、Tracy、`tools/headless_testing` | 可用 Recoil headless 验证同步 Lua 加载和早期模拟。headless 没有可用画面 FPS/GPU 数据，也不能替代多人同步测试。 |

对照测试使用当前分支、优化开关全关，而非独立检出的原始提交。场景为 Quicksilver Remake 1.24、1 名人类玩家、Raptors epic、固定 RNG seed、1000～2300 帧的 benchmark 窗口。1170 个采样帧的 `Sim` 均值为 **16.89 ms**，创建 85 个单位、摧毁 21 个单位。这个样本只有单人前期负载；其计时路径还包含 headless 的帧调度，不能当作 8～16 人后期 CPU 基线。

## 已实施的修改

### P1：数量与生成节奏

- 新增 `luarules/Utilities/pve_spawn_budget.lua`，按实际非观战玩家的 teamID 计算 1～16 人战斗虫数量上限。16 人候选值为 960；1 人是该值的 12.5%。队伍总数仍受原引擎上限约束。
- 战斗虫、建筑、最终 Boss 分别计数。战斗虫按单位金属成本划为权重 1/2/5/8，Boss 单独计算；同时检查数量与权重预算。重型数量也单独发布为 GameRulesParam。分类和权重是初始候选，尚需后期平衡测试。
- 两个波次队列改为有界 FIFO；预留名额随入队、出队、队列清空和虫巢死亡释放。默认队列最多 128，生成每 15 帧至多 4 个；Raptors 开局加速不再绕过该节奏。超额请求丢弃，不留作未来突发波次。
- 两个 spawner 的 `AllowUnitCreation` 对敌方队伍的直接创建也执行分类上限，并计入已有预留；队列单位在实际创建前消费自己的预留。Scavengers 的俘获替换队列纳入共同队列容量，并按批次处理。每 30 帧发布当前各类数量、战斗权重、队列数与剩余战斗虫名额。
- 默认上限会改变波次强度、开局速度和 Boss 之前的单位组成；这是游戏平衡变化。

### P2：已有小队决策的错峰

- `manageAllSquads` 的非紧急目标刷新分成 3 组，依据帧号轮转；目标死亡等已有事件刷新路径仍保留。关闭 `pve_ai_stagger` 后走原来的抽样顺序。
- 波次规模统计在开启数量限制时只计实际人类玩家 teamID；AI 队伍不再被当作玩家扩张预算。
- 尚未建立每名玩家的基地、经济、压力与战术区域管理器。现有全局目标候选池已经由事件维护，缺乏 8～16 人热点数据时重写它有同步、玩法和性能风险。

### P3/P4：保留战斗能力并处理可确定的重复工作

- 没有改玩家自动攻击、防御塔索敌、武器伤害、弹道、残骸或经验。当前证据不足以选择某种武器或规则作安全删减；这些改动需要单独的多人后期与客户端测试。
- 两个 spawner 每 7 帧的随机繁殖检查，在敌方队伍达到 100 单位时仅在该次遍历内缓存单位类型数量，减少同一类型的重复 `GetTeamUnitDefCount` 调用。缓存随本轮遍历结束失效；同一轮内新生单位可能使概率与原版略有差异。
- `dbg_benchmark.lua` 现在对 headless 连续 `Update` 只计一次模拟样本，空的 Draw/Update 系列不会除零，总耗时按秒输出。
- 修复 `Game.gameShortName=BARPVE` 时 Scavengers 遗迹蓝图查找失败：若不存在对应目录，则使用已有 BYAR 蓝图。未新增遗迹扫描逻辑。

### 配置开关

`modoptions.lua` 提供：`pve_spawn_limits`、`pve_enemy_unit_cap`、`pve_structure_cap`、`pve_boss_cap`、`pve_combat_budget_mult`、`pve_spawn_queue_cap`、`pve_spawn_interval`、`pve_spawn_per_call`、`pve_ai_stagger`、`pve_population_cache`。英文界面说明见 `language/en/interface.json`。默认战斗虫上限 960、建筑 120、Boss 2、队列 128、每 15 帧最多 4 个。关闭相应开关可对照原有逻辑。

## 验证记录

测试引擎：已安装的 Recoil `recoil_2026.07.04` 的 `spring-headless.exe`。隔离运行目录位于系统临时目录，游戏目录通过 junction 指向当前工作树，地图和 engine base 指向本机安装目录。没有部署本地服务器或改联机配置。

| 场景 | 结果 |
|---|---|
| Raptors，单人，2400 帧，三项 PVE 开关全关 | 正常结束；benchmark 1170 样本、`Sim` 均值 16.89 ms；创建 85、摧毁 21。 |
| Raptors，单人，2400 帧，三项 PVE 开关全开 | 正常结束；benchmark 1170 样本、`Sim` 均值 16.95 ms；创建 101、摧毁 16。两组负载不同，不能据此计算提速。 |
| Scavengers，单人，1200 帧 | spawner 同步和非同步部分正常加载，正常到达第 1200 帧；未见相关 Lua 异常。 |
| Raptors，单人，候选上限 100，首波增强，1200 帧 | 第 1100 帧为战斗虫 7、待生成 6、剩余名额 0，合计等于单人折算上限 13；建筑另有 5 个。验证了预留名额与建筑独立计数。 |
| Scavengers，单人，候选上限 100，较快波次，1200 帧 | 第 1100 帧战斗单位 13、建筑 5、剩余名额 0；无相关 Lua 异常。验证了另一种敌人的分类上限。 |
| 最终代码，两种 AI，各 30 帧加载检查 | 两个防御 spawner 均加载，无相关 Lua 异常。 |
| 静态检查 | `git diff --check` 通过；`language/en/interface.json` 经 Node `JSON.parse` 通过。 |

此前一次测试暴露 Scavengers `GameFrame` 超过 Lua 5.1 的 60 upvalue 限制，已通过提取队列统计函数并复用现有 `config` 捕获修复。修复后重新检查了两个 spawner 的加载。

这些短时 headless 测试无法证明 CPU 收益百分比、FPS、最慢 1% 帧、Boss 战、玩家操作体验或多人同步。基线和优化版单位数量与随机序列可能不同，`Sim` 均值只作早期回归观察，不作算法提速结论。

## 未完成的验收与建议

1. 使用相同地图、难度、玩家配置和后期存档，分别采集 4/8/16 人的单位数、Lua Gadget 耗时、平均与最慢 1% 模拟帧、客户端 FPS、CPU/内存以及同步错误。对数量控制和算法优化分别做开关对照。
2. 按这些数据决定是否需要完整的玩家组调度器，以及是否值得改武器、炮台、残骸或视觉效果；每项另做平衡测试。优先测 Boss 生成、Scavengers 大量俘获替换和满队列时的体验。
3. 目前不能宣称达到文档中的多人后期性能目标，也不能宣称多人同步稳定。P5 引擎优化应等 Lua 与规则层的后期数据明确指向引擎瓶颈后再启动。
