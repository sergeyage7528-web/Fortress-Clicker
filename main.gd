extends Node2D

const W := 540.0
const H := 960.0
const AUTOSAVE_INTERVAL := 20.0
const SAVE_VERSION: int = 4
const MAX_STANDARD_UPGRADE_LEVEL: int = 10000
const MAX_HERO_UPGRADE_LEVEL: int = 10000
const MAX_PRESTIGE_UPGRADE_LEVEL: int = 1000
const MAX_STAGE: int = 1000
const MAX_GOLD: int = 9000000000000000000
const MAX_COST_EXPONENT: int = 100
const STAGE_VICTORY_DELAY := 1.8
const WAVE_DELAY := 1.2
const HERO_ATTACK_DURATION := 0.22
const MAX_WAVES_PER_STAGE := 10
const BASE_ENEMY_HP := 120.0
const BASE_GOLD_REWARD := 20.0
const PRESTIGE_UNLOCK_STAGE: int = 10
const PRESTIGE_DAMAGE_MAX_LEVEL: int = 20
const PRESTIGE_GOLD_MAX_LEVEL: int = 20
const PRESTIGE_START_GOLD_MAX_LEVEL: int = 10
const STARTING_GOLD_VALUES: Array[int] = [0, 50, 150, 300, 500, 800, 1200, 1800, 2600, 3600, 5000]
const BATTLEFIELD_RECT := Rect2(0, 128, W, 576)
const NORMAL_MESSAGE_COLOR := Color("#d9c7a1")
const UI_PANEL_COLOR := Color("#2c3747")
const UI_CONTENT_COLOR := Color("#405064")
const UI_STONE_COLOR := Color("#5b6470")
const UI_BRONZE_COLOR := Color("#6c5944")
const UI_GOLD_COLOR := Color("#f2cd78")
const UI_TEXT_COLOR := Color("#f3ead8")
const UI_MUTED_TEXT_COLOR := Color("#c1b7a2")
var stage := 1
var wave := 1
var highest_stage_this_run: int = 1
var highest_stage_ever: int = 1
var heart_shards: int = 0
var prestige_unlocked := false
var prestige_damage_level: int = 0
var prestige_gold_level: int = 0
var prestige_start_gold_level: int = 0
var prestige_in_progress := false
var enemies_killed: int = 0
var current_enemy_type := ""
var current_enemy_max_hp := 0.0
var current_enemy_reward: int = 0
var enemy_is_dying := false
var gold := 0
var tower_level := 1
var tower_crit_level := 0
var tower_crit_mult_level := 0
var fortress_level := 1
var fortress_armor_level := 0
var barracks_open := false
var barracks_level := 0
var garrison_damage_level := 0
var garrison_health_level := 0
var garrison_crit_level := 0
var garrison_speed_level := 0
var owned: Array[String] = []
var selected := ""
var active_hero := ""
var hero_upgrades: Dictionary = {}
var fortress_hp := 1000.0
var hero_hp := 0.0
var hero_alive := false
var garrison_units: Array[Dictionary] = []
var enemies: Array[Dictionary] = []
var wave_max_health := 0.0
var wave_current_health := 0.0
var battle_generation: int = 0
var projectiles: Array[Dictionary] = []
var effects: Array[Dictionary] = []
var state := "ready_stage" # ready_stage, battle, between, stage_victory, defeat
var spawn_timer := 0.0
var stage_victory_timer := 0.0
var stage_completion_processed := false
var hero_attack_timer := 0.0
var hero_auto_timer := 0.0
var garrison_auto_timer := 0.0
var rng := RandomNumberGenerator.new()
var active_tab := "castle"
var tab_buttons: Dictionary = {}
var ui: CanvasLayer
var info_label: Label
var gold_label: Label
var stage_label: Label
var message_label: Label
var enemy_label: Label
var tab_content: Panel
var upgrade_scroll: ScrollContainer
var upgrade_list: VBoxContainer
var start_stage_button: Button
var retry_button: Button
var test_console_open := false
var test_overlay: Control
var test_status: Label
var test_notice: Label
var prestige_overlay: Control
var prestige_summary: Label
var prestige_confirm_button: Button
var save_dirty: bool = false
var autosave_timer: float = 0.0

func _ready() -> void:
	rng.randomize()
	load_progress()
	build_ui()
	reset_stage_combat(false)
	queue_redraw()

func max_fortress() -> float: return 750.0 + fortress_level * 250.0
func fortress_armor() -> float: return fortress_armor_level * 3.0
func prestige_damage_multiplier() -> float: return 1.0 + prestige_damage_level * 0.10
func prestige_gold_multiplier() -> float: return 1.0 + prestige_gold_level * 0.10
func prestige_starting_gold() -> int: return STARTING_GOLD_VALUES[prestige_start_gold_index()]
func prestige_start_gold_index() -> int: return clampi(prestige_start_gold_level, 0, PRESTIGE_START_GOLD_MAX_LEVEL)
func tower_damage() -> float: return (24.0 + tower_level * 12.0) * prestige_damage_multiplier()
func tower_crit_chance() -> float: return minf(1.0, tower_crit_level * 0.04)
func tower_crit_multiplier() -> float: return 1.5 + tower_crit_mult_level * 0.25

func growing_cost(base: int, growth: float, level: int) -> int:
	var safe_level := clampi(level, 0, MAX_COST_EXPONENT)
	return int(minf(float(MAX_GOLD), base * pow(growth, safe_level)))

func capped_gold_value(value: float) -> int:
	if is_nan(value) or is_inf(value): return MAX_GOLD
	return int(clampf(round(value), 0.0, float(MAX_GOLD)))

func castle_cost(kind: String) -> int:
	var level := tower_level if kind == "tower" else tower_crit_level if kind == "tower_crit" else tower_crit_mult_level if kind == "tower_mult" else fortress_level if kind == "fortress" else fortress_armor_level
	var base := 90 if kind == "tower" else 120 if kind == "tower_crit" else 140 if kind == "tower_mult" else 110 if kind == "fortress" else 130
	return growing_cost(base, 1.52, level)

func barracks_cost(kind: String) -> int:
	var level := barracks_level if kind == "level" else garrison_damage_level if kind == "damage" else garrison_health_level if kind == "health" else garrison_crit_level if kind == "crit" else garrison_speed_level
	var base := 170 if kind == "level" else 110 if kind == "damage" else 100 if kind == "health" else 130 if kind == "crit" else 120
	return growing_cost(base, 1.5, level)

func hero_upgrade_data(id: String) -> Dictionary:
	if not hero_upgrades.has(id): hero_upgrades[id] = {"damage":0, "health":0, "crit":0, "mult":0, "speed":0}
	return hero_upgrades[id]

func hero_stats(id: String) -> Dictionary:
	if id.is_empty() or not HeroDatabase.has_hero(id): return {}
	var base: Dictionary = HeroDatabase.get_hero(id)
	var up := hero_upgrade_data(id)
	return {"name":base.name, "hp":base.hp + up.health * 35, "damage":(base.damage + up.damage * 7) * prestige_damage_multiplier(), "crit":minf(1.0, base.crit + up.crit * 0.03), "mult":base.crit_mult + up.mult * 0.2, "cooldown":maxf(0.22, base.cooldown - up.speed * 0.05), "color":base.color, "attack":base.attack, "desc":base.desc}

func hero_upgrade_cost(id: String, kind: String) -> int:
	var up := hero_upgrade_data(id)
	var base := 100 if kind == "damage" else 90 if kind == "health" else 120 if kind == "crit" else 135 if kind == "mult" else 115
	return growing_cost(base, 1.55, int(up[kind]))

func reset_stage_combat(restart: bool) -> void:
	if restart: wave = 1
	enemies_killed = 0
	current_enemy_type = ""
	current_enemy_max_hp = 0.0
	current_enemy_reward = 0
	enemy_is_dying = false
	fortress_hp = max_fortress()
	active_hero = selected if owned.has(selected) else ""
	hero_alive = not active_hero.is_empty()
	hero_hp = hero_stats(active_hero).hp if hero_alive else 0.0
	garrison_units = create_garrison_units()
	enemies.clear(); projectiles.clear(); effects.clear()
	wave_max_health = 0.0; wave_current_health = 0.0
	hero_attack_timer = 0.0; hero_auto_timer = 0.0; garrison_auto_timer = 0.0; stage_victory_timer = 0.0
	state = "ready_stage"
	stage_completion_processed = false
	message_label.modulate = NORMAL_MESSAGE_COLOR
	message_label.text = "Стадия %d готова. Нажмите «Начать стадию»" % stage
	if tab_content != null: refresh_tab()

func create_garrison_units() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not barracks_open: return result
	var hp := garrison_max_health()
	result.append({"kind":"guard", "hp":hp, "max_hp":hp, "x":252.0, "y":595.0, "alive":true})
	var archers: int = mini(2, maxi(0, barracks_level - 1))
	var knights: int = maxi(0, barracks_level - 3)
	for i in archers: result.append({"kind":"archer", "hp":hp * .8, "max_hp":hp * .8, "x":180.0 + i * 24.0, "y":402.0, "alive":true})
	for i in knights: result.append({"kind":"knight", "hp":hp * 1.35, "max_hp":hp * 1.35, "x":220.0 - i * 27.0, "y":620.0, "alive":true})
	return result

func desired_archers() -> int: return mini(2, maxi(0, barracks_level - 1))
func desired_knights() -> int: return maxi(0, barracks_level - 3)

func garrison_unit_count(kind: String) -> int:
	var count := 0
	for unit in garrison_units:
		if unit.kind == kind: count += 1
	return count

func add_garrison_unit(kind: String, index: int) -> void:
	var hp := garrison_max_health()
	if kind == "guard": garrison_units.append({"kind":"guard", "hp":hp, "max_hp":hp, "x":252.0, "y":595.0, "alive":true})
	elif kind == "archer": garrison_units.append({"kind":"archer", "hp":hp * .8, "max_hp":hp * .8, "x":180.0 + index * 24.0, "y":402.0, "alive":true})
	else: garrison_units.append({"kind":"knight", "hp":hp * 1.35, "max_hp":hp * 1.35, "x":220.0 - index * 27.0, "y":620.0, "alive":true})

func add_garrison_reinforcements() -> void:
	if not barracks_open: return
	if garrison_unit_count("guard") == 0: add_garrison_unit("guard", 0)
	while garrison_unit_count("archer") < desired_archers(): add_garrison_unit("archer", garrison_unit_count("archer"))
	while garrison_unit_count("knight") < desired_knights(): add_garrison_unit("knight", garrison_unit_count("knight"))

func garrison_damage() -> float: return (10.0 + barracks_level * 3.0 + garrison_damage_level * 6.0) * prestige_damage_multiplier()
func garrison_max_health() -> float: return 105.0 + barracks_level * 22.0 + garrison_health_level * 28.0
func garrison_crit_chance() -> float: return minf(1.0, 0.04 + garrison_crit_level * 0.03)
func garrison_cooldown() -> float: return maxf(0.25, 0.8 - garrison_speed_level * 0.06)
func garrison_next_unit() -> String:
	if not barracks_open: return "стражник"
	if barracks_level < 2: return "лучник"
	if barracks_level < 4: return "рыцарь"
	return "ещё один рыцарь"

func start_stage() -> void:
	if state != "ready_stage": return
	state = "battle"
	start_stage_button.visible = false
	spawn_enemy()

func restart_stage() -> void:
	reset_stage_combat(true)
	start_stage()

func enemy_type_for_wave() -> String:
	if wave >= MAX_WAVES_PER_STAGE: return "boss"
	if wave == 5: return "elite"
	return "normal"

func calculate_enemy_stats() -> Dictionary:
	var enemy_type := enemy_type_for_wave()
	var hp_multiplier := 5.0 if enemy_type == "boss" else 2.0 if enemy_type == "elite" else 1.0
	var reward_multiplier := 4.0 if enemy_type == "boss" else 2.0 if enemy_type == "elite" else 1.0
	var stage_hp_scale := pow(1.18, stage - 1)
	var wave_hp_scale := 1.0 + float(wave - 1) * 0.08
	var hp := BASE_ENEMY_HP * stage_hp_scale * wave_hp_scale * hp_multiplier
	var reward := capped_gold_value(BASE_GOLD_REWARD * pow(1.12, stage - 1) * reward_multiplier * prestige_gold_multiplier())
	var damage_multiplier := 2.2 if enemy_type == "boss" else 1.45 if enemy_type == "elite" else 1.0
	var display_name := "Вожак стаи" if enemy_type == "boss" else "Закалённый мародёр" if enemy_type == "elite" else "Лесной слизень"
	return {"type":enemy_type, "name":display_name, "hp":hp, "reward":reward, "damage":(11.0 + stage * 4.0) * damage_multiplier}

func enemy_count_for_wave() -> int:
	if wave >= MAX_WAVES_PER_STAGE: return 1
	return clampi(1 + floori((stage - 1) / 2.0), 1, 4)

func enemy_spawn_position(index: int, enemy_count: int) -> Vector2:
	var x: float = 430.0
	if enemy_count == 2: x = 390.0 if index == 0 else 470.0
	elif enemy_count == 3: x = 350.0 if index == 0 else 420.0 if index == 1 else 490.0
	elif enemy_count >= 4: x = 325.0 if index == 0 else 380.0 if index == 1 else 435.0 if index == 2 else 490.0
	return Vector2(x, 535.0 + (index % 2) * 35.0)

func spawn_enemy() -> void:
	enemies.clear()
	battle_generation += 1
	var stats := calculate_enemy_stats()
	current_enemy_type = stats.type
	current_enemy_max_hp = stats.hp
	current_enemy_reward = stats.reward
	enemy_is_dying = false
	var count := enemy_count_for_wave()
	for i in count:
		var position := enemy_spawn_position(i, count)
		enemies.append({"hp":stats.hp, "max_hp":stats.hp, "damage":stats.damage, "gold":stats.reward, "x":position.x, "y":position.y, "boss":current_enemy_type == "boss", "attack_cd":1.7 + i * 0.22, "flash":0.0, "type":current_enemy_type, "name":stats.name, "death_processed":false})
	update_wave_health(true)
	message_label.text = "БОСС У ВОРОТ!" if current_enemy_type == "boss" else "Волна %d начинается" % wave
	message_label.modulate = Color("#ffbc68") if current_enemy_type == "boss" else NORMAL_MESSAGE_COLOR
	update_enemy_ui()

func advance_wave() -> void:
	if state == "defeat": return
	if wave >= MAX_WAVES_PER_STAGE:
		finish_stage()
		return
	wave += 1
	state = "between"
	spawn_timer = WAVE_DELAY
	message_label.modulate = NORMAL_MESSAGE_COLOR
	message_label.text = "Волна %d очищена! Следующий враг приближается…" % (wave - 1)
	update_enemy_ui()

func advance_stage() -> void:
	stage = mini(MAX_STAGE, stage + 1)
	wave = 1
	highest_stage_this_run = maxi(highest_stage_this_run, stage)
	highest_stage_ever = maxi(highest_stage_ever, stage)
	if stage >= PRESTIGE_UNLOCK_STAGE: prestige_unlocked = true
	mark_save_dirty()
	reset_stage_combat(false)
	start_stage()

func update_enemy_ui() -> void:
	if enemy_label == null: return
	if enemies.is_empty():
		enemy_label.text = ""
		return
	var enemy: Dictionary = enemies[0]
	var prefix := "БОСС" if enemy.boss else "УСИЛЕННЫЙ ВРАГ" if enemy.type == "elite" else "ВРАГ"
	enemy_label.text = "%s: %s  •  Волна %d — %d / %d HP" % [prefix, enemy.name, wave, wave_current_health, wave_max_health]
	enemy_label.modulate = Color("#ffbe70") if enemy.boss else Color("#e6d7bd")

func update_wave_health(reset_maximum := false) -> void:
	if reset_maximum: wave_max_health = 0.0
	wave_current_health = 0.0
	for enemy in enemies:
		if reset_maximum: wave_max_health += maxf(0.0, enemy.max_hp)
		wave_current_health += maxf(0.0, enemy.hp)

func _process(delta: float) -> void:
	autosave_timer += delta
	if save_dirty and autosave_timer >= AUTOSAVE_INTERVAL: save_progress()
	if test_console_open:
		update_hud(); queue_redraw(); return
	hero_attack_timer = maxf(0.0, hero_attack_timer - delta)
	for p in projectiles:
		p.t += delta * 7.0
		if p.t >= 1.0 and not p.hit: p.hit = true
	for fx in effects: fx.life -= delta
	effects = effects.filter(func(f): return f.life > 0)
	for e in enemies: e.flash = maxf(0.0, e.flash - delta)
	if state == "battle":
		hero_auto_timer += delta; garrison_auto_timer += delta
		if hero_alive and hero_auto_timer >= hero_stats(active_hero).cooldown:
			hero_auto_timer = 0.0; hero_attack()
		if not garrison_units.is_empty() and garrison_auto_timer >= garrison_cooldown():
			garrison_auto_timer = 0.0; garrison_attack()
		monster_attacks(delta)
	elif state == "between":
		spawn_timer -= delta
		if spawn_timer <= 0.0:
			state = "battle"
			spawn_enemy()
	elif state == "stage_victory":
		stage_victory_timer -= delta
		if stage_victory_timer <= 0.0:
			begin_prepared_stage()
	if state == "battle":
		for p in projectiles:
			if p.hit and not p.resolved:
				p.resolved = true
				if projectile_matches_current_generation(p): apply_damage_to_wave(p.damage, p.kind, p.crit)
	projectiles = projectiles.filter(func(p): return p.t < 1.08)
	update_hud(); queue_redraw()

func roll_damage(base: float, chance: float, multiplier: float) -> Dictionary:
	var crit := rng.randf() < chance
	return {"damage":base * (multiplier if crit else 1.0), "crit":crit}

func tower_shot(target: Dictionary) -> void:
	if state != "battle" or not enemies.has(target): return
	var hit := roll_damage(tower_damage(), tower_crit_chance(), tower_crit_multiplier())
	fire_attack(Vector2(122, 415), Vector2(target.x, target.y), hit.damage, "tower", target, hit.crit)

func hero_attack() -> void:
	if enemies.is_empty() or not hero_alive: return
	var stats := hero_stats(active_hero)
	var target := enemies[0]
	var hit := roll_damage(stats.damage, stats.crit, stats.mult)
	hero_attack_timer = HERO_ATTACK_DURATION
	fire_attack(Vector2(190, 580), Vector2(target.x, target.y), hit.damage, stats.attack, target, hit.crit)

func garrison_attack() -> void:
	if enemies.is_empty(): return
	var target := enemies[0]
	for unit in garrison_units:
		if not unit.alive: continue
		var modifier := 1.25 if unit.kind == "knight" else .85 if unit.kind == "archer" else 1.0
		var hit := roll_damage(garrison_damage() * modifier, garrison_crit_chance(), 1.6)
		var attack := "arrow" if unit.kind == "archer" else "axe" if unit.kind == "knight" else "slash"
		fire_attack(Vector2(unit.x, unit.y - 10), Vector2(target.x, target.y), hit.damage, attack, target, hit.crit)

func monster_attacks(delta: float) -> void:
	for enemy in enemies.duplicate():
		if state != "battle": return
		enemy.attack_cd -= delta
		if enemy.attack_cd > 0.0: continue
		enemy.attack_cd = 1.6
		if hero_alive:
			hero_hp -= enemy.damage; add_effect(Vector2(190, 575), "-%d" % enemy.damage, Color("#ff6e5e"))
			if hero_hp <= 0.0: hero_alive = false; add_effect(Vector2(190, 550), "ГЕРОЙ ПАЛ", Color("#ff7a63"))
		else:
			var target_unit := first_garrison_target()
			if not target_unit.is_empty():
				target_unit.hp -= enemy.damage; add_effect(Vector2(target_unit.x, target_unit.y - 25), "-%d" % enemy.damage, Color("#ff6e5e"))
				if target_unit.hp <= 0.0: target_unit.alive = false; add_effect(Vector2(target_unit.x, target_unit.y - 45), "ВОИН ПАЛ", Color("#ff7a63"))
			else:
				var damage := maxf(1.0, enemy.damage - fortress_armor())
				fortress_hp -= damage; add_effect(Vector2(110, 480), "-%d" % damage, Color("#ff6257"))
				if fortress_hp <= 0.0: defeat()

func first_garrison_target() -> Dictionary:
	for wanted in ["knight", "guard", "archer"]:
		for unit in garrison_units:
			if unit.alive and unit.kind == wanted: return unit
	return {}

func fire_attack(from: Vector2, to: Vector2, damage: float, kind: String, target: Dictionary, crit: bool) -> void:
	projectiles.append({"from":from, "to":to, "damage":damage, "kind":kind, "target":target, "crit":crit, "generation":battle_generation, "t":0.0, "hit":false, "resolved":false})

func projectile_matches_current_generation(projectile: Dictionary) -> bool:
	return int(projectile.get("generation", -1)) == battle_generation

func apply_damage_to_wave(damage: float, kind: String, crit: bool) -> void:
	if state != "battle" or enemy_is_dying or enemies.is_empty() or damage <= 0.0: return
	var first_enemy: Dictionary = enemies[0]
	var damage_color := Color("#ff8b56") if crit else Color("#ffe5a2")
	var damage_text := "КРИТ! -%d" % damage if crit else "-%d" % damage
	add_effect(Vector2(first_enemy.x, first_enemy.y - 38), damage_text, damage_color)
	if kind == "magic": add_effect(Vector2(first_enemy.x, first_enemy.y), "✦", Color("#c799ff"))
	var remaining_damage := damage
	while remaining_damage > 0.0 and not enemies.is_empty():
		var enemy: Dictionary = enemies[0]
		var dealt_damage := minf(remaining_damage, maxf(0.0, enemy.hp))
		enemy.hp = maxf(0.0, enemy.hp - dealt_damage)
		remaining_damage -= dealt_damage
		play_hit_animation(enemy)
		if enemy.hp <= 0.0: kill_enemy(enemy)
	update_wave_health()
	update_enemy_ui()

func play_hit_animation(enemy: Dictionary) -> void:
	# A single short flash is reset on each hit and never accumulates on rapid taps.
	enemy.flash = 0.16

func kill_enemy(enemy: Dictionary) -> void:
	if enemy_is_dying or not enemies.has(enemy) or enemy.death_processed: return
	enemy_is_dying = true
	enemy.death_processed = true
	gold += int(enemy.gold)
	enemies_killed += 1
	mark_save_dirty()
	refresh_tab_purchase_states()
	add_effect(Vector2(enemy.x, enemy.y - 60), "+%d золота" % enemy.gold, Color("#ffd461"))
	enemies.erase(enemy)
	enemy_is_dying = false
	update_wave_health()
	update_enemy_ui()
	if enemies.is_empty(): advance_wave()

func finish_stage() -> void:
	var completed_stage := stage
	var reward := 100 + completed_stage * 60
	if not process_stage_completion(reward): return
	mark_save_dirty()
	save_progress(true)
	message_label.text = "СТАДИЯ %d ПРОЙДЕНА! +%d золота" % [completed_stage, reward]
	message_label.modulate = Color("#80e5a2")
	state = "stage_victory"
	stage_victory_timer = STAGE_VICTORY_DELAY

func process_stage_completion(reward: int) -> bool:
	if stage_completion_processed: return false
	stage_completion_processed = true
	gold = mini(MAX_GOLD, gold + reward)
	stage = mini(MAX_STAGE, stage + 1)
	wave = 1
	highest_stage_this_run = maxi(highest_stage_this_run, stage)
	highest_stage_ever = maxi(highest_stage_ever, stage)
	if stage >= PRESTIGE_UNLOCK_STAGE: prestige_unlocked = true
	return true

func begin_prepared_stage() -> void:
	reset_stage_combat(false)
	start_stage()

func defeat() -> void:
	state = "defeat"; message_label.text = "КРЕПОСТЬ ПАЛА"; message_label.modulate = Color("#ff5d58")

func add_effect(pos: Vector2, text_value: String, color: Color) -> void:
	effects.append({"pos":pos, "text":text_value, "color":color, "life":.85})

func _unhandled_input(event: InputEvent) -> void:
	if test_console_open: return
	if prestige_overlay != null and prestige_overlay.visible:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE: close_prestige_confirmation()
		return
	# Touch is handled first and returned so one Android tap cannot also become a mouse shot.
	if event is InputEventScreenTouch:
		if event.pressed: try_tap(event.position)
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		try_tap(event.position)

func is_inside_battlefield(position: Vector2) -> bool:
	return BATTLEFIELD_RECT.has_point(position)

func try_tap(pos: Vector2) -> void:
	if state != "battle": return
	if not is_inside_battlefield(pos): return
	if not enemies.is_empty(): tower_shot(enemies[0])

func build_ui() -> void:
	ui = CanvasLayer.new(); add_child(ui)
	var root := Control.new(); root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root.mouse_filter = Control.MOUSE_FILTER_PASS; ui.add_child(root)
	stage_label = make_label(Vector2(15, 12), Vector2(510, 54), 18, Color("#f5dfa8")); root.add_child(stage_label)
	info_label = make_label(Vector2(15, 47), Vector2(510, 28), 15, Color("#e6d7bd")); root.add_child(info_label)
	message_label = make_label(Vector2(30, 98), Vector2(480, 30), 18, NORMAL_MESSAGE_COLOR); message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; root.add_child(message_label)
	enemy_label = make_label(Vector2(24, 128), Vector2(492, 26), 14, Color("#e6d7bd")); enemy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; root.add_child(enemy_label)
	gold_label = make_label(Vector2(18, 674), Vector2(500, 26), 18, Color("#ffd561")); root.add_child(gold_label)
	var panel := Panel.new(); panel.position = Vector2(8, 704); panel.size = Vector2(524, 248); panel.add_theme_stylebox_override("panel", make_panel_style(UI_PANEL_COLOR, Color("#718198"), 2)); root.add_child(panel)
	var tabs := [["Замок", "castle"], ["Герой", "hero"], ["Гарнизон", "garrison"], ["Магазин", "shop"], ["Престиж", "prestige"]]
	for i in tabs.size():
		var tab_id: String = tabs[i][1]
		var tab := make_button(tabs[i][0], Vector2(14 + i * 102, 712), func(): set_tab(tab_id)); tab.size = Vector2(98, 34); tab.add_theme_font_size_override("font_size", 11); root.add_child(tab); tab_buttons[tab_id] = tab
	tab_content = Panel.new(); tab_content.position = Vector2(14, 750); tab_content.size = Vector2(512, 120); tab_content.add_theme_stylebox_override("panel", make_panel_style(UI_CONTENT_COLOR, Color("#8b9bad"), 1)); tab_content.mouse_filter = Control.MOUSE_FILTER_STOP; root.add_child(tab_content)
	upgrade_scroll = ScrollContainer.new(); upgrade_scroll.position = Vector2(4, 4); upgrade_scroll.size = Vector2(504, 112); upgrade_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; upgrade_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO; upgrade_scroll.mouse_filter = Control.MOUSE_FILTER_STOP; tab_content.add_child(upgrade_scroll)
	var upgrade_margin := MarginContainer.new(); upgrade_margin.custom_minimum_size = Vector2(496, 0); upgrade_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL; upgrade_margin.add_theme_constant_override("margin_left", 4); upgrade_margin.add_theme_constant_override("margin_right", 4); upgrade_margin.add_theme_constant_override("margin_top", 3); upgrade_margin.add_theme_constant_override("margin_bottom", 3); upgrade_scroll.add_child(upgrade_margin)
	upgrade_list = VBoxContainer.new(); upgrade_list.custom_minimum_size = Vector2(488, 0); upgrade_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; upgrade_list.add_theme_constant_override("separation", 6); upgrade_margin.add_child(upgrade_list)
	start_stage_button = make_button("Начать стадию 1", Vector2(16, 878), start_stage); start_stage_button.size = Vector2(250, 58); root.add_child(start_stage_button)
	retry_button = make_button("Начать заново", Vector2(274, 878), restart_stage); retry_button.size = Vector2(250, 58); retry_button.visible = false; root.add_child(retry_button)
	build_prestige_confirmation(root)
	if OS.is_debug_build(): build_test_console(root)
	update_tab_styles()
	refresh_tab()

func build_test_console(root: Control) -> void:
	var test_button := make_button("TEST", Vector2(468, 8), open_test_console)
	test_button.size = Vector2(62, 32); test_button.add_theme_font_size_override("font_size", 11); root.add_child(test_button)
	test_overlay = Control.new(); test_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); test_overlay.mouse_filter = Control.MOUSE_FILTER_STOP; test_overlay.visible = false; root.add_child(test_overlay)
	var shade := ColorRect.new(); shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); shade.color = Color("#05070ce8"); shade.mouse_filter = Control.MOUSE_FILTER_STOP; test_overlay.add_child(shade)
	var panel := Panel.new(); panel.position = Vector2(14, 42); panel.size = Vector2(512, 876); panel.add_theme_stylebox_override("panel", make_panel_style(Color("#344154"), Color("#a88b55"), 2)); test_overlay.add_child(panel)
	var title := make_label(Vector2(16, 10), Vector2(380, 28), 22, Color("#ffd77d")); title.text = "ТЕСТОВАЯ КОНСОЛЬ"; panel.add_child(title)
	var close := make_button("Закрыть", Vector2(396, 8), close_test_console); close.size = Vector2(100, 34); close.add_theme_font_size_override("font_size", 11); panel.add_child(close)
	test_status = make_label(Vector2(16, 42), Vector2(480, 38), 12, Color("#e6d7bd")); test_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; panel.add_child(test_status)
	test_notice = make_label(Vector2(16, 78), Vector2(480, 24), 13, Color("#80e5a2")); panel.add_child(test_notice)
	var scroll := ScrollContainer.new(); scroll.position = Vector2(12, 108); scroll.size = Vector2(488, 754); panel.add_child(scroll)
	var list := VBoxContainer.new(); list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; list.custom_minimum_size = Vector2(460, 0); scroll.add_child(list)
	add_test_group(list, "ЗОЛОТО И СОХРАНЕНИЕ")
	add_test_button(list, "+100 золота", func(): test_add_gold(100))
	add_test_button(list, "+1 000 золота", func(): test_add_gold(1000))
	add_test_button(list, "+10 000 золота", func(): test_add_gold(10000))
	add_test_button(list, "Сохранить", func(): test_finish("Прогресс сохранён"))
	add_test_button(list, "Сбросить прогресс", test_reset_progress)
	add_test_group(list, "СТАДИИ И ВОЛНЫ")
	add_test_button(list, "Начать стадию", test_start_stage)
	add_test_button(list, "Следующая волна", test_next_wave)
	add_test_button(list, "Волна 10: босс", func(): test_start_specific_wave(10))
	add_test_button(list, "Пропустить волну", test_skip_wave)
	add_test_button(list, "Следующая стадия", test_next_stage)
	add_test_button(list, "Нанести 100 урона крепости", func(): test_damage_fortress(100.0))
	add_test_button(list, "Уничтожить крепость", func(): test_damage_fortress(fortress_hp))
	add_test_group(list, "ГЕРОИ")
	for id in ["knight", "archer", "berserker", "mage"]:
		var hero_id: String = id
		add_test_button(list, "Выдать %s" % HeroDatabase.get_hero(hero_id).name, func(): test_grant_hero(hero_id))
	add_test_button(list, "Убрать героя", test_remove_hero)
	add_test_group(list, "ГАРНИЗОН")
	add_test_button(list, "Открыть казармы", test_open_barracks)
	add_test_button(list, "+1 уровень казарм", func(): test_upgrade_garrison("level"))
	add_test_button(list, "+1 урон гарнизона", func(): test_upgrade_garrison("damage"))
	add_test_button(list, "+1 здоровье гарнизона", func(): test_upgrade_garrison("health"))
	add_test_button(list, "+1 критический шанс гарнизона", func(): test_upgrade_garrison("crit"))
	add_test_button(list, "+1 скорость гарнизона", func(): test_upgrade_garrison("speed"))
	add_test_button(list, "Убрать гарнизон", test_remove_garrison)
	add_test_group(list, "УЛУЧШЕНИЯ ЗАМКА")
	add_test_button(list, "+1 урон башни", func(): test_upgrade_castle("tower"))
	add_test_button(list, "+1 критический шанс башни", func(): test_upgrade_castle("tower_crit"))
	add_test_button(list, "+1 критический множитель башни", func(): test_upgrade_castle("tower_mult"))
	add_test_button(list, "+1 здоровье крепости", func(): test_upgrade_castle("fortress"))
	add_test_button(list, "+1 броня крепости", func(): test_upgrade_castle("armor"))

func add_test_group(list: VBoxContainer, text_value: String) -> void:
	var label := Label.new(); label.text = text_value; label.custom_minimum_size = Vector2(0, 28); label.add_theme_font_size_override("font_size", 14); label.add_theme_color_override("font_color", Color("#ffd77d")); label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM; list.add_child(label)

func add_test_button(list: VBoxContainer, text_value: String, callback: Callable) -> void:
	var button := Button.new(); button.text = text_value; button.custom_minimum_size = Vector2(0, 44); button.add_theme_font_size_override("font_size", 16); apply_regular_button_style(button); button.pressed.connect(callback); list.add_child(button)

func open_test_console() -> void:
	if not OS.is_debug_build() or test_overlay == null: return
	test_console_open = true; test_overlay.visible = true; refresh_test_status(); test_notice.text = ""

func close_test_console() -> void:
	test_console_open = false
	if test_overlay: test_overlay.visible = false

func refresh_test_status() -> void:
	if test_status == null: return
	var hero_name: String = HeroDatabase.get_hero(selected).name if not selected.is_empty() and HeroDatabase.has_hero(selected) else "нет"
	test_status.text = "Золото: %d   Стадия: %d   Волна: %d\nБой: %s   Герой: %s   Казармы: %s" % [gold, stage, wave, state, hero_name, "открыты, ур. %d" % barracks_level if barracks_open else "нет"]

func test_finish(notice: String) -> void:
	save_progress(true); update_hud(); refresh_tab(); refresh_test_status()
	if test_notice: test_notice.text = notice

func test_add_gold(amount: int) -> void:
	gold += amount; test_finish("Добавлено %d золота" % amount)

func test_reset_progress() -> void:
	var delete_error: Error = SaveManager.delete_save()
	if delete_error != OK: push_error("Не удалось удалить сохранение: %s" % delete_error)
	stage = 1; wave = 1; highest_stage_this_run = 1; highest_stage_ever = 1; gold = 0
	heart_shards = 0; prestige_unlocked = false; prestige_damage_level = 0; prestige_gold_level = 0; prestige_start_gold_level = 0
	tower_level = 1; tower_crit_level = 0; tower_crit_mult_level = 0; fortress_level = 1; fortress_armor_level = 0
	barracks_open = false; barracks_level = 0; garrison_damage_level = 0; garrison_health_level = 0; garrison_crit_level = 0; garrison_speed_level = 0
	owned.clear(); selected = ""; active_hero = ""; hero_upgrades.clear()
	reset_stage_combat(false); test_finish("Прогресс сброшен: новая игра")

func test_start_stage() -> void:
	if state == "defeat": reset_stage_combat(true)
	if state == "ready_stage": start_stage(); test_finish("Стадия запущена")
	else: test_finish("Стадия уже идёт")

func test_start_specific_wave(target_wave: int) -> void:
	if state == "defeat": test_finish("Сначала перезапустите стадию"); return
	wave = clampi(target_wave, 1, MAX_WAVES_PER_STAGE); enemies.clear(); projectiles.clear(); state = "battle"; spawn_enemy(); test_finish("Запущена волна %d" % wave)

func test_next_wave() -> void:
	if wave >= MAX_WAVES_PER_STAGE: test_start_specific_wave(MAX_WAVES_PER_STAGE)
	else: test_start_specific_wave(wave + 1)

func test_skip_wave() -> void:
	if state == "defeat": test_finish("Крепость разрушена"); return
	enemies.clear(); projectiles.clear()
	if wave >= MAX_WAVES_PER_STAGE: finish_stage(); test_finish("Босс пропущен")
	else: test_start_specific_wave(wave + 1)

func test_next_stage() -> void:
	stage += 1; wave = 1; highest_stage_this_run = maxi(highest_stage_this_run, stage); highest_stage_ever = maxi(highest_stage_ever, stage); if stage >= PRESTIGE_UNLOCK_STAGE: prestige_unlocked = true
	enemies.clear(); projectiles.clear(); reset_stage_combat(false); test_finish("Подготовлена стадия %d" % stage)

func test_damage_fortress(amount: float) -> void:
	if state == "defeat": test_finish("Крепость уже разрушена"); return
	fortress_hp -= amount
	if fortress_hp <= 0.0: fortress_hp = 0.0; defeat(); test_finish("Крепость уничтожена")
	else: test_finish("Крепости нанесено %d урона" % amount)

func test_grant_hero(id: String) -> void:
	if not owned.has(id): owned.append(id)
	hero_upgrade_data(id); selected = id; test_finish("Выдан герой: %s. Вступит в бой со следующей стадии" % HeroDatabase.get_hero(id).name)

func test_remove_hero() -> void:
	selected = ""; test_finish("Герой убран. Изменение вступит в силу со следующей стадии")

func test_open_barracks() -> void:
	if not barracks_open: barracks_open = true; barracks_level = 1
	test_finish("Казармы открыты. Гарнизон вступит в бой со следующей стадии")

func test_upgrade_garrison(kind: String) -> void:
	if not barracks_open: test_open_barracks()
	if kind == "level": barracks_level += 1
	elif kind == "damage": garrison_damage_level += 1
	elif kind == "health": garrison_health_level += 1
	elif kind == "crit": garrison_crit_level = mini(32, garrison_crit_level + 1)
	else: garrison_speed_level += 1
	test_finish("Улучшен гарнизон: %s" % kind)

func test_remove_garrison() -> void:
	barracks_open = false; barracks_level = 0; garrison_damage_level = 0; garrison_health_level = 0; garrison_crit_level = 0; garrison_speed_level = 0
	test_finish("Гарнизон убран. Изменение вступит в силу со следующей стадии")

func test_upgrade_castle(kind: String) -> void:
	if kind == "tower": tower_level += 1
	elif kind == "tower_crit": tower_crit_level = mini(25, tower_crit_level + 1)
	elif kind == "tower_mult": tower_crit_mult_level += 1
	elif kind == "fortress": fortress_level += 1; fortress_hp += 250
	else: fortress_armor_level += 1
	test_finish("Улучшен замок: %s" % kind)

func make_label(pos: Vector2, size: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new(); label.position = pos; label.size = size; label.add_theme_font_size_override("font_size", font_size); label.add_theme_color_override("font_color", color); label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label

func make_panel_style(background: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(7)
	style.shadow_color = Color("#0a0e16a0")
	style.shadow_size = 3
	return style

func apply_regular_button_style(button: Button) -> void:
	button.add_theme_stylebox_override("normal", make_panel_style(UI_BRONZE_COLOR, Color("#aa8e61"), 1))
	button.add_theme_stylebox_override("hover", make_panel_style(Color("#81705a"), UI_GOLD_COLOR, 2))
	button.add_theme_stylebox_override("pressed", make_panel_style(Color("#41382f"), Color("#e6bd65"), 2))
	button.add_theme_stylebox_override("disabled", make_panel_style(Color("#46505d"), Color("#657283"), 1))
	button.add_theme_color_override("font_color", Color("#f4d797"))
	button.add_theme_color_override("font_hover_color", Color("#fff2cf"))
	button.add_theme_color_override("font_pressed_color", UI_GOLD_COLOR)
	button.add_theme_color_override("font_disabled_color", UI_MUTED_TEXT_COLOR)
	button.add_theme_color_override("font_outline_color", Color("#17202c"))
	button.add_theme_constant_override("outline_size", 1)

func apply_upgrade_button_state(button: Button, availability: String) -> void:
	if availability == "maximum":
		button.add_theme_stylebox_override("disabled", make_panel_style(Color("#526658"), Color("#9cc78f"), 2))
		button.add_theme_color_override("font_disabled_color", Color("#d5ecc7"))
	elif availability == "unavailable":
		button.add_theme_stylebox_override("disabled", make_panel_style(Color("#465566"), Color("#74879a"), 1))
		button.add_theme_color_override("font_disabled_color", Color("#f0ab86"))

func update_tab_styles() -> void:
	for tab_id in tab_buttons:
		var button: Button = tab_buttons[tab_id]
		var is_active: bool = tab_id == active_tab
		var normal_color := Color("#7b684f") if is_active else UI_STONE_COLOR
		var border_color := UI_GOLD_COLOR if is_active else Color("#8493a5")
		button.add_theme_stylebox_override("normal", make_panel_style(normal_color, border_color, 2 if is_active else 1))
		button.add_theme_stylebox_override("hover", make_panel_style(Color("#91806a") if is_active else Color("#6e7b8b"), UI_GOLD_COLOR, 2))
		button.add_theme_stylebox_override("pressed", make_panel_style(Color("#4c4033") if is_active else Color("#394554"), UI_GOLD_COLOR, 2))
		button.add_theme_stylebox_override("disabled", make_panel_style(Color("#37414d"), Color("#596778"), 1))
		button.add_theme_color_override("font_color", UI_GOLD_COLOR if is_active else UI_TEXT_COLOR)
		button.add_theme_color_override("font_pressed_color", Color("#ffe2a0"))

func make_button(text_value: String, pos: Vector2, callback: Callable) -> Button:
	var button := Button.new(); button.text = text_value; button.position = pos; button.size = Vector2(164, 58); button.add_theme_font_size_override("font_size", 14); apply_regular_button_style(button); button.pressed.connect(callback)
	return button

func set_tab(tab: String) -> void:
	active_tab = tab; update_tab_styles(); refresh_tab(false)

func clear_tab() -> void:
	if upgrade_list == null: return
	for child in upgrade_list.get_children(): child.queue_free()

func add_tab_button(text_value: String, _index: int, callback: Callable, availability := "available", purchase_cost := -1) -> void:
	var row := PanelContainer.new(); row.custom_minimum_size = Vector2(0, 52); row.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_theme_stylebox_override("panel", make_panel_style(Color("#485669"), Color("#8798ab"), 1)); upgrade_list.add_child(row)
	var button := Button.new(); button.name = "PurchaseButton"; button.text = text_value; button.custom_minimum_size = Vector2(0, 50); button.size_flags_horizontal = Control.SIZE_EXPAND_FILL; button.add_theme_font_size_override("font_size", 11); button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; apply_regular_button_style(button); apply_upgrade_button_state(button, availability); button.disabled = availability != "available" or state == "defeat"; button.pressed.connect(callback)
	if purchase_cost >= 0:
		button.set_meta("purchase_cost", purchase_cost)
		button.set_meta("maximum", availability == "maximum")
	row.add_child(button)

func add_tab_label(text_value: String, font_size: int, color: Color) -> void:
	var label := Label.new(); label.text = text_value; label.custom_minimum_size = Vector2(0, 28); label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; label.add_theme_font_size_override("font_size", font_size); label.add_theme_color_override("font_color", color); label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; upgrade_list.add_child(label)

func refresh_tab(keep_scroll := true) -> void:
	if upgrade_list == null: return
	var saved_scroll := upgrade_scroll.scroll_vertical if keep_scroll else 0
	clear_tab()
	if active_tab == "castle": build_castle_tab()
	elif active_tab == "hero": build_hero_tab()
	elif active_tab == "garrison": build_garrison_tab()
	elif active_tab == "shop": build_shop_tab()
	else: build_prestige_tab()
	call_deferred("restore_upgrade_scroll", saved_scroll)

func restore_upgrade_scroll(saved_scroll: int) -> void:
	if upgrade_scroll != null: upgrade_scroll.scroll_vertical = saved_scroll

func price_text(cost: int, is_maximum := false) -> String:
	if is_maximum: return "Максимум"
	return "%d золота" % cost if gold >= cost else "Нужно %d золота" % cost

func purchase_state(cost: int, is_maximum := false) -> String:
	if is_maximum: return "maximum"
	return "available" if gold >= cost else "unavailable"

func refresh_tab_purchase_states() -> void:
	if upgrade_list == null: return
	for row in upgrade_list.get_children():
		var button := row.get_node_or_null("PurchaseButton") as Button
		if button == null or not button.has_meta("purchase_cost"): continue
		var cost: int = int(button.get_meta("purchase_cost"))
		var is_maximum: bool = bool(button.get_meta("maximum"))
		var availability := purchase_state(cost, is_maximum)
		if availability == "available": button.text = button.text.replace("Нужно %d золота" % cost, "%d золота" % cost)
		elif availability == "unavailable" and not button.text.contains("Нужно %d золота" % cost): button.text = button.text.replace("%d золота" % cost, "Нужно %d золота" % cost)
		apply_upgrade_button_state(button, availability)
		button.disabled = availability != "available" or state == "defeat"

func build_castle_tab() -> void:
	var tower_crit_maxed: bool = tower_crit_chance() >= 1.0
	var tower_crit_text := "Крит башни ур.%d | 100%% | Максимум" % tower_crit_level if tower_crit_maxed else "Крит башни ур.%d | %d%% → %d%% | %s" % [tower_crit_level, tower_crit_chance()*100, minf(1.0, tower_crit_chance()+.04)*100, price_text(castle_cost("tower_crit"))]
	var data = [["tower", "Башня ур.%d | Тап: %d → %d | %s" % [tower_level, tower_damage(), tower_damage()+12, price_text(castle_cost("tower"))]], ["tower_crit", tower_crit_text], ["tower_mult", "Крит-множ. ур.%d | x%.2f → x%.2f | %s" % [tower_crit_mult_level, tower_crit_multiplier(), tower_crit_multiplier()+.25, price_text(castle_cost("tower_mult"))]], ["fortress", "Крепость ур.%d | %d → %d HP | %s" % [fortress_level, max_fortress(), max_fortress()+250, price_text(castle_cost("fortress"))]], ["armor", "Броня ур.%d | -%d → -%d урона | %s" % [fortress_armor_level, fortress_armor(), fortress_armor()+3, price_text(castle_cost("armor"))]]]
	for i in data.size():
		var kind: String = data[i][0]
		var is_maximum: bool = kind == "tower_crit" and tower_crit_maxed
		var cost := castle_cost(kind)
		add_tab_button(data[i][1], i, func(): upgrade_castle(kind), purchase_state(cost, is_maximum), cost)

func build_hero_tab() -> void:
	if selected.is_empty() or not owned.has(selected):
		add_tab_label("Герой не выбран. Купите героя в магазине.", 16, Color("#e6d7bd"))
		add_tab_button("Открыть магазин героев", 2, func(): set_tab("shop")); return
	var stats := hero_stats(selected)
	add_tab_label("%s • HP %d • Урон %d • крит %d%% x%.1f" % [stats.name, stats.hp, stats.damage, stats.crit*100, stats.mult], 12, stats.color)
	var kinds = ["damage", "health", "crit", "mult", "speed"]
	var names = ["Урон", "Здоровье", "Крит шанс", "Крит множ.", "Скорость"]
	var values = ["%d → %d" % [stats.damage, stats.damage+7], "%d → %d" % [stats.hp, stats.hp+35], "%d%% → %d%%" % [stats.crit*100, (stats.crit+.03)*100], "x%.1f → x%.1f" % [stats.mult, stats.mult+.2], "%.2fс → %.2fс" % [stats.cooldown, maxf(.22, stats.cooldown-.05)]]
	for i in kinds.size():
		var cost := hero_upgrade_cost(selected, kinds[i])
		var kind: String = kinds[i]
		var is_maximum: bool = kind == "crit" and stats.crit >= 1.0
		if kind == "crit": values[i] = "100%% | Максимум" if is_maximum else "%d%% → %d%%" % [stats.crit*100, minf(1.0, stats.crit+.03)*100]
		add_tab_button("%s ур.%d | %s | %s" % [names[i], hero_upgrade_data(selected)[kind], values[i], price_text(cost, is_maximum)], i, func(): upgrade_hero(kind), purchase_state(cost, is_maximum), cost)

func build_garrison_tab() -> void:
	if not barracks_open:
		add_tab_label("Гарнизона нет. Откройте казармы и наймите стражника.", 15, Color("#e6d7bd"))
		var cost := 220
		add_tab_button("Открыть казармы + стражник | %s" % price_text(cost), 2, open_barracks, purchase_state(cost), cost); return
	add_tab_label("Стражник у ворот • следующее пополнение: %s" % garrison_next_unit(), 12, Color("#9fc8a0"))
	var garrison_crit_maxed: bool = garrison_crit_chance() >= 1.0
	var garrison_crit_text := "Крит ур.%d | 100%% | Максимум" % garrison_crit_level if garrison_crit_maxed else "Крит ур.%d | %d%% → %d%% | %s" % [garrison_crit_level, garrison_crit_chance()*100, minf(1.0, garrison_crit_chance()+.03)*100, price_text(barracks_cost("crit"))]
	var data = [["level", "Казармы ур.%d | след.: %s | %s" % [barracks_level, garrison_next_unit(), price_text(barracks_cost("level"))]], ["damage", "Урон ур.%d | %d → %d | %s" % [garrison_damage_level, garrison_damage(), garrison_damage()+6, price_text(barracks_cost("damage"))]], ["health", "Здоровье ур.%d | %d → %d | %s" % [garrison_health_level, garrison_max_health(), garrison_max_health()+28, price_text(barracks_cost("health"))]], ["crit", garrison_crit_text], ["speed", "Скорость ур.%d | %.2fс → %.2fс | %s" % [garrison_speed_level, garrison_cooldown(), maxf(.25,garrison_cooldown()-.06), price_text(barracks_cost("speed"))]]]
	for i in data.size():
		var kind: String = data[i][0]
		var is_maximum: bool = kind == "crit" and garrison_crit_maxed
		var cost := barracks_cost(kind)
		add_tab_button(data[i][1], i, func(): upgrade_barracks(kind), purchase_state(cost, is_maximum), cost)

func build_shop_tab() -> void:
	var i := 0
	for id in HeroDatabase.get_hero_ids():
		var hero: Dictionary = HeroDatabase.get_hero(id)
		var status := "Выбрать" if owned.has(id) else "Купить: %d ✦" % hero.cost
		var hero_id: String = id
		var purchase_cost: int = -1 if owned.has(hero_id) else hero.cost
		add_tab_button("%s | HP %d • Урон %d • %s" % [hero.name, hero.hp, hero.damage, status], i, func(): shop_hero(hero_id), "available" if owned.has(hero_id) else purchase_state(hero.cost), purchase_cost)
		i += 1

func add_prestige_button(text_value: String, callback: Callable, enabled: bool) -> void:
	var row := PanelContainer.new(); row.custom_minimum_size = Vector2(0, 68); row.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_theme_stylebox_override("panel", make_panel_style(Color("#4c475e"), Color("#b49a67"), 1)); upgrade_list.add_child(row)
	var button := Button.new(); button.text = text_value; button.custom_minimum_size = Vector2(0, 66); button.size_flags_horizontal = Control.SIZE_EXPAND_FILL; button.add_theme_font_size_override("font_size", 12); button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; apply_regular_button_style(button); button.disabled = not enabled or state == "defeat"; button.pressed.connect(callback); row.add_child(button)

func prestige_price_text(cost: int, is_maximum: bool) -> String:
	if is_maximum: return "Максимум"
	return "%d Осколков" % cost if heart_shards >= cost else "Нужно %d Осколков" % cost

func build_prestige_tab() -> void:
	var reward := calculate_prestige_reward()
	add_tab_label("Осколки Сердца: %d  •  Рекорд этапа: %d" % [heart_shards, highest_stage_ever], 14, Color("#f2cd78"))
	if not is_prestige_tab_unlocked():
		add_prestige_button("Перерождение\nОткроется на этапе %d (сейчас: %d)" % [PRESTIGE_UNLOCK_STAGE, highest_stage_this_run], open_prestige_confirmation, false)
	else:
		var prestige_ready := can_prestige_now()
		var prestige_text := "Перерождение\nПолучить: %d Осколка(ов) Сердца" % reward if prestige_ready else "Перерождение\nНужно достичь этапа %d в текущем цикле (сейчас: %d)" % [PRESTIGE_UNLOCK_STAGE, highest_stage_this_run]
		add_prestige_button(prestige_text, open_prestige_confirmation, prestige_ready and reward > 0)
	var damage_cost := get_prestige_upgrade_cost(prestige_damage_level)
	var damage_maxed := prestige_damage_level >= PRESTIGE_DAMAGE_MAX_LEVEL
	add_prestige_button("Сила Сердца ур.%d/%d\nУрон: +%d%% → +%d%% | %s" % [prestige_damage_level, PRESTIGE_DAMAGE_MAX_LEVEL, prestige_damage_level * 10, mini(PRESTIGE_DAMAGE_MAX_LEVEL, prestige_damage_level + 1) * 10, prestige_price_text(damage_cost, damage_maxed)], buy_prestige_damage_upgrade, can_buy_prestige_upgrades() and not damage_maxed and heart_shards >= damage_cost)
	var gold_cost := get_prestige_upgrade_cost(prestige_gold_level)
	var gold_maxed := prestige_gold_level >= PRESTIGE_GOLD_MAX_LEVEL
	add_prestige_button("Знание охотника ур.%d/%d\nЗолото: +%d%% → +%d%% | %s" % [prestige_gold_level, PRESTIGE_GOLD_MAX_LEVEL, prestige_gold_level * 10, mini(PRESTIGE_GOLD_MAX_LEVEL, prestige_gold_level + 1) * 10, prestige_price_text(gold_cost, gold_maxed)], buy_prestige_gold_upgrade, can_buy_prestige_upgrades() and not gold_maxed and heart_shards >= gold_cost)
	var start_cost := get_prestige_upgrade_cost(prestige_start_gold_level)
	var start_maxed := prestige_start_gold_level >= PRESTIGE_START_GOLD_MAX_LEVEL
	var next_start_level := mini(PRESTIGE_START_GOLD_MAX_LEVEL, prestige_start_gold_level + 1)
	add_prestige_button("Запасы крепости ур.%d/%d\nСтарт: %d → %d золота | %s" % [prestige_start_gold_level, PRESTIGE_START_GOLD_MAX_LEVEL, prestige_starting_gold(), STARTING_GOLD_VALUES[next_start_level], prestige_price_text(start_cost, start_maxed)], buy_prestige_start_gold_upgrade, can_buy_prestige_upgrades() and not start_maxed and heart_shards >= start_cost)

func upgrade_castle(kind: String) -> void:
	if kind == "tower_crit" and tower_crit_chance() >= 1.0: return
	var cost := castle_cost(kind)
	if gold < cost: message_label.text = "Нужно %d золота" % cost; return
	gold -= cost
	if kind == "tower": tower_level += 1
	elif kind == "tower_crit": tower_crit_level += 1
	elif kind == "tower_mult": tower_crit_mult_level += 1
	elif kind == "fortress": fortress_level += 1; fortress_hp += 250
	else: fortress_armor_level += 1
	message_label.modulate = NORMAL_MESSAGE_COLOR; message_label.text = "Улучшение завершено!"; save_progress(true); update_hud(); refresh_tab()

func upgrade_hero(kind: String) -> void:
	if selected.is_empty(): return
	if kind == "crit" and hero_stats(selected).crit >= 1.0: return
	var cost := hero_upgrade_cost(selected, kind)
	if gold < cost: message_label.text = "Нужно %d золота" % cost; return
	gold -= cost; hero_upgrade_data(selected)[kind] += 1
	if kind == "health" and hero_alive and selected == active_hero: hero_hp += 35.0
	message_label.modulate = NORMAL_MESSAGE_COLOR; message_label.text = "Герой улучшен!"; save_progress(true); update_hud(); refresh_tab()

func open_barracks() -> void:
	if gold < 220: message_label.text = "Нужно 220 золота"; return
	gold -= 220; barracks_open = true; barracks_level = 1; add_garrison_reinforcements(); message_label.modulate = NORMAL_MESSAGE_COLOR; message_label.text = "Казармы открыты. Стражник вступил в бой!"; save_progress(true); update_hud(); refresh_tab()

func upgrade_barracks(kind: String) -> void:
	if kind == "crit" and garrison_crit_chance() >= 1.0: return
	var cost := barracks_cost(kind)
	if gold < cost: message_label.text = "Нужно %d золота" % cost; return
	gold -= cost
	if kind == "level": barracks_level += 1; add_garrison_reinforcements()
	elif kind == "damage": garrison_damage_level += 1
	elif kind == "health":
		garrison_health_level += 1
		for unit in garrison_units:
			if unit.alive: unit.max_hp += 28.0; unit.hp += 28.0
	elif kind == "crit": garrison_crit_level += 1
	else: garrison_speed_level += 1
	message_label.modulate = NORMAL_MESSAGE_COLOR; message_label.text = "Гарнизон улучшен!"; save_progress(true); update_hud(); refresh_tab()

func shop_hero(id: String) -> void:
	var hero: Dictionary = HeroDatabase.get_hero(id)
	if not owned.has(id):
		if gold < hero.cost: message_label.text = "Нужно %d золота" % hero.cost; return
		gold -= hero.cost; owned.append(id); hero_upgrade_data(id); message_label.text = "%s куплен!" % hero.name
	selected = id
	message_label.modulate = NORMAL_MESSAGE_COLOR
	save_progress(true); update_hud(); refresh_tab()

func is_prestige_tab_unlocked() -> bool:
	return prestige_unlocked

func can_prestige_now() -> bool:
	return highest_stage_this_run >= PRESTIGE_UNLOCK_STAGE

func can_buy_prestige_upgrades() -> bool:
	return is_prestige_tab_unlocked()

func calculate_prestige_reward() -> int:
	if highest_stage_this_run < PRESTIGE_UNLOCK_STAGE: return 0
	return maxi(1, int(floor(pow(float(highest_stage_this_run) / 10.0, 1.8))))

func get_prestige_upgrade_cost(level: int) -> int:
	return int(pow(2.0, level))

func build_prestige_confirmation(root: Control) -> void:
	prestige_overlay = Control.new(); prestige_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); prestige_overlay.mouse_filter = Control.MOUSE_FILTER_STOP; prestige_overlay.visible = false; root.add_child(prestige_overlay)
	var shade := ColorRect.new(); shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); shade.color = Color("#05070ce8"); shade.mouse_filter = Control.MOUSE_FILTER_STOP; prestige_overlay.add_child(shade)
	var panel := Panel.new(); panel.position = Vector2(24, 250); panel.size = Vector2(492, 420); panel.add_theme_stylebox_override("panel", make_panel_style(Color("#344154"), Color("#d0ab64"), 2)); prestige_overlay.add_child(panel)
	var title := make_label(Vector2(20, 16), Vector2(452, 36), 24, Color("#ffd77d")); title.text = "ПЕРЕРОЖДЕНИЕ"; title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; panel.add_child(title)
	prestige_summary = make_label(Vector2(28, 66), Vector2(436, 244), 15, Color("#e6d7bd")); prestige_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; prestige_summary.vertical_alignment = VERTICAL_ALIGNMENT_TOP; panel.add_child(prestige_summary)
	var cancel := make_button("Отмена", Vector2(28, 338), close_prestige_confirmation); cancel.size = Vector2(206, 58); panel.add_child(cancel)
	prestige_confirm_button = make_button("Переродиться", Vector2(258, 338), perform_prestige); prestige_confirm_button.size = Vector2(206, 58); panel.add_child(prestige_confirm_button)

func open_prestige_confirmation() -> void:
	if prestige_in_progress or not can_prestige_now() or prestige_overlay == null: return
	var reward := calculate_prestige_reward()
	if reward <= 0: return
	prestige_summary.text = "Текущий этап: %d\nМаксимальный этап цикла: %d\n\nВы получите:\n%d Осколка(ов) Сердца\n\nБудут сброшены:\n— золото, этап и волна;\n— герои, гарнизон и обычные улучшения;\n— текущий враг и его здоровье.\n\nСохранятся Осколки, престижные улучшения и рекорд." % [stage, highest_stage_this_run, reward]
	prestige_confirm_button.disabled = false
	prestige_overlay.visible = true

func close_prestige_confirmation() -> void:
	if prestige_overlay != null: prestige_overlay.visible = false

func reset_run_progress() -> void:
	stage = 1; wave = 1; highest_stage_this_run = 1
	gold = prestige_starting_gold()
	tower_level = 1; tower_crit_level = 0; tower_crit_mult_level = 0; fortress_level = 1; fortress_armor_level = 0
	barracks_open = false; barracks_level = 0; garrison_damage_level = 0; garrison_health_level = 0; garrison_crit_level = 0; garrison_speed_level = 0
	owned.clear(); selected = ""; active_hero = ""; hero_upgrades.clear()
	enemies.clear(); projectiles.clear(); effects.clear(); enemy_is_dying = false
	reset_stage_combat(true)

func perform_prestige() -> void:
	if prestige_in_progress or not can_prestige_now(): return
	var reward := calculate_prestige_reward()
	if reward <= 0: return
	prestige_in_progress = true
	heart_shards = maxi(0, heart_shards + reward)
	reset_run_progress()
	close_prestige_confirmation()
	start_stage()
	save_progress(true)
	update_hud()
	refresh_tab()
	prestige_in_progress = false

func buy_prestige_damage_upgrade() -> void:
	if not can_buy_prestige_upgrades() or prestige_damage_level >= PRESTIGE_DAMAGE_MAX_LEVEL: return
	var cost := get_prestige_upgrade_cost(prestige_damage_level)
	if heart_shards < cost: return
	heart_shards -= cost; prestige_damage_level += 1; save_progress(true); update_hud(); refresh_tab()

func buy_prestige_gold_upgrade() -> void:
	if not can_buy_prestige_upgrades() or prestige_gold_level >= PRESTIGE_GOLD_MAX_LEVEL: return
	var cost := get_prestige_upgrade_cost(prestige_gold_level)
	if heart_shards < cost: return
	heart_shards -= cost; prestige_gold_level += 1; save_progress(true); update_hud(); refresh_tab()

func buy_prestige_start_gold_upgrade() -> void:
	if not can_buy_prestige_upgrades() or prestige_start_gold_level >= PRESTIGE_START_GOLD_MAX_LEVEL: return
	var cost := get_prestige_upgrade_cost(prestige_start_gold_level)
	if heart_shards < cost: return
	heart_shards -= cost; prestige_start_gold_level += 1; save_progress(true); update_hud(); refresh_tab()

func update_hud() -> void:
	if stage_label == null: return
	stage_label.text = "СТАДИЯ %d   •   ВОЛНА %d / %d" % [stage, wave, MAX_WAVES_PER_STAGE]
	var hero_name: String = hero_stats(active_hero).name if hero_alive else "Герой не выбран" if active_hero.is_empty() else "%s (пал)" % hero_stats(active_hero).name
	info_label.text = "Крепость %d/%d  броня -%d     %s" % [max(0, fortress_hp), max_fortress(), fortress_armor(), hero_name]
	gold_label.text = "✦ %d золота   •   Осколки Сердца: %d" % [gold, heart_shards]
	start_stage_button.visible = state == "ready_stage"
	start_stage_button.text = "Начать стадию %d" % stage
	retry_button.visible = state == "defeat"
	for tab_id in tab_buttons:
		tab_buttons[tab_id].disabled = state == "defeat"
	if upgrade_list != null:
		for row in upgrade_list.get_children():
			var purchase_button := row.get_node_or_null("PurchaseButton") as Button
			if purchase_button != null and state == "defeat": purchase_button.disabled = true
	if test_console_open: refresh_test_status()
	update_enemy_ui()

func mark_save_dirty() -> void:
	save_dirty = true

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if save_dirty: save_progress()

func build_save_data() -> Dictionary:
	return {
		"version": SAVE_VERSION, "stage": stage, "gold": gold,
		"highest_stage_this_run": highest_stage_this_run, "highest_stage_ever": highest_stage_ever,
		"heart_shards": heart_shards, "prestige_unlocked": prestige_unlocked,
		"prestige_damage_level": prestige_damage_level, "prestige_gold_level": prestige_gold_level, "prestige_start_gold_level": prestige_start_gold_level,
		"tower_level": tower_level, "tower_crit_level": tower_crit_level, "tower_crit_mult_level": tower_crit_mult_level,
		"fortress_level": fortress_level, "fortress_armor_level": fortress_armor_level,
		"barracks_open": barracks_open, "barracks_level": barracks_level,
		"garrison_damage_level": garrison_damage_level, "garrison_health_level": garrison_health_level,
		"garrison_crit_level": garrison_crit_level, "garrison_speed_level": garrison_speed_level,
		"owned": owned, "selected": selected, "active_hero": active_hero, "hero_upgrades": hero_upgrades
	}

func save_progress(force: bool = false) -> void:
	if not force and not save_dirty: return
	var error: Error = SaveManager.save_game(build_save_data())
	if error != OK:
		push_error("Не удалось сохранить прогресс: %s" % error)
		return
	save_dirty = false
	autosave_timer = 0.0

func load_int_clamped(data: Dictionary, key: String, default_value: int, min_value: int, max_value: int) -> int:
	var value = data.get(key, default_value)
	if not (value is int or value is float): return default_value
	if value is float and (is_nan(value) or is_inf(value)): return default_value
	return clampi(int(value), min_value, max_value)

func save_bool(data: Dictionary, key: String, default_value: bool) -> bool:
	var value = data.get(key, default_value)
	if value is bool: return value
	if value is int: return value != 0
	return default_value

func apply_save_data(data: Dictionary) -> void:
	stage = load_int_clamped(data, "stage", 1, 1, MAX_STAGE); gold = load_int_clamped(data, "gold", 0, 0, MAX_GOLD)
	highest_stage_this_run = maxi(stage, load_int_clamped(data, "highest_stage_this_run", stage, 1, MAX_STAGE))
	highest_stage_ever = maxi(highest_stage_this_run, load_int_clamped(data, "highest_stage_ever", highest_stage_this_run, 1, MAX_STAGE))
	heart_shards = load_int_clamped(data, "heart_shards", 0, 0, MAX_GOLD)
	prestige_unlocked = save_bool(data, "prestige_unlocked", false) or highest_stage_ever >= PRESTIGE_UNLOCK_STAGE
	prestige_damage_level = load_int_clamped(data, "prestige_damage_level", 0, 0, mini(PRESTIGE_DAMAGE_MAX_LEVEL, MAX_PRESTIGE_UPGRADE_LEVEL))
	prestige_gold_level = load_int_clamped(data, "prestige_gold_level", 0, 0, mini(PRESTIGE_GOLD_MAX_LEVEL, MAX_PRESTIGE_UPGRADE_LEVEL))
	prestige_start_gold_level = load_int_clamped(data, "prestige_start_gold_level", 0, 0, mini(PRESTIGE_START_GOLD_MAX_LEVEL, MAX_PRESTIGE_UPGRADE_LEVEL))
	var version := load_int_clamped(data, "version", 0, 0, SAVE_VERSION)
	if version == 0:
		fortress_level = load_int_clamped(data, "fortress", 1, 1, MAX_STANDARD_UPGRADE_LEVEL); tower_level = load_int_clamped(data, "forge", 1, 1, MAX_STANDARD_UPGRADE_LEVEL)
		barracks_level = load_int_clamped(data, "barracks", 0, 0, MAX_STANDARD_UPGRADE_LEVEL); barracks_open = barracks_level > 0
	else:
		tower_level = load_int_clamped(data, "tower_level", 1, 1, MAX_STANDARD_UPGRADE_LEVEL); tower_crit_level = load_int_clamped(data, "tower_crit_level", 0, 0, MAX_STANDARD_UPGRADE_LEVEL); tower_crit_mult_level = load_int_clamped(data, "tower_crit_mult_level", 0, 0, MAX_STANDARD_UPGRADE_LEVEL)
		fortress_level = load_int_clamped(data, "fortress_level", 1, 1, MAX_STANDARD_UPGRADE_LEVEL); fortress_armor_level = load_int_clamped(data, "fortress_armor_level", 0, 0, MAX_STANDARD_UPGRADE_LEVEL)
		barracks_open = save_bool(data, "barracks_open", false); barracks_level = load_int_clamped(data, "barracks_level", 0, 0, MAX_STANDARD_UPGRADE_LEVEL)
		garrison_damage_level = load_int_clamped(data, "garrison_damage_level", 0, 0, MAX_STANDARD_UPGRADE_LEVEL); garrison_health_level = load_int_clamped(data, "garrison_health_level", 0, 0, MAX_STANDARD_UPGRADE_LEVEL)
		garrison_crit_level = load_int_clamped(data, "garrison_crit_level", 0, 0, MAX_STANDARD_UPGRADE_LEVEL); garrison_speed_level = load_int_clamped(data, "garrison_speed_level", 0, 0, MAX_STANDARD_UPGRADE_LEVEL)
	if not barracks_open: barracks_level = 0
	owned.clear()
	var stored_owned = data.get("owned", [])
	if stored_owned is Array:
		for value in stored_owned:
			if value is String and HeroDatabase.has_hero(value): owned.append(value)
	selected = data.get("selected", "") if data.get("selected", "") is String else ""
	active_hero = data.get("active_hero", "") if data.get("active_hero", "") is String else ""
	if not owned.has(selected): selected = ""
	if not owned.has(active_hero): active_hero = ""
	hero_upgrades.clear()
	var stored_upgrades = data.get("hero_upgrades", {})
	if stored_upgrades is Dictionary:
		for hero_id in stored_upgrades:
			if not hero_id is String or not HeroDatabase.has_hero(hero_id): continue
			var stored_hero_data = stored_upgrades[hero_id]
			if not stored_hero_data is Dictionary: continue
			hero_upgrades[hero_id] = {
				"damage": load_int_clamped(stored_hero_data, "damage", 0, 0, MAX_HERO_UPGRADE_LEVEL), "health": load_int_clamped(stored_hero_data, "health", 0, 0, MAX_HERO_UPGRADE_LEVEL),
				"crit": load_int_clamped(stored_hero_data, "crit", 0, 0, MAX_HERO_UPGRADE_LEVEL), "mult": load_int_clamped(stored_hero_data, "mult", 0, 0, MAX_HERO_UPGRADE_LEVEL), "speed": load_int_clamped(stored_hero_data, "speed", 0, 0, MAX_HERO_UPGRADE_LEVEL)
			}
	for hero_id in owned: hero_upgrade_data(hero_id)

func load_progress() -> void:
	var data: Dictionary = SaveManager.load_game()
	if data.is_empty(): return
	apply_save_data(data)

func _draw() -> void:
	draw_rect(Rect2(0, 0, W, H), Color("#0b1020")); draw_circle(Vector2(445, 155), 46, Color("#303650"))
	draw_colored_polygon(PackedVector2Array([Vector2(0,410),Vector2(130,250),Vector2(260,400),Vector2(385,230),Vector2(540,390),Vector2(540,704),Vector2(0,704)]), Color("#192036"))
	draw_rect(Rect2(0, 600, W, 104), Color("#25252b")); draw_line(Vector2(0,620),Vector2(W,620),Color("#48413d"),2)
	draw_rect(Rect2(35, 392, 205, 214), Color("#5b5b61")); draw_rect(Rect2(35, 392, 205, 214), Color("#262a33"), 4)
	for x in range(43, 235, 28): draw_rect(Rect2(x, 378, 17, 30), Color("#727177")); draw_rect(Rect2(x, 378, 17, 30), Color("#282b34"), 2)
	draw_rect(Rect2(75, 287, 94, 113), Color("#606169")); draw_rect(Rect2(75, 287, 94, 113), Color("#242832"), 4); draw_polygon(PackedVector2Array([Vector2(62,287),Vector2(122,220),Vector2(182,287)]), PackedColorArray([Color("#303346")]))
	draw_rect(Rect2(107, 336, 28, 64), Color("#111722")); draw_circle(Vector2(121, 340), 14, Color("#111722")); draw_rect(Rect2(74, 532, 72, 74), Color("#202027")); draw_circle(Vector2(110,535),36,Color("#202027"))
	for x in [58, 208]: draw_circle(Vector2(x, 463), 12 + sin(Time.get_ticks_msec()/150.0)*2, Color("#f49b3a")); draw_circle(Vector2(x,463),6,Color("#fff0a6"))
	if hero_alive:
		var phase := 1.0 - hero_attack_timer / HERO_ATTACK_DURATION
		draw_unit(Vector2(190, 585) + Vector2(13, -3) * sin(phase * PI), hero_stats(active_hero).color, hero_stats(active_hero).attack)
	for unit in garrison_units:
		if unit.alive: draw_unit(Vector2(unit.x, unit.y), Color("#93bc79") if unit.kind == "archer" else Color("#adadba") if unit.kind == "knight" else Color("#bbb48d"), unit.kind)
	for enemy in enemies: draw_enemy(enemy)
	draw_enemy_health_bar()
	for projectile in projectiles: draw_projectile(projectile)
	for fx in effects:
		var alpha := clampf(fx.life/.85,0.0,1.0); var text_color: Color = fx.color; text_color.a = alpha
		draw_string(ThemeDB.fallback_font, fx.pos + Vector2(0,(1.0-alpha)*-34), fx.text, HORIZONTAL_ALIGNMENT_CENTER, -1, 15, text_color)
	if state == "defeat":
		draw_rect(Rect2(0,128,W,560),Color("#070912b4")); draw_string(ThemeDB.fallback_font,Vector2(112,330),"КРЕПОСТЬ РАЗРУШЕНА",HORIZONTAL_ALIGNMENT_LEFT,-1,27,Color("#ff756b"))

func draw_unit(pos: Vector2, color: Color, kind: String) -> void:
	draw_circle(pos+Vector2(0,-16),10,Color("#e2c3a0")); draw_rect(Rect2(pos.x-11,pos.y-8,22,29),color); draw_circle(pos+Vector2(0,23),12,Color("#191d25"))
	if kind in ["archer","arrow"]: draw_arc(pos+Vector2(12,0),13,-1.4,1.4,12,Color("#e2c993"),2)
	elif kind == "magic": draw_circle(pos+Vector2(12,-2),8+sin(Time.get_ticks_msec()/160.0)*2,Color("#bf8aff"))
	else: draw_line(pos+Vector2(10,0),pos+Vector2(22,-16),Color("#e5e3d0"),3)

func draw_enemy(enemy: Dictionary) -> void:
	var pos := Vector2(enemy.x,enemy.y)
	var body: Color = Color("#9c4850") if enemy.boss else Color("#815d91") if enemy.type == "elite" else Color("#68864b")
	if enemy.flash > 0: body = Color.WHITE
	draw_circle(pos+Vector2(0,14),22 if enemy.boss else 17,body); draw_circle(pos+Vector2(0,-12),15 if enemy.boss else 12,body.darkened(.08)); draw_circle(pos+Vector2(-5,-14),2,Color("#ffdb64")); draw_circle(pos+Vector2(5,-14),2,Color("#ffdb64"))
	# Health is drawn by the single shared bar above the battlefield.
	if enemy.boss: draw_string(ThemeDB.fallback_font,pos+Vector2(-24,-56),"БОСС",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("#ffbe70"))

func draw_enemy_health_bar() -> void:
	if enemies.is_empty(): return
	var enemy: Dictionary = enemies[0]
	var bar_rect := Rect2(70, 157, 400, 12)
	draw_rect(bar_rect, Color("#161923"))
	draw_rect(Rect2(bar_rect.position + Vector2(2, 2), Vector2((bar_rect.size.x - 4.0) * clampf(wave_current_health / maxf(1.0, wave_max_health), 0.0, 1.0), 8)), Color("#d66a4d") if enemy.boss else Color("#c95155"))
	draw_rect(bar_rect, Color("#ffbe70") if enemy.boss else Color("#8c9aa8"), false, 1.0)

func draw_projectile(projectile: Dictionary) -> void:
	var pos: Vector2 = projectile.from.lerp(projectile.to,minf(projectile.t,1.0)); var color := Color("#ff764e") if projectile.crit else Color("#ffdc76") if projectile.kind == "tower" else Color("#c994ff") if projectile.kind == "magic" else Color("#e7e2c5")
	draw_circle(pos,7 if projectile.kind == "tower" else 4,color); draw_circle(pos,2,Color.WHITE)
