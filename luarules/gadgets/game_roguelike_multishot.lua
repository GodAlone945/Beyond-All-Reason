-- 只为配置中明确允许的 ARM 商店武器生成额外弹丸。
-- 原弹丸由引擎发射；此 Gadget 复制其出生位置和速度，再水平旋转形成扇形齐射。
local gadget = gadget

function gadget:GetInfo()
	return {
		name = "Roguelike Multishot",
		desc = "Simultaneous full-damage projectiles for explicitly approved weapons",
		author = "BAR PVE",
		layer = 2,
		enabled = true,
	}
end

-- 模式关闭或当前不是同步游戏逻辑时，不加载弹丸生成回调。
local option = Spring.GetModOptions().roguelike_mode
if option ~= true and option ~= 1 and option ~= "1" and option ~= "true" then return false end
if not gadgetHandler:IsSyncedCode() then return false end

-- 配置决定可用武器、散射角度和每帧最多生成多少额外弹丸。
local config = VFS.Include("unitbasedefs/roguelike_multishot.lua")
-- watched：允许触发的 WeaponDef；spawned：本 Gadget 创建的子弹丸；
-- processed：已处理的原弹丸，避免重复触发。
local watched = {}
local spawned = {}
local processed = {}
local spawning = false
-- 每个游戏帧单独统计生成数量，防止一次齐射生成过多弹丸。
local budgetFrame, extraThisFrame = -1, 0
local pi = math.pi
local sin, cos, sqrt = math.sin, math.cos, math.sqrt

local function ownerWeapon(ownerID, weaponDefID)
	-- 只接受三组肉鸽指挥官中列入白名单的武器。
	local unitDefID = Spring.GetUnitDefID(ownerID)
	local unitDef = unitDefID and UnitDefs[unitDefID]
	if not unitDef then return end
	local commanderName
	for _, name in ipairs({ "armcom", "corcom", "legcom" }) do
		if UnitDefNames[name] and unitDefID == UnitDefNames[name].id then
			commanderName = name
			break
		end
	end
	if not commanderName then return end
	local teamID = Spring.GetUnitTeam(ownerID)
	local state = GG.Roguelike and GG.Roguelike.teams and GG.Roguelike.teams[teamID]
	if not state or state.commanderUnitID ~= ownerID then return end
	local entry = watched[weaponDefID]
	if not entry then return end
	-- 找到该武器在单位上的槽位，并确认它当前具有可用射程。
	for weaponNum, weapon in ipairs(unitDef.weapons) do
		if weapon.weaponDef == weaponDefID then
			local range = Spring.GetUnitWeaponState(ownerID, weaponNum, "range")
			if range and range > 0 then return entry, weaponNum, teamID end
		end
	end
end

function gadget:Initialize()
	-- 遍历三组肉鸽指挥官的武器槽，登记匹配的白名单商店武器。
	for commanderName, entries in pairs(config) do
		local commander = UnitDefNames[commanderName]
		local unitDef = commander and UnitDefs[commander.id]
		if unitDef then
			for _, weapon in ipairs(unitDef.weapons) do
				local def = WeaponDefs[weapon.weaponDef]
				local item = def and def.customParams and def.customParams.roguelike_shop_item
				local entry = item and entries[item]
				-- 阵营自定义伤害、连射弹幕和非弹丸攻击不允许复制。
				if entry and def.type == entry.type and not def.customParams.roguelike_custom_weapon
					and (def.projectiles or 1) == 1 and (def.salvoSize or 1) == 1 then
					watched[weapon.weaponDef] = entry
					Script.SetWatchWeapon(weapon.weaponDef, true)
				end
			end
		end
	end
end

function gadget:ProjectileCreated(projectileID, ownerID, weaponDefID)
	-- SpawnProjectile 可能同步触发此回调；识别子弹丸以阻止递归复制。
	-- 正在创建子弹丸时，先登记其 ID 并结束本次回调。
	if spawning then spawned[projectileID] = true; return end
	-- 已由内部 SpawnProjectile 创建的弹丸只清除临时标记，不再次参与齐射。
	if spawned[projectileID] then spawned[projectileID] = nil; return end
	-- 跳过已处理弹丸和无发射单位的弹丸。
	if processed[projectileID] or not ownerID then return end
	-- 校验发射者、武器和当前单位槽位，取得配置及队伍信息。
	local entry, weaponNum, teamID = ownerWeapon(ownerID, weaponDefID)
	-- 未列入允许清单或不符合 ARM 指挥官条件时不复制。
	if not entry then return end
	-- 先标记原弹丸，避免同一弹丸重复进入处理逻辑。
	processed[projectileID] = true
	-- 升级值表示齐射总弹数；至少三发才需要创建额外弹丸。
	local count = tonumber(Spring.GetUnitRulesParam(ownerID, "roguelike_multishot_count")) or 1
	-- 参数缺失时按单发处理；小于三发无需额外生成弹丸。
	if count < 3 then return end
	-- 限制数量并修正为奇数，让原弹丸处在扇形正中。
	count = math.min(config.maxProjectiles, math.floor(count))
	-- 若上限或升级值为偶数，减一以保持中心弹丸对准原始方向。
	if count % 2 == 0 then count = count - 1 end
	-- 读取原始弹丸出生位置、速度以及武器槽的瞄准向量。
	local x, y, z = Spring.GetProjectilePosition(projectileID)
	local vx, vy, vz = Spring.GetProjectileVelocity(projectileID)
	local _, _, _, aimX, _, aimZ = Spring.GetUnitWeaponVectors(ownerID, weaponNum)
	if not x or not vx or not vz then return end
	-- 使用原弹丸的水平速度；速度太小时无法可靠计算扇形方向。
	local horizontal = sqrt(vx * vx + vz * vz)
	-- 水平速度接近零时无法计算旋转方向，停止复制。
	if horizontal < 0.001 then return end
	-- 计算水平瞄准向量长度；没有有效向量时沿用弹丸原来的水平速度方向。
	local aimLength = aimX and aimZ and sqrt(aimX * aimX + aimZ * aimZ) or 0
	if aimLength > 0.001 then
		-- 优先对齐武器当前的水平瞄准方向，再向两侧展开。
		vx, vz = horizontal * aimX / aimLength, horizontal * aimZ / aimLength
	end
	-- 原弹丸提供实际枪口位置和弹道速度；保留垂直速度，仅旋转水平分量。
	local frame = Spring.GetGameFrame()
	-- 进入新帧后重置额外弹丸计数，保证每帧生成量受配置限制。
	if budgetFrame ~= frame then budgetFrame, extraThisFrame = frame, 0 end
	-- 以原弹丸为中心，offset 从负半数递增到正半数。
	local half = (count - 1) / 2
	-- 估算子弹丸存活帧数；受重力影响的武器沿用游戏重力。
	local ttl = math.max(30, math.ceil((WeaponDefs[weaponDefID].range or 650) / horizontal) + 30)
	local gravity = -Game.gravity / (Game.gameSpeed * Game.gameSpeed)
	-- 遍历齐射中的每个方向；中心方向由原弹丸承担。
	for offset = -half, half do
		-- offset=0 对应原弹丸；其余位置在每帧预算内各生成一枚。
		if offset ~= 0 and extraThisFrame < config.maxExtraPerFrame then
			-- 将偏移角换算成弧度，供 sin/cos 旋转速度向量使用。
			local angle = offset * entry.angleDegrees * pi / 180
			-- 子弹丸从相同枪口位置发射，使用旋转后的水平速度并保留垂直速度。
			local params = {
				pos = { x, y, z },
				speed = { vx * cos(angle) - vz * sin(angle), vy,
					vx * sin(angle) + vz * cos(angle) },
				owner = ownerID, team = teamID, ttl = ttl,
			}
			-- 仅对原定义启用重力的武器传入重力参数。
			if WeaponDefs[weaponDefID].gravityAffected then params.gravity = gravity end
			-- SpawnProjectile 可能立即回调 ProjectileCreated，用 spawning 标记阻止再分裂。
			spawning = true
			local childID = Spring.SpawnProjectile(weaponDefID, params)
			-- 离开创建保护区后，若引擎返回有效 ID，则登记该弹丸并消耗本帧额度。
			spawning = false
			if childID then
				spawned[childID] = true
				extraThisFrame = extraThisFrame + 1
			end
		end
	end
end

function gadget:ProjectileDestroyed(projectileID)
	-- 弹丸销毁后释放去重记录，避免状态表持续增长。
	spawned[projectileID] = nil
	processed[projectileID] = nil
end
