extends SceneTree

const EconomyCalculatorScript = preload("res://scripts/economy_calculator.gd")

var failures := 0

func _init() -> void:
	check(EconomyCalculatorScript.growing_cost(90, 1.52, 0, 9_007_199_254_740_991) == 90, "first upgrade cost")
	check(EconomyCalculatorScript.growing_cost(90, 1.52, 5, 9_007_199_254_740_991) == 730, "middle upgrade cost")
	check(EconomyCalculatorScript.growing_cost(90, 1.52, 10000, 5000) == 5000, "high level cost is capped")
	check(EconomyCalculatorScript.capped_reward(NAN, 100) == 100 and EconomyCalculatorScript.capped_reward(INF, 100) == 100, "non-finite reward is capped")
	check(EconomyCalculatorScript.format_number(1250.0) == "1.25K", "K formatting")
	check(EconomyCalculatorScript.format_number(1_500_000.0) == "1.50M", "M formatting")
	check(EconomyCalculatorScript.format_number(2_000_000_000.0) == "2.00B", "B formatting")
	check(EconomyCalculatorScript.format_number(999.0) == "999", "plain number formatting")
	if failures == 0:
		print("Economy regression checks passed.")
		quit(0)
	quit(1)

func check(condition: bool, description: String) -> void:
	if condition: return
	failures += 1
	push_error("Economy regression check failed: %s" % description)
