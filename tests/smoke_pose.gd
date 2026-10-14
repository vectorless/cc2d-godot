extends Node2D
## Finds the right-arm pose for smoking: the held item's mouth end (filter / mouthpiece) at the lips,
## the hand in front of the face and the lit end pointing away from it. Prints the rotation offsets.
func find(ch, suffix: String) -> Node2D:
	for k in ch.parts:
		if String(k).ends_with(suffix):
			return ch.parts[k]
	return null
func wsprite(ch) -> Node2D:
	for k in ch.sprites:
		if String(k).ends_with("Bone_Weapon R/Weapon R"):
			return ch.sprites[k]
	return null
func _ready() -> void:
	CC2DCharacter.add_part_pack("res://custom/smoking/parts.json")
	var pack: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://custom/smoking/parts.json"))
	var ch := CC2DCharacter.new()
	ch.character_file = "res://characters/exa/character.json"
	ch.autoplay = false
	add_child(ch)
	await get_tree().process_frame
	var total := {}
	for bt in ["Male", "Female"]:
		ch.set_body_type(bt)
		for p in pack.categories.Weapon:
			ch.equip_part("MainHand", p.name, "Smoking")
			ch.pose("Idle", 0.0)
			await get_tree().process_frame
			var up := find(ch, "Bone_Upper Arm R")
			var lo := find(ch, "Bone_Lower Arm R")
			var hd := find(ch, "Bone_Hand R")
			var mouth := find(ch, "/Mouth F")
			var spr := wsprite(ch)
			var me := Vector2(p.mouth_end[0], p.mouth_end[1])
			var tip := Vector2(p.smoke_tip[0], p.smoke_tip[1])
			var u0 := up.rotation
			var l0 := lo.rotation
			var h0 := hd.rotation
			var lips := mouth.global_position + Vector2(10, 2)
			var costs := PackedFloat32Array()
			for i in range(-40, 21):
				for j in range(-45, 6):
					for k in range(-12, 13):
						up.rotation = u0 + i * 0.05
						lo.rotation = l0 + j * 0.05
						hd.rotation = h0 + k * 0.1
						var gm := spr.global_transform * me
						var gt := spr.global_transform * tip
						var gh := hd.global_position
						var cost := gm.distance_to(lips)
						cost += maxf(0.0, 42.0 - gh.distance_to(lips)) * 2.0     # keep the fist off the face
						cost += maxf(0.0, lips.y + 22.0 - gh.y) * 1.5          # hand below the mouth (in front of the chin)
						cost += maxf(0.0, lips.x + 20.0 - gt.x) * 1.0           # lit end pointing away (forward)
						costs.append(cost)
			total[bt + p.name] = costs
	for bt in ["Male", "Female"]:
		var keys := total.keys().filter(func(kk): return String(kk).begins_with(bt))
		var n := (total[keys[0]] as PackedFloat32Array).size()
		var best_i := 0
		var best_c := 1e18
		for c in n:
			var sm := 0.0
			var w := 0.0
			for key in keys:
				sm += total[key][c]
				w = maxf(w, total[key][c])
			sm += w * 2.0
			if sm < best_c:
				best_c = sm
				best_i = c
		var i := best_i / (51 * 25) - 40
		var j := (best_i / 25) % 51 - 45
		var k := best_i % 25 - 12
		print("POSE %s upper %.2f lower %.2f hand %.2f" % [bt, i * 0.05, j * 0.05, k * 0.1])
		for key in keys:
			print("   %-24s %.1f" % [key, total[key][best_i]])
	get_tree().quit()
