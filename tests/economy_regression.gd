extends SceneTree

const EconomyCalculatorScript = preload("res://scripts/economy_calculator.gd")
const GameScript = preload("res://main.gd")
const MAXIMUM := 9_007_199_254_740_991

var failures := 0

func _init() -> void:
	for level in [0, 1, 5, 20, 100]:
		var expected := int(minf(float(MAXIMUM), 90.0 * pow(1.52, level)))
		check(EconomyCalculatorScript.growing_cost(90, 1.52, level, MAXIMUM, 100) == expected, "legacy tower formula at level %d" % level)
	var capped_at_100 := EconomyCalculatorScript.growing_cost(90, 1.52, 100, MAXIMUM, 100)
	check(EconomyCalculatorScript.growing_cost(90, 1.52, 101, MAXIMUM, 100) == capped_at_100, "cost exponent caps at 100")
	check(EconomyCalculatorScript.growing_cost(90, 1.52, 10000, MAXIMUM, 100) == capped_at_100, "very high level keeps old exponent cap")
	check(EconomyCalculatorScript.growing_cost(90, 1.52, 10000, 5000, 100) == 5000, "high level cost is capped")
	check(EconomyCalculatorScript.capped_reward(NAN, 100) == 100 and EconomyCalculatorScript.capped_reward(INF, 100) == 100, "non-finite reward is capped")
	check(EconomyCalculatorScript.format_number(1250.0) == "1.25K", "K formatting")
	check(EconomyCalculatorScript.format_number(1_500_000.0) == "1.50M", "M formatting")
	check(EconomyCalculatorScript.format_number(2_000_000_000.0) == "2.00B", "B formatting")
	check(EconomyCalculatorScript.format_number(999.0) == "999", "plain number formatting")
	var game := GameScript.new()
	check(game.castle_cost("tower") == EconomyCalculatorScript.growing_cost(90, 1.52, game.tower_level, MAXIMUM, 100), "tower uses economy calculator")
	check(game.castle_cost("fortress") == EconomyCalculatorScript.growing_cost(110, 1.52, game.fortress_level, MAXIMUM, 100), "fortress uses economy calculator")
	check(game.barracks_cost("level") == EconomyCalculatorScript.growing_cost(170, 1.5, game.barracks_level, MAXIMUM, 100), "barracks uses economy calculator")
	check(game.hero_upgrade_cost("knight", "damage") == EconomyCalculatorScript.growing_cost(100, 1.55, 0, MAXIMUM, 100), "hero upgrade uses economy calculator")
	check(game.format_number(1250.0) == EconomyCalculatorScript.format_number(1250.0), "game formatting uses economy calculator")
	game.free()
	if failures == 0:
		print("Economy regression checks passed.")
		quit(0)
	quit(1)

func check(condition: bool, description: String) -> void:
	if condition: return
	failures += 1
	push_error("Economy regression check failed: %s" % description)
