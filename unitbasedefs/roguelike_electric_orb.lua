-- ARM 肉鸽商店电球的武器定义。直接命中和伤害由引擎处理；
-- Weapon Effects Gadget 可在命中事件上追加配置的连锁效果。
return {
	-- 显示名称；武器类型使用 Cannon 弹体。
	name = "Electric Orb",
	weapontype = "Cannon",
	-- 最大射程、装填间隔（秒）和弹体初始速度。
	range = 560,
	reloadtime = 1.2,
	weaponvelocity = 500,
	-- 关闭重力影响，让电球沿初始方向平直飞行。
	gravityaffected = "true",
	-- 弹体大小与绘制层数；使用 plasmaball 纹理形成球体外观。
	size = 27,
	stages = 1,
	noexplode = false,
	textures = { [1] = "plasmaball" },
	-- 设置弹体的蓝色调与亮度。
	rgbcolor = "0.3 0.7 1",
	intensity = 0.8,
	-- 命中爆炸范围；impactonly 让范围效果只在命中时触发。
	areaofeffect = 16,
	impactonly = true,
	-- 避开友军、关闭与友军碰撞，并防止对发射者自身造成伤害。
	avoidfriendly = true,
	collidefriendly = false,
	noselfdamage = true,
	-- 允许炮塔转向瞄准；cegtag 指定飞行拖尾的自定义效果。
	turret = true,
	cegtag = "roguelike-electric-orb-trail",
	-- 命中时播放小型闪电爆炸效果及对应发射/命中音效。
	explosiongenerator = "custom:genericshellexplosion-small-lightning",
	soundstart = "lghthvy1",
	soundhit = "xplomed2",
	-- 对普通目标、空中单位和潜艇使用相同的基础伤害。
	damage = { default = 280, vtol = 280, subs = 280 },
	customparams = {
		-- 商店商品 ID 和详细信息界面中的武器分组编号。
		roguelike_shop_item = "electric_orb",
		weapons_group = 9,
	},
}
