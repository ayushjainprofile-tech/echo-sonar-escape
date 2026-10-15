extends Node2D
# ECHO - Sonar Escape  (single-script Godot 4 game, no external assets)
# You are blind. Ping to see the maze... but every ping is heard by the hunters.
# Move: WASD / Arrow keys   Ping: SPACE or Mouse Click   Start / Continue: ENTER

const COLS := 23
const ROWS := 13
const TS := 44.0
const OX := 70.0
const OY := 58.0

var size := Vector2(1152, 648)
var state := "menu"        # menu, play, clear, over
var walls := PackedByteArray()
var reveal := PackedFloat32Array()
var cells: Array = []
var far_cells: Array = []
var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var player := Vector2.ZERO
var exit_tile := Vector2i(COLS - 2, ROWS - 2)
var exit_vis := 0.0
var hunters: Array = []
var shards: Array = []
var rings: Array = []
var particles: Array = []

var level := 1
var score := 0
var best := 0
var lives := 3
var total_shards := 0
var level_t := 0.0
var ping_cd := 0.0
var invuln := 0.0
var shake := 0.0
var over_t := 0.0
var clear_bonus := 0
var new_best := false
var font: Font
var sfx := {}
var voices: Array = []
var voice_i := 0

func _ready():
	randomize()
	size = get_viewport_rect().size
	font = ThemeDB.fallback_font
	load_best()
	setup_audio()

# ---------------- audio (generated in code) ----------------
func make_tone(freq: float, dur: float, vol: float = 0.35, sweep: float = 0.0) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var ph := 0.0
	for i in n:
		var t := float(i) / rate
		var env := 1.0 - float(i) / n
		ph += TAU * (freq + sweep * t) / rate
		var v := sin(ph) * vol * env
		data.encode_s16(i * 2, int(v * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.data = data
	return s

func setup_audio():
	sfx["ping"] = make_tone(720.0, 0.45, 0.3, -900.0)
	sfx["shard"] = make_tone(980.0, 0.18, 0.35, 700.0)
	sfx["hit"] = make_tone(130.0, 0.35, 0.55, -80.0)
	sfx["clear"] = make_tone(440.0, 0.6, 0.4, 500.0)
	sfx["over"] = make_tone(110.0, 0.8, 0.5, -60.0)
	sfx["alert"] = make_tone(300.0, 0.15, 0.25, 200.0)
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		voices.append(p)

func play_sfx(n: String):
	var p: AudioStreamPlayer = voices[voice_i % voices.size()]
	voice_i += 1
	p.stream = sfx[n]
	p.play()

func load_best():
	if FileAccess.file_exists("user://echo_best.save"):
		var f := FileAccess.open("user://echo_best.save", FileAccess.READ)
		if f:
			best = f.get_32()

func save_best():
	var f := FileAccess.open("user://echo_best.save", FileAccess.WRITE)
	if f:
		f.store_32(best)

# ---------------- helpers ----------------
func tile_center(t: Vector2i) -> Vector2:
	return Vector2(OX + (t.x + 0.5) * TS, OY + (t.y + 0.5) * TS)

func world_to_tile(p: Vector2) -> Vector2i:
	return Vector2i(floori((p.x - OX) / TS), floori((p.y - OY) / TS))

func in_bounds(t: Vector2i) -> bool:
	return t.x >= 0 and t.x < COLS and t.y >= 0 and t.y < ROWS

func is_wall_at(p: Vector2) -> bool:
	var t := world_to_tile(p)
	if not in_bounds(t):
		return true
	return walls[t.y * COLS + t.x] == 1

func blocked(p: Vector2, r: float = 9.0) -> bool:
	return is_wall_at(p + Vector2(r, r)) or is_wall_at(p + Vector2(-r, r)) or is_wall_at(p + Vector2(r, -r)) or is_wall_at(p + Vector2(-r, -r))

func bfs(target: Vector2i) -> PackedInt32Array:
	var d := PackedInt32Array()
	d.resize(COLS * ROWS)
	d.fill(-1)
	var q: Array = [target]
	d[target.y * COLS + target.x] = 0
	var i := 0
	while i < q.size():
		var c: Vector2i = q[i]
		i += 1
		var cd := d[c.y * COLS + c.x]
		for dd in dirs:
			var n: Vector2i = c + dd
			if in_bounds(n):
				var idx := n.y * COLS + n.x
				if walls[idx] == 0 and d[idx] == -1:
					d[idx] = cd + 1
					q.append(n)
	return d

# ---------------- level generation ----------------
func gen_maze():
	walls.resize(COLS * ROWS)
	walls.fill(1)
	reveal.resize(COLS * ROWS)
	reveal.fill(0.0)
	var dirs2: Array[Vector2i] = [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]
	var stack: Array = [Vector2i(1, 1)]
	walls[1 * COLS + 1] = 0
	while stack.size() > 0:
		var c: Vector2i = stack[stack.size() - 1]
		var opts: Array = []
		for dv in dirs2:
			var n: Vector2i = c + dv
			if n.x > 0 and n.x < COLS - 1 and n.y > 0 and n.y < ROWS - 1 and walls[n.y * COLS + n.x] == 1:
				opts.append(dv)
		if opts.is_empty():
			stack.pop_back()
		else:
			var pick: Vector2i = opts[randi() % opts.size()]
			var nn: Vector2i = c + pick
			var mid := Vector2i(c.x + pick.x / 2, c.y + pick.y / 2)
			walls[mid.y * COLS + mid.x] = 0
			walls[nn.y * COLS + nn.x] = 0
			stack.append(nn)
	# open a few extra passages so the maze has loops
	for k in 26:
		var x := randi_range(1, COLS - 2)
		var y := randi_range(1, ROWS - 2)
		if walls[y * COLS + x] == 1 and ((x % 2 == 1) != (y % 2 == 1)):
			walls[y * COLS + x] = 0
	cells.clear()
	for y in range(1, ROWS, 2):
		for x in range(1, COLS, 2):
			cells.append(Vector2i(x, y))

func new_level():
	gen_maze()
	rings.clear()
	particles.clear()
	hunters.clear()
	shards.clear()
	player = tile_center(Vector2i(1, 1))
	exit_vis = 0.0
	level_t = 0.0
	ping_cd = 0.0
	invuln = 1.5
	var sf := bfs(Vector2i(1, 1))
	var far: Array = []
	var mid: Array = []
	for c in cells:
		var cv: Vector2i = c
		if cv == exit_tile or cv == Vector2i(1, 1):
			continue
		var dd := sf[cv.y * COLS + cv.x]
		if dd >= 16:
			far.append(cv)
		if dd >= 8:
			mid.append(cv)
	far.shuffle()
	mid.shuffle()
	if far.is_empty():
		far = mid.duplicate()
	far_cells = far
	var n_s := mini(2 + level, 7)
	var n_h := mini(1 + level / 2, 5)
	total_shards = n_s
	for i in n_s:
		shards.append({"t": mid[i % mid.size()], "vis": 0.0})
	for i in n_h:
		var h := {"p": tile_center(far[i % far.size()]), "field": PackedInt32Array(), "mode": "wander", "wait": 1.0, "vis": 0.0, "think": 0.0}
		pick_wander(h)
		hunters.append(h)

func start_game():
	level = 1
	score = 0
	lives = 3
	new_best = false
	new_level()
	state = "play"
	play_sfx("clear")

func pick_wander(h: Dictionary):
	var c: Vector2i = cells[randi() % cells.size()]
	h["field"] = bfs(c)
	h["mode"] = "wander"
	h["wait"] = randf_range(0.4, 1.4)

# ---------------- input ----------------
func do_ping():
	if ping_cd > 0.0:
		return
	ping_cd = 0.9
	rings.append({"o": player, "r": 0.0})
	play_sfx("ping")
	var ptile := world_to_tile(player)
	for h in hunters:
		var hp: Vector2 = h["p"]
		if hp.distance_to(player) < 520.0 and h["mode"] != "chase":
			h["field"] = bfs(ptile)
			h["mode"] = "alert"
			h["wait"] = 1.6

func _input(event):
	var confirm := false
	var click := false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		confirm = true
		click = true
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER or event.keycode == KEY_SPACE:
			confirm = true
	if not confirm:
		return
	if state == "play":
		do_ping()
	elif state == "menu":
		start_game()
	elif state == "clear" and over_t > 0.5:
		level += 1
		new_level()
		state = "play"
	elif state == "over" and over_t > 0.8:
		start_game()

# ---------------- main loop ----------------
func _process(delta):
	for i in range(particles.size() - 1, -1, -1):
		var q: Dictionary = particles[i]
		q["p"] += q["v"] * delta
		q["v"] *= 0.95
		q["l"] -= delta
		if q["l"] <= 0.0:
			particles.remove_at(i)
	shake = maxf(0.0, shake - delta * 40.0)
	if state == "clear" or state == "over":
		over_t += delta
	if state == "play":
		update_game(delta)
	queue_redraw()

func burst(pos: Vector2, col: Color, n: int):
	for i in n:
		var a := randf() * TAU
		var sp := randf_range(40.0, 260.0)
		var l := randf_range(0.3, 0.9)
		particles.append({"p": pos, "v": Vector2(cos(a), sin(a)) * sp, "l": l, "m": l, "c": col})

func ring_hits(pos: Vector2) -> bool:
	for rg in rings:
		var o: Vector2 = rg["o"]
		var r: float = rg["r"]
		if absf(pos.distance_to(o) - r) < 26.0:
			return true
	return false

func update_game(delta: float):
	level_t += delta
	ping_cd = maxf(0.0, ping_cd - delta)
	invuln = maxf(0.0, invuln - delta)

	# player movement (axis-separated for wall sliding)
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		dir.x += 1.0
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		dir.y += 1.0
	if dir != Vector2.ZERO:
		dir = dir.normalized()
	var nx := player + Vector2(dir.x * 150.0 * delta, 0.0)
	if not blocked(nx):
		player = nx
	var ny := player + Vector2(0.0, dir.y * 150.0 * delta)
	if not blocked(ny):
		player = ny

	# sonar rings
	for rg in rings:
		rg["r"] += 430.0 * delta
	for i in range(rings.size() - 1, -1, -1):
		var rr: float = rings[i]["r"]
		if rr > 360.0:
			rings.remove_at(i)

	# reveal decay + updates
	for i in reveal.size():
		reveal[i] = maxf(0.0, reveal[i] - delta * 0.45)
	for y in ROWS:
		for x in COLS:
			var idx := y * COLS + x
			if walls[idx] == 1:
				var c := tile_center(Vector2i(x, y))
				var dp := c.distance_to(player)
				if dp < 80.0:
					reveal[idx] = maxf(reveal[idx], 0.5 * (1.0 - dp / 80.0))
				if rings.size() > 0 and ring_hits(c):
					reveal[idx] = 1.0
	exit_vis = maxf(0.0, exit_vis - delta * 0.45)
	if ring_hits(tile_center(exit_tile)):
		exit_vis = 1.0
	for s in shards:
		s["vis"] = maxf(0.0, float(s["vis"]) - delta * 0.45)
		if ring_hits(tile_center(s["t"])):
			s["vis"] = 1.0
	for h in hunters:
		h["vis"] = maxf(0.0, float(h["vis"]) - delta * 0.6)
		var hp0: Vector2 = h["p"]
		if ring_hits(hp0):
			h["vis"] = 1.0

	# hunters
	for h in hunters:
		update_hunter(h, delta)
		var hp: Vector2 = h["p"]
		if invuln <= 0.0 and hp.distance_to(player) < 20.0:
			hit_player()
			return

	# shards
	for i in range(shards.size() - 1, -1, -1):
		var sc := tile_center(shards[i]["t"])
		if sc.distance_to(player) < 20.0:
			shards.remove_at(i)
			score += 100
			burst(sc, Color(0.5, 1.0, 0.9), 20)
			play_sfx("shard")

	# exit
	if shards.is_empty() and tile_center(exit_tile).distance_to(player) < 22.0:
		clear_bonus = 150 + maxi(0, 90 - int(level_t)) * 5
		score += clear_bonus
		state = "clear"
		over_t = 0.0
		burst(player, Color(0.3, 1.0, 0.6), 50)
		play_sfx("clear")
		if score > best:
			best = score
			new_best = true
			save_best()

func update_hunter(h: Dictionary, delta: float):
	var p: Vector2 = h["p"]
	var mode: String = h["mode"]
	var dpl := p.distance_to(player)
	if dpl < 130.0 and invuln <= 0.0:
		if mode != "chase":
			h["mode"] = "chase"
			h["think"] = 0.0
			mode = "chase"
			play_sfx("alert")
	elif mode == "chase" and dpl > 230.0:
		pick_wander(h)
		mode = "wander"
	if mode == "chase":
		h["think"] -= delta
		if h["think"] <= 0.0:
			h["think"] = 0.25
			h["field"] = bfs(world_to_tile(player))
	var f: PackedInt32Array = h["field"]
	var tile := world_to_tile(p)
	if not in_bounds(tile):
		return
	var cd := f[tile.y * COLS + tile.x]
	var spd := 60.0 + level * 4.0
	if mode == "alert":
		spd = 105.0 + level * 5.0
	elif mode == "chase":
		spd = minf(122.0 + level * 4.0, 142.0)
	if cd < 0:
		pick_wander(h)
		return
	if cd == 0:
		h["wait"] -= delta
		if h["wait"] <= 0.0:
			pick_wander(h)
		return
	var best_t := tile
	var best_d := cd
	for dd in dirs:
		var n: Vector2i = tile + dd
		if in_bounds(n):
			var nd := f[n.y * COLS + n.x]
			if nd >= 0 and nd < best_d:
				best_d = nd
				best_t = n
	h["p"] = p.move_toward(tile_center(best_t), spd * delta)

func hit_player():
	lives -= 1
	shake = 16.0
	play_sfx("hit")
	burst(player, Color(1.0, 0.3, 0.3), 40)
	if lives <= 0:
		state = "over"
		over_t = 0.0
		play_sfx("over")
		if score > best:
			best = score
			new_best = true
		save_best()
		return
	player = tile_center(Vector2i(1, 1))
	invuln = 2.5
	for h in hunters:
		var c: Vector2i = far_cells[randi() % far_cells.size()]
		h["p"] = tile_center(c)
		pick_wander(h)

# ---------------- drawing ----------------
func label(s: String, y: float, sz: int, col: Color):
	draw_string(font, Vector2(0, y), s, HORIZONTAL_ALIGNMENT_CENTER, size.x, sz, col)

func _draw():
	var off := Vector2.ZERO
	if shake > 0.0:
		off = Vector2(randf_range(-shake, shake), randf_range(-shake, shake)) * 0.5
	draw_set_transform(off, 0.0, Vector2.ONE)
	draw_rect(Rect2(Vector2(-40, -40), size + Vector2(80, 80)), Color(0.10, 0.04, 0.12))
	if state == "menu":
		draw_menu()
	else:
		draw_world()
		draw_hud()
		if state == "clear":
			draw_clear()
		elif state == "over":
			draw_over()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func draw_world():
	# walls revealed by sonar
	for y in ROWS:
		for x in COLS:
			var idx := y * COLS + x
			var a := reveal[idx]
			if walls[idx] == 1 and a > 0.02:
				var r := Rect2(Vector2(OX + x * TS, OY + y * TS), Vector2(TS, TS))
				draw_rect(r, Color(1.0, 0.35, 0.5, a * 0.22))
				draw_rect(r, Color(1.0, 0.6, 0.4, a * 0.9), false, 1.5)

	# sonar rings
	for rg in rings:
		var o: Vector2 = rg["o"]
		var r: float = rg["r"]
		var a := clampf(1.0 - r / 360.0, 0.0, 1.0)
		draw_arc(o, r, 0.0, TAU, 72, Color(1.0, 0.85, 0.3, a * 0.8), 2.5)
		draw_arc(o, r * 0.97, 0.0, TAU, 72, Color(1.0, 0.85, 0.3, a * 0.25), 6.0)

	var tm := Time.get_ticks_msec() / 1000.0

	# exit
	var ec := tile_center(exit_tile)
	if shards.is_empty():
		var pulse := 0.6 + 0.4 * sin(tm * 4.0)
		draw_rect(Rect2(ec - Vector2(18, 18), Vector2(36, 36)), Color(0.2, 1.0, 0.5, 0.3 * pulse))
		draw_rect(Rect2(ec - Vector2(18, 18), Vector2(36, 36)), Color(0.3, 1.0, 0.6, pulse), false, 3.0)
		draw_arc(ec, 26.0 + 4.0 * sin(tm * 4.0), 0.0, TAU, 32, Color(0.3, 1.0, 0.6, 0.5 * pulse), 2.0)
	elif exit_vis > 0.02:
		draw_rect(Rect2(ec - Vector2(16, 16), Vector2(32, 32)), Color(0.5, 0.6, 0.6, exit_vis * 0.5), false, 2.0)

	# shards
	for s in shards:
		var sp := tile_center(s["t"])
		var dd := sp.distance_to(player)
		var a := maxf(float(s["vis"]), clampf(1.0 - dd / 110.0, 0.0, 1.0))
		if a > 0.02:
			var bob := sin(tm * 3.0 + sp.x) * 2.0
			var c := sp + Vector2(0, bob)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -11), c + Vector2(8, 0), c + Vector2(0, 11), c + Vector2(-8, 0)]), Color(0.5, 1.0, 0.9, a))
			draw_circle(c, 15.0, Color(0.5, 1.0, 0.9, a * 0.15))

	# hunters
	for h in hunters:
		var hp: Vector2 = h["p"]
		var mode: String = h["mode"]
		var dd := hp.distance_to(player)
		var a := maxf(float(h["vis"]), clampf(1.0 - dd / 150.0, 0.0, 1.0) * 0.85)
		if mode == "chase":
			a = maxf(a, 0.6)
		if a > 0.02:
			draw_circle(hp, 24.0, Color(1.0, 0.1, 0.15, a * 0.18))
			draw_circle(hp, 13.0, Color(0.9, 0.1, 0.2, a))
			draw_circle(hp + Vector2(-5, -3), 3.0, Color(1, 1, 1, a))
			draw_circle(hp + Vector2(5, -3), 3.0, Color(1, 1, 1, a))
			if mode == "chase":
				draw_string(font, hp + Vector2(-4, -22), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 0.3, 0.3, a))

	# particles
	for q in particles:
		var a: float = q["l"] / q["m"]
		var c: Color = q["c"]
		c.a = a
		draw_circle(q["p"], 3.0 * a + 1.0, c)

	# player
	if state == "play" or state == "clear":
		var show := true
		if invuln > 0.0 and int(tm * 16.0) % 2 == 0:
			show = false
		if show:
			draw_circle(player, 18.0, Color(1.0, 0.85, 0.3, 0.12))
			draw_circle(player, 8.0, Color(1, 1, 1))
			draw_arc(player, 11.0, 0.0, TAU, 20, Color(1.0, 0.85, 0.3, 0.8), 2.0)

	# danger vignette
	var nearest := 9999.0
	for h in hunters:
		var hp2: Vector2 = h["p"]
		nearest = minf(nearest, hp2.distance_to(player))
	if nearest < 220.0 and state == "play":
		var da := (1.0 - nearest / 220.0) * (0.10 + 0.05 * sin(tm * 10.0))
		draw_rect(Rect2(Vector2(-40, -40), size + Vector2(80, 80)), Color(1.0, 0.0, 0.0, da))

func draw_hud():
	draw_string(font, Vector2(24, 40), "SECTOR %d" % level, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(1.0, 0.6, 0.45))
	draw_string(font, Vector2(190, 40), "SHARDS %d/%d" % [total_shards - shards.size(), total_shards], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.5, 1.0, 0.9))
	draw_string(font, Vector2(380, 40), "SCORE %d" % score, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 1, 1))
	draw_string(font, Vector2(560, 40), "BEST %d" % best, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.8, 0.6, 0.7))
	for i in lives:
		draw_circle(Vector2(760 + i * 26, 32), 8.0, Color(1.0, 0.3, 0.4))
	# ping meter
	var w := 140.0
	var fill := 1.0 - ping_cd / 0.9
	draw_rect(Rect2(Vector2(930, 22), Vector2(w, 14)), Color(0.3, 0.15, 0.25, 0.7))
	draw_rect(Rect2(Vector2(930, 22), Vector2(w * fill, 14)), Color(1.0, 0.85, 0.3, 0.9))
	draw_string(font, Vector2(1080, 35), "PING", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.65, 0.7))
	if shards.is_empty() and state == "play":
		label("ALL SHARDS COLLECTED - FIND THE EXIT", 644.0, 18, Color(0.3, 1.0, 0.6))
	elif level <= 2 and state == "play":
		label("SPACE / CLICK = sonar ping   (hunters hear it!)", 644.0, 16, Color(0.7, 0.55, 0.65))

func draw_menu():
	var tm := Time.get_ticks_msec() / 1000.0
	var center := Vector2(size.x / 2.0, 250.0)
	for k in 3:
		var r := fmod(tm * 110.0 + k * 140.0, 420.0)
		draw_arc(center, r, 0.0, TAU, 72, Color(1.0, 0.85, 0.3, 0.35 * (1.0 - r / 420.0)), 2.5)
	label("E C H O", 255, 110, Color(1.0, 0.6, 0.45))
	label("You are blind. Sound is your only light.", 320, 28, Color(1.0, 0.92, 0.85))
	label("But everything... hears.", 355, 26, Color(1.0, 0.35, 0.5))
	label("WASD / Arrows = move        SPACE / Click = sonar ping", 430, 22, Color(0.85, 0.7, 0.8))
	label("Collect all golden shards, then reach the green exit.", 465, 22, Color(0.85, 0.7, 0.8))
	label("Every ping reveals the maze - and tells the hunters where you are.", 500, 22, Color(0.85, 0.7, 0.8))
	label("BEST SCORE: %d" % best, 550, 26, Color(0.5, 1.0, 0.9))
	if int(tm * 2.0) % 2 == 0:
		label("Press ENTER or CLICK to begin", 610, 30, Color(1, 1, 1))

func draw_clear():
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6))
	label("SECTOR %d CLEARED" % level, 250, 70, Color(0.3, 1.0, 0.6))
	label("Bonus: +%d     Score: %d" % [clear_bonus, score], 330, 34, Color(1, 1, 1))
	if new_best:
		label("NEW BEST SCORE!", 385, 30, Color(0.5, 1.0, 0.9))
	if over_t > 0.5 and int(Time.get_ticks_msec() / 500) % 2 == 0:
		label("Press ENTER for the next sector (more hunters)", 480, 28, Color(1, 1, 1))

func draw_over():
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.65))
	label("SIGNAL LOST", 250, 80, Color(1.0, 0.3, 0.35))
	label("Reached Sector %d     Score: %d" % [level, score], 330, 34, Color(1, 1, 1))
	if new_best:
		label("NEW BEST SCORE!", 385, 30, Color(0.5, 1.0, 0.9))
	else:
		label("Best: %d" % best, 385, 28, Color(0.85, 0.7, 0.8))
	if over_t > 0.8 and int(Time.get_ticks_msec() / 500) % 2 == 0:
		label("Press ENTER or CLICK to try again", 480, 28, Color(1, 1, 1))
