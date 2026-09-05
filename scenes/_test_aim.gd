extends Node3D

const BOSS := preload("res://scripts/boss.gd")
const GEN := preload("res://scripts/world_gen.gd")

var _boss: Node3D
var _t := 0.0
var _player := Vector3(330, 18.2, 700)
var _aims: Array[Dictionary] = []
var _last_live := -1

func _ready() -> void:
	GEN.generate_now()
	_boss = BOSS.new()
	_boss.name = "Boss"
	_boss.setup(self, Vector3(GEN.BOSS_CENTER.x, 0.0, GEN.BOSS_CENTER.y))
	add_child(_boss)
	await get_tree().create_timer(3.5).timeout
	print("STATE=", _boss.get("state"))


func _process(delta: float) -> void:
	_t += delta
	# Player circles the boss on the XZ plane (-250 offset so it stays within
	# combat range the whole loop)
	var ang: float = _t * 0.3
	_player = Vector3(512.0 + cos(ang) * 200.0, 18.2, 512.0 + sin(ang) * 200.0)
	_boss.update(delta, _player)
	var live := 0
	var names := ""
	for child in get_children():
		names += child.name + " "
		if child.name == "Shard":
			live += 1
	if live != _last_live or _boss._shards.size() != live:
		print("TREE_CHILDREN=", names, "| live=", live, " buf=", _boss._shards.size())
		for s in _boss._shards:
			var n: Node = s["node"]
			print("  buf[name=", n.get_name(), "] parent=", n.get_parent().get_name(), " in_tree=", n.is_inside_tree())
		_last_live = live
	if _t > 14.0 and _aims.size() >= 3:
		var dots := ""
		for a in _aims:
			dots += "\n  t=%4.1f  dot=%5.2f" % [a["t"], a["dot"]]
		print("AIM_DOTS=", dots)
		get_tree().quit()