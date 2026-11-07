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

static func for_island(island_id: int) -> String:
	return TYPES[posmod(island_id, TYPES.size())]

static func label(kind: String) -> String:
	return str(NAMES.get(kind, kind))

static func cooldown(kind: String, rank: int = 1) -> float:
	return maxf(2.0, float(COOLDOWNS.get(kind, 6.0)) * (1.0 - 0.07 * float(rank - 1)))

static func tint(kind: String) -> Color:
	return TINTS.get(kind, Color.WHITE)
