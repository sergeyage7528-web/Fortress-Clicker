class_name HeroDatabase
extends RefCounted

const HERO_IDS: Array[String] = ["knight", "archer", "berserker", "mage"]
const HEROES: Dictionary = {
	"knight": {"name":"Рыцарь", "cost":350, "hp":260, "damage":18, "cooldown":0.68, "crit":0.08, "crit_mult":1.7, "color":Color("#bcc8d5"), "attack":"slash", "desc":"Стойкий защитник"},
	"archer": {"name":"Лучница", "cost":650, "hp":170, "damage":27, "cooldown":0.58, "crit":0.14, "crit_mult":1.6, "color":Color("#9bd06b"), "attack":"arrow", "desc":"Быстрые стрелы"},
	"berserker": {"name":"Берсерк", "cost":1100, "hp":370, "damage":42, "cooldown":0.82, "crit":0.12, "crit_mult":2.0, "color":Color("#d46b55"), "attack":"axe", "desc":"Сокрушительные удары"},
	"mage": {"name":"Маг", "cost":1800, "hp":210, "damage":58, "cooldown":0.75, "crit":0.18, "crit_mult":1.8, "color":Color("#a878e0"), "attack":"magic", "desc":"Тёмная магия"}
}

static func has_hero(hero_id: String) -> bool:
	return HEROES.has(hero_id)

static func get_hero(hero_id: String) -> Dictionary:
	if not has_hero(hero_id): return {}
	return (HEROES[hero_id] as Dictionary).duplicate(true)

static func get_all_heroes() -> Dictionary:
	return HEROES.duplicate(true)

static func get_hero_ids() -> Array[String]:
	return HERO_IDS.duplicate()
