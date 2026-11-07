class_name FruitCatalog
extends RefCounted

# Four island rewards per school; repeated finds upgrade mastery rather
# than creating canonically impossible copies of the same Devil Fruit.
const TYPES := ["rubber", "fire", "ice", "lightning", "sand", "smoke",
	"flower", "string", "light", "gravity", "magma", "quake", "barrier", "poison"]
const NAMES := {
	"rubber": "Gomu • Резина", "fire": "Mera • Огонь",
	"ice": "Hie • Лёд", "lightning": "Goro • Молния",
	"sand": "Suna • Песок", "smoke": "Moku • Дым",
	"flower": "Hana • Цветение", "string": "Ito • Нити",
	"light": "Pika • Свет", "gravity": "Zushi • Гравитация",
	"magma": "Magu • Магма", "quake": "Gura • Землетрясение",
	"barrier": "Bari • Барьер", "poison": "Doku • Яд"
}
const COOLDOWNS := {
	"rubber": 4.0, "fire": 5.0, "ice": 5.5, "lightning": 6.0,
	"sand": 4.2, "smoke": 7.0, "flower": 6.0, "string": 5.2,
	"light": 6.5, "gravity": 8.0, "magma": 7.5, "quake": 8.0,
	"barrier": 10.0, "poison": 6.5
}
const TINTS := {
	"rubber": Color(1.0, 0.72, 0.39), "fire": Color(1.0, 0.27, 0.06),
	"ice": Color(0.45, 0.93, 1.0), "lightning": Color(1.0, 0.94, 0.24),
	"sand": Color(0.87, 0.70, 0.38), "smoke": Color(0.68, 0.70, 0.80),
	"flower": Color(1.0, 0.38, 0.76), "string": Color(0.97, 0.90, 0.92),
	"light": Color(1.0, 1.0, 0.62), "gravity": Color(0.57, 0.26, 1.0),
	"magma": Color(1.0, 0.23, 0.03), "quake": Color(0.36, 0.96, 0.86),
	"barrier": Color(0.35, 1.0, 0.55), "poison": Color(0.57, 1.0, 0.22)
}

# A selected fruit changes normal LMB attacks as well as providing a Q skill.
# Damage, crowd control and trajectories are all resolved by the LAN server.
const SHOT_INFUSIONS := {
	"rubber": {"speed": 1.18, "push": 4.5, "spread": 0.16, "rate": 0.88},
	"fire": {"damage": 1, "splash": 3.0, "status": "burn", "duration": 3.0},
	"ice": {"radius": 1.18, "status": "freeze", "duration": 1.8},
	"lightning": {"speed": 1.65, "pierce": 1, "chain": true},
	"sand": {"spread": 0.25, "status": "slow", "duration": 2.3},
	"smoke": {"radius": 1.25, "splash": 3.5, "status": "slow", "duration": 2.0},
	"flower": {"pierce": 1, "status": "root", "duration": 1.2},
	"string": {"pierce": 2, "status": "root", "duration": 1.7},
	"light": {"speed": 1.9, "pierce": 2, "radius": 0.78},
	"gravity": {"speed": 0.85, "splash": 4.2, "status": "slow", "duration": 2.2, "push": -4.0},
	"magma": {"damage": 2, "speed": 0.75, "splash": 4.8, "status": "burn", "duration": 4.0, "rate": 1.16},
	"quake": {"splash": 4.0, "push": 6.0},
	"barrier": {"radius": 1.2, "push": 3.0, "shield": 0.85},
	"poison": {"splash": 3.0, "status": "poison", "duration": 5.0}
}

static func shot_style(kind: String, rank: int = 1) -> Dictionary:
	if not SHOT_INFUSIONS.has(kind):
		return {}
	var style: Dictionary = SHOT_INFUSIONS[kind].duplicate()
	if rank >= 2 and style.has("duration"):
		style["duration"] = float(style["duration"]) * 1.25
	if rank >= 3:
		style["damage"] = int(style.get("damage", 0)) + 1
	if rank >= 4:
		style["pierce"] = int(style.get("pierce", 0)) + 1
		if style.has("splash"):
			style["splash"] = float(style["splash"]) * 1.25
		if style.has("shield"):
			style["shield"] = float(style["shield"]) + 0.5
	return style

static func for_island(island_id: int) -> String:
	return TYPES[posmod(island_id, TYPES.size())]

static func label(kind: String) -> String:
	return str(NAMES.get(kind, kind))

static func cooldown(kind: String, rank: int = 1) -> float:
	return maxf(2.0, float(COOLDOWNS.get(kind, 6.0)) * (1.0 - 0.07 * float(rank - 1)))

static func tint(kind: String) -> Color:
	return TINTS.get(kind, Color.WHITE)
