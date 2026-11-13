# Roguelike 检查工具

从仓库根目录运行。工具不会启动/停止房间，不修改 SPADS 权限，也不读取密码文件。

## 本地版本与房间快照

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/roguelike/Get-RoguelikeAudit.ps1
```

默认读取本机 `D:\BeyondAllReason` 下的客户端和服务器；其他机器使用 `-SourceRoot`、`-ServerRoot`、`-ClientData` 指定路径。输出只包含版本、目录链接、上次生成的开局选项、选定源码文件的 SHA-256。`lastStartscript` 不代表当前房间状态；源码指纹不替代完整游戏包和引擎校验。

## Lua 检查与模拟回调回归

验证工具隔离安装在 `.preview`，不加入游戏运行依赖：

```powershell
npm.cmd install --prefix .preview/roguelike-validation --cache .preview/npm-cache --no-save --ignore-scripts --no-audit --no-fund fengari-node-cli@0.1.0 luaparse@0.3.1
node tools/roguelike/Validate-Sources.cjs
.preview\roguelike-validation\node_modules\.bin\fengari.cmd tools/roguelike/Test-WeaponEffects.lua
node tools/roguelike/Test-ShieldRepulsion.cjs
.preview\roguelike-validation\node_modules\.bin\fengari.cmd tools/roguelike/Test-Multishot.lua
.preview\roguelike-validation\node_modules\.bin\fengari.cmd tools/roguelike/Test-DamageHealing.lua
.preview\roguelike-validation\node_modules\.bin\fengari.cmd tools/roguelike/Benchmark-DamageHealing.lua 100000
```

`Validate-Sources.cjs` 按 Lua 5.1 解析模式与集成文件。`Test-WeaponEffects.lua` 在 Fengari 的 Lua 5.3 环境模拟 Spring 回调，检查容量、队列、触发与伤害基数。它执行真实 Gadget 文件，不是重写算法。可给它传入旧 Gadget 路径比较修复前后。

本轮范围扩充为 24 个 Lua 文件（含 Raptor/Scav 互斥入口），模拟回调 13 项（含无 projectileID 的 BeamLaser 回退及 Boss 派生伤害标记恢复）。启动器开发版勾选“Roguelike 模式”后才写入 `roguelike_mode=1`；地图点击测试陨石命令另需 `roguelike_weapon_effect_tests=1`。

两者都不验证 Recoil API 行为、护盾碰撞、回放、RML 排版、双客户端同步或实际帧耗。实机验收见 [开发与游玩总览](../../doc/RoguelikeOverview.md)。
