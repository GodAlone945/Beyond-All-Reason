-- [表现定义：无人机纳米修复 CEG]
-- LuaRules synced Gadget 在确认实际扣电和回血后生成该 CEG。
-- 粒子沿 SpawnCEG 传入的 dir 从无人机飞向指挥官，仅承担可视反馈；
-- 修改这里不会改变回血量、电力消耗、触发阈值或任务优先级。

return {
	["roguelike-drone-repair-nano"] = {
		nano = {
			air = true,
			class = [[CSimpleParticleSystem]],
			count = 1,
			ground = true,
			water = true,
			underwater = true,
			properties = {
				airdrag = 1,
				colormap = [[0.25 1 0.35 0.04   0.55 1 0.65 0.85   0.15 0.75 0.25 0.55   0 0 0 0.01]],
				directional = true,
				emitrot = 0,
				emitrotspread = 3,
				emitvector = [[dir]],
				gravity = [[0, 0, 0]],
				numparticles = 3,
				particlelife = 20,
				particlelifespread = 3,
				particlesize = 2.2,
				particlesizespread = 0.8,
				particlespeed = 9,
				particlespeedspread = 1,
				pos = [[0, 0, 0]],
				sizegrowth = -0.025,
				sizemod = 1,
				texture = [[nanopart]],
			},
		},
	},
}
