#!/usr/bin/env python3
"""Pixel-art generator for the new zombie, slime, spider and boss sprites.

Pure standard library (zlib + struct), so no image package is needed.
Run it from anywhere; it writes the PNG files next to this script:

    python3 generate_enemy_sprites.py

Output layout:
- characters/*_16x16_strip8.png  8-frame strips, same format as the existing sheets
- characters/*_64x64.png         single-frame bosses, same format as big_jelly_64x64.png
- projectile/*_8x8.png           single-frame projectiles
"""
import math
import os
import struct
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))

FRAME_COUNT = 8
## Rows from this index down are legs; they swing sideways while walking.
LEG_ROW = 12

PALETTE = {
	'g': (123, 179, 79, 255),   # zombie green
	'l': (166, 214, 107, 255),  # light green
	'd': (74, 122, 51, 255),    # dark green
	'p': (126, 90, 168, 255),   # bloat purple
	'P': (176, 143, 214, 255),  # light purple
	'y': (200, 214, 74, 255),   # sickly yellow
	'r': (107, 74, 46, 255),    # rags
	'b': (58, 40, 24, 255),     # dark brown
	'a': (67, 214, 166, 255),   # acid teal
	'A': (166, 255, 216, 255),  # acid highlight
	't': (24, 110, 96, 255),    # acid rim
	'x': (42, 36, 48, 255),     # spider black
	'X': (77, 69, 88, 255),     # spider grey
	'Y': (128, 118, 146, 255),   # spider leg grey
	'w': (232, 226, 200, 255),  # bone white
	'e': (223, 233, 240, 255),  # web white
	'R': (224, 48, 46, 255),    # red eyes
	'k': (27, 20, 32, 255),     # black
	'S': (96, 150, 220, 255),   # slime puddle blue
	's': (56, 92, 150, 255),    # slime puddle rim
	'L': (190, 220, 250, 255),  # slime puddle highlight
}
OUTLINE = (20, 14, 26, 255)
TRANSPARENT = (0, 0, 0, 0)


def new_canvas(width, height):
	return [[None] * width for _ in range(height)]


def put(canvas, x, y, color):
	if 0 <= y < len(canvas) and 0 <= x < len(canvas[0]):
		canvas[y][x] = color


def ellipse(canvas, cx, cy, rx, ry, color):
	for y in range(len(canvas)):
		for x in range(len(canvas[0])):
			dx = (x + 0.5 - cx) / rx
			dy = (y + 0.5 - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				canvas[y][x] = color


def thick_line(canvas, x0, y0, x1, y1, thickness, color):
	radius = thickness / 2.0
	length_sq = max((x1 - x0) ** 2 + (y1 - y0) ** 2, 1e-9)
	for y in range(len(canvas)):
		for x in range(len(canvas[0])):
			px = x + 0.5
			py = y + 0.5
			t = max(0.0, min(1.0, ((px - x0) * (x1 - x0) + (py - y0) * (y1 - y0)) / length_sq))
			nearest_x = x0 + t * (x1 - x0)
			nearest_y = y0 + t * (y1 - y0)
			if (px - nearest_x) ** 2 + (py - nearest_y) ** 2 <= radius * radius:
				canvas[y][x] = color


def add_outline(canvas):
	"""Adds a 1px dark outline around the silhouette."""
	height = len(canvas)
	width = len(canvas[0])
	result = [row[:] for row in canvas]
	for y in range(height):
		for x in range(width):
			if canvas[y][x] is not None:
				continue
			for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
				nx = x + dx
				ny = y + dy
				if 0 <= nx < width and 0 <= ny < height and canvas[ny][nx] is not None:
					result[y][x] = OUTLINE
					break
	return result


def from_rows(rows):
	"""Builds a 16x16 canvas from palette-key rows, each centred horizontally. '.' is transparent."""
	assert len(rows) == 16, 'expected 16 rows, got %d' % len(rows)
	canvas = new_canvas(16, 16)
	for y, text in enumerate(rows):
		assert len(text) <= 16, text
		left = (16 - len(text)) // 2
		for i, key in enumerate(text):
			if key != '.':
				canvas[y][left + i] = PALETTE[key]
	return canvas


def walk_frames(base):
	"""Eight frames: whole body bobs, legs swing left and right."""
	frames = []
	for frame in range(FRAME_COUNT):
		bob = -1 if frame in (2, 6) else 0
		swing = (0, 1, 0, -1)[frame % 4]
		canvas = new_canvas(16, 16)
		for y in range(16):
			for x in range(16):
				color = base[y][x]
				if color is None:
					continue
				new_x = x
				if y >= LEG_ROW:
					new_x = x + swing if x < 8 else x - swing
				put(canvas, new_x, y + bob, color)
		frames.append(add_outline(canvas))
	return frames


## Left-side legs as (anchor, knee, foot) in 16x16 pixel space, top-down.
## Group 'A' and 'B' take turns lifting during the walk; the right side mirrors them.
SPIDER_LEGS = [
	((5.0, 4.5), (3.0, 2.0), (2.0, 0.5), 'A'),
	((5.0, 6.5), (2.5, 6.0), (1.0, 5.0), 'B'),
	((5.0, 8.5), (2.5, 9.5), (1.0, 10.5), 'A'),
	((5.0, 10.5), (3.0, 13.0), (2.0, 14.5), 'B'),
]


def spider_frames(body, abdomen, leg_color, eye_color, fang_color, marks=None):
	"""Top-down spider: head and fangs up top, round abdomen below, legs alternate groups while walking.
	Frame 0 is used as the dead spider lying on its back."""
	frames = []
	for frame in range(FRAME_COUNT):
		step = math.sin(frame / FRAME_COUNT * 2 * math.pi)
		canvas = new_canvas(16, 16)
		for side in (0, 1):
			for anchor, knee, foot, group in SPIDER_LEGS:
				lift = step if group == 'A' else -step
				points = [anchor, (knee[0], knee[1] + 0.8 * lift), (foot[0], foot[1] + 1.0 * lift)]
				if side == 1:
					points = [(16.0 - x, y) for x, y in points]
				thick_line(canvas, points[0][0], points[0][1], points[1][0], points[1][1], 1.0, leg_color)
				thick_line(canvas, points[1][0], points[1][1], points[2][0], points[2][1], 1.0, leg_color)
		bob = 0.4 * step
		ellipse(canvas, 7.5, 11.0 + bob, 3.2, 3.0, abdomen)
		ellipse(canvas, 7.5, 5.0 + bob, 2.4, 2.2, body)
		if marks is not None:
			for x, y in ((7, 10), (8, 10), (7, 12), (8, 12)):
				put(canvas, x, y + round(bob), marks)
		put(canvas, 6, 3, eye_color)
		put(canvas, 9, 3, eye_color)
		put(canvas, 7, 4, fang_color)
		put(canvas, 8, 4, fang_color)
		frames.append(add_outline(canvas))
	return frames


## Near side legs front to back as (anchor x, foot x, knee height above the ground), side view facing right.
## Outer legs arch higher; far side legs are drawn from the same list, reaching less.
CRAWL_LEGS = [(10.0, 15.0, 10.0), (9.5, 12.5, 9.0), (8.5, 3.5, 10.0), (8.0, 0.5, 11.0)]
CRAWL_GROUND = 15


def line_pixels(x0, y0, x1, y1):
	"""1px Bresenham line between rounded points, so legs stay thin and readable at 16x16."""
	x0, y0, x1, y1 = round(x0), round(y0), round(x1), round(y1)
	points = set()
	dx = abs(x1 - x0)
	dy = -abs(y1 - y0)
	sx = 1 if x0 < x1 else -1
	sy = 1 if y0 < y1 else -1
	error = dx + dy
	while True:
		points.add((x0, y0))
		if x0 == x1 and y0 == y1:
			return points
		e2 = 2 * error
		if e2 >= dy:
			error += dy
			x0 += sx
		if e2 <= dx:
			error += dx
			y0 += sy


def spider_crawl_pose(t, moving, body, abdomen, leg_color, far_color, eye_color, fang_color, marks):
	"""Side view spider, facing right. t is the 0..1 gait phase; legs step in two alternating groups of four."""
	# whole pixel body lift halfway through each step keeps the shapes clean
	lift_body = -1 if moving and math.sin(4 * math.pi * t) > 0.5 else 0
	if not moving and t >= 0.5:
		lift_body = -1

	def leg(index, near):
		anchor_x, foot_x, knee_height = CRAWL_LEGS[index]
		phase = t + (0.0 if (index % 2 == 0) == near else 0.5)
		# lifted foot swings forward, planted foot pushes back
		swing = 1.5 * math.sin(2 * math.pi * phase) if moving else 0.0
		lift = 1.5 * max(0.0, math.cos(2 * math.pi * phase)) if moving else 0.0
		outward = 1 if foot_x > anchor_x else -1
		if not near:
			foot_x -= 1.5 * outward
			knee_height -= 1.0
		foot = (foot_x + swing, CRAWL_GROUND - lift)
		anchor = (anchor_x, 11 + lift_body)
		knee = (anchor_x + (0.35 if outward > 0 else 0.6) * (foot[0] - anchor_x), CRAWL_GROUND - knee_height + lift_body - 0.5 * lift)
		return line_pixels(*anchor, *knee) | line_pixels(*knee, *foot)

	body_canvas = new_canvas(16, 16)
	ellipse(body_canvas, 5.0, 10.5 + lift_body, 3.8, 2.9, abdomen)
	if marks is not None:
		put(body_canvas, 3, 9 + lift_body, marks)
		put(body_canvas, 4, 9 + lift_body, marks)
		put(body_canvas, 3, 10 + lift_body, marks)
	ellipse(body_canvas, 10.5, 11.5 + lift_body, 2.4, 1.8, body)
	put(body_canvas, 11, 11 + lift_body, eye_color)
	put(body_canvas, 12, 11 + lift_body, eye_color)
	put(body_canvas, 12, 13 + lift_body, fang_color)
	body_canvas = add_outline(body_canvas)
	# legs arch over the body and reach the ground below it; the body covers their roots
	canvas = new_canvas(16, 16)
	for near, color in ((False, far_color), (True, leg_color)):
		for i in range(4):
			for x, y in leg(i, near):
				put(canvas, x, y, color)
	for y in range(16):
		for x in range(16):
			if body_canvas[y][x] is not None:
				canvas[y][x] = body_canvas[y][x]
	return canvas


def spider_crawl_frames(body, abdomen, leg_color, far_color, eye_color, fang_color, marks=None):
	"""Frames 0-1 idle (breathing), 2-7 one crawl cycle; same idle/walk layout as the other strips."""
	frames = [spider_crawl_pose(i / 2, False, body, abdomen, leg_color, far_color, eye_color, fang_color, marks) for i in range(2)]
	frames += [spider_crawl_pose(i / 6, True, body, abdomen, leg_color, far_color, eye_color, fang_color, marks) for i in range(6)]
	return frames


def acid_spit_projectile():
	canvas = new_canvas(8, 8)
	ellipse(canvas, 4, 4, 3.2, 3.2, PALETTE['a'])
	ellipse(canvas, 3, 3, 1.0, 1.0, PALETTE['A'])
	return add_outline(canvas)


def web_projectile():
	canvas = new_canvas(8, 8)
	ellipse(canvas, 4, 4, 3.0, 3.0, PALETTE['e'])
	thick_line(canvas, 1, 4, 7, 4, 0.7, PALETTE['w'])
	thick_line(canvas, 4, 1, 4, 7, 0.7, PALETTE['w'])
	return add_outline(canvas)


def giant_zombie_pose(stride=0.0, bob=0.0, hand_y=48.0):
	"""64x64 brute pose. stride swings the legs, bob lifts the body, hand_y is where the arms reach."""
	canvas = new_canvas(64, 64)
	thick_line(canvas, 24 + 4 * stride, 50, 22 + 4 * stride, 62, 7, PALETTE['b'])
	thick_line(canvas, 40 - 4 * stride, 50, 42 - 4 * stride, 62, 7, PALETTE['b'])
	thick_line(canvas, 16, 30 + bob, 6, hand_y, 8, PALETTE['g'])
	thick_line(canvas, 48, 30 + bob, 58, hand_y, 8, PALETTE['g'])
	ellipse(canvas, 32, 38 + bob, 19, 15, PALETTE['g'])
	ellipse(canvas, 32, 47 + bob, 17, 9, PALETTE['r'])
	ellipse(canvas, 32, 17 + bob, 11, 11, PALETTE['g'])
	ellipse(canvas, 28, 11 + bob, 5, 3, PALETTE['l'])
	ellipse(canvas, 26, 17 + bob, 1.6, 1.6, PALETTE['R'])
	ellipse(canvas, 38, 17 + bob, 1.6, 1.6, PALETTE['R'])
	thick_line(canvas, 26, 25 + bob, 38, 25 + bob, 2, PALETTE['k'])
	thick_line(canvas, 26, 38 + bob, 30, 44 + bob, 1, PALETTE['b'])
	thick_line(canvas, 36, 36 + bob, 38, 42 + bob, 1, PALETTE['b'])
	return add_outline(canvas)


def giant_zombie_frames():
	"""Walk x4 (legs swing, body bobs), attack x3 (arms raise, slam down, recover)."""
	frames = []
	for frame in range(4):
		phase = frame / 4 * 2 * math.pi
		frames.append(giant_zombie_pose(stride=math.sin(phase), bob=-1.0 * abs(math.sin(phase))))
	frames.append(giant_zombie_pose(hand_y=6.0))
	frames.append(giant_zombie_pose(bob=2.0, hand_y=60.0))
	frames.append(giant_zombie_pose(hand_y=34.0))
	return frames


BROODMOTHER_LEG_ANGLES = (-150, -120, -95, -70, 70, 95, 120, 150)


def broodmother_pose(front_left=-150, front_right=150, spread=0.0, step=0.0):
	"""64x64 spider pose. front legs set the forelimb swing, spread pushes all legs outwards, step wobbles them."""
	canvas = new_canvas(64, 64)
	center_x = 32.0
	center_y = 36.0
	for index, angle_deg in enumerate(BROODMOTHER_LEG_ANGLES):
		if index == 0:
			angle_deg = front_left
		elif index == 7:
			angle_deg = front_right
		wobble = 4.0 * step * (1 if index % 2 == 0 else -1)
		angle = math.radians(angle_deg + wobble)
		reach = 1.0 + 0.12 * spread
		knee_x = center_x + 20 * reach * math.cos(angle)
		knee_y = center_y + 18 * reach * math.sin(angle)
		foot_x = center_x + 29 * reach * math.cos(angle)
		foot_y = center_y + 27 * reach * math.sin(angle)
		thick_line(canvas, center_x + 10 * math.cos(angle), center_y + 10 * math.sin(angle), knee_x, knee_y, 3, PALETTE['X'])
		thick_line(canvas, knee_x, knee_y, foot_x, foot_y, 3, PALETTE['X'])
	ellipse(canvas, 32, 42, 16, 14, PALETTE['X'])
	ellipse(canvas, 32, 46, 5, 6, PALETTE['R'])
	ellipse(canvas, 26, 40, 1.5, 1.5, PALETTE['k'])
	ellipse(canvas, 38, 40, 1.5, 1.5, PALETTE['k'])
	ellipse(canvas, 32, 20, 9, 8, PALETTE['x'])
	for x, y in ((27, 17), (31, 15), (35, 15), (39, 17), (29, 21), (35, 21)):
		ellipse(canvas, x, y, 1.3, 1.3, PALETTE['R'])
	thick_line(canvas, 28, 26, 26, 31, 2, PALETTE['w'])
	thick_line(canvas, 36, 26, 38, 31, 2, PALETTE['w'])
	if spread > 0:
		for x, y in ((20, 46), (44, 46), (24, 52), (40, 52)):
			ellipse(canvas, x, y, 1.2, 1.2, PALETTE['a'])
	return add_outline(canvas)


def broodmother_frames():
	"""Idle x1, acid throw x3 (left foreleg whips forward), acid fan x3 (both forelegs raised and spread)."""
	frames = [broodmother_pose(step=0.0)]
	frames.append(broodmother_pose(front_left=-150))
	frames.append(broodmother_pose(front_left=-100))
	frames.append(broodmother_pose(front_left=-125))
	frames.append(broodmother_pose(front_left=-110, front_right=110, spread=0.5))
	frames.append(broodmother_pose(front_left=-100, front_right=100, spread=1.0))
	frames.append(broodmother_pose(front_left=-120, front_right=120, spread=0.5))
	return frames


def plague_mother_pose(left_tip=(6, 6), right_tip=(58, 6), glow=False, pulse=0.0):
	"""64x64 boss pose. left_tip and right_tip move the tentacles, glow lights the summon tips, pulse swells the eyes."""
	canvas = new_canvas(64, 64)
	thick_line(canvas, 14, 20, left_tip[0], left_tip[1], 3, PALETTE['a'])
	thick_line(canvas, 50, 20, right_tip[0], right_tip[1], 3, PALETTE['a'])
	thick_line(canvas, 32, 18, 32, 4, 3, PALETTE['a'])
	ellipse(canvas, left_tip[0], left_tip[1], 2, 2, PALETTE['A'])
	ellipse(canvas, right_tip[0], right_tip[1], 2, 2, PALETTE['A'])
	if glow:
		ellipse(canvas, 32, 4, 4, 4, PALETTE['y'])
	ellipse(canvas, 32, 38, 22, 20, PALETTE['p'])
	ellipse(canvas, 32, 47, 16, 9, PALETTE['P'])
	ellipse(canvas, 24, 28, 7, 4, PALETTE['P'])
	ellipse(canvas, 44, 46, 3, 3, PALETTE['y'])
	ellipse(canvas, 20, 46, 2, 2, PALETTE['y'])
	ellipse(canvas, 40, 30, 2, 2, PALETTE['y'])
	ellipse(canvas, 24, 34, 3.5 + pulse, 3.5 + pulse, PALETTE['R'])
	ellipse(canvas, 40, 34, 3.5 + pulse, 3.5 + pulse, PALETTE['R'])
	ellipse(canvas, 32, 27, 4, 4, PALETTE['R'])
	ellipse(canvas, 24, 34, 1.2, 1.2, PALETTE['k'])
	ellipse(canvas, 40, 34, 1.2, 1.2, PALETTE['k'])
	ellipse(canvas, 32, 27, 1.4, 1.4, PALETTE['k'])
	ellipse(canvas, 32, 48, 6, 3, PALETTE['k'])
	ellipse(canvas, 14, 56, 2, 3, PALETTE['a'])
	ellipse(canvas, 30, 58, 2, 4, PALETTE['a'])
	ellipse(canvas, 48, 57, 2, 3, PALETTE['a'])
	return add_outline(canvas)


def plague_mother_frames():
	"""Idle x2 (pulse), acid throw x3 (left tentacle whips out and down), summon x3 (tentacles lift and glow)."""
	frames = [plague_mother_pose(pulse=0.0), plague_mother_pose(pulse=0.8)]
	frames.append(plague_mother_pose(left_tip=(10, 2)))
	frames.append(plague_mother_pose(left_tip=(0, 30)))
	frames.append(plague_mother_pose(left_tip=(8, 12)))
	frames.append(plague_mother_pose(left_tip=(6, 0), right_tip=(58, 0), glow=True))
	frames.append(plague_mother_pose(left_tip=(4, 0), right_tip=(60, 0), glow=True, pulse=0.5))
	frames.append(plague_mother_pose(left_tip=(6, 0), right_tip=(58, 0), glow=True, pulse=0.8))
	return frames


def web_trap_frame():
	"""A sticky web tile on the floor: spokes from the centre joined by rings, no outline."""
	canvas = new_canvas(16, 16)
	for angle in range(0, 360, 45):
		radians = math.radians(angle)
		thick_line(canvas, 8, 8, 8 + 7 * math.cos(radians), 8 + 7 * math.sin(radians), 1.0, PALETTE['e'])
	# Two thin rings between the spokes, so it reads as a web and not a target.
	for radius in (3.5, 6.0):
		for y in range(16):
			for x in range(16):
				distance = math.hypot(x + 0.5 - 8, y + 0.5 - 8)
				if abs(distance - radius) <= 0.35:
					canvas[y][x] = PALETTE['e']
	canvas[8][8] = PALETTE['w']
	return canvas


def acid_puddle_frame():
	"""A flat acid pool, 24 wide: teal body with a darker rim and bright highlights."""
	canvas = new_canvas(24, 16)
	ellipse(canvas, 12, 8, 11.5, 7.0, PALETTE['t'])
	ellipse(canvas, 12, 8, 10.0, 5.8, PALETTE['a'])
	ellipse(canvas, 8, 6, 2.0, 1.0, PALETTE['A'])
	ellipse(canvas, 16, 10, 1.0, 0.7, PALETTE['A'])
	return canvas


def slime_puddle_frame():
	"""A flat slime pool, 24 wide: blue body with a darker rim and a highlight."""
	canvas = new_canvas(24, 16)
	ellipse(canvas, 12, 8, 11.5, 7.0, PALETTE['s'])
	ellipse(canvas, 12, 8, 10.0, 5.8, PALETTE['S'])
	ellipse(canvas, 8, 6, 2.0, 1.0, PALETTE['L'])
	return canvas


def write_png(path, rows):
	"""Writes RGBA rows (None means transparent) as a PNG using zlib and struct."""
	height = len(rows)
	width = len(rows[0])
	raw = bytearray()
	for row in rows:
		raw.append(0)
		for pixel in row:
			raw.extend(TRANSPARENT if pixel is None else pixel)

	def chunk(tag, data):
		return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xFFFFFFFF)

	header = struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)
	data = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', header) + chunk(b'IDAT', zlib.compress(bytes(raw), 9)) + chunk(b'IEND', b'')
	with open(path, 'wb') as file:
		file.write(data)


def write_strip(path, frames):
	"""Joins square frames left to right into one PNG; works for 16x16 and 64x64 frames."""
	height = len(frames[0])
	rows = []
	for y in range(height):
		row = []
		for frame in frames:
			row.extend(frame[y])
		rows.append(row)
	write_png(path, rows)


## Each slime/zombie is a 16x16 map of palette keys: one string per row, centred.
BLOATER_MAP = [
	'', 'llllll', 'gggggggg', 'gRggRg', 'gggggggggg', 'ggppppppppgg',
	'gppPppppPppg', 'gppppppppppg', 'gggpppppggg', 'gggggggggg',
	'rrrrrrrrrr', 'rrrrrrrr', 'bb....bb', 'bb....bb', 'bbb..bbb', '',
]
ACID_SLIME_MAP = [
	'', '', 'a.a..a.a', 'aaaaaaaaaa', 'aAaaaaaaaaa', 'aaRaaaaRaaa',
	'aaaaaaaaaaaa', 'aaaaaAaaaaaa', 'aaaaaaaaaaaa', 'aaaaaaaaaaa',
	'tttttttttttt', 'a.a.a.a.a.a', '', '', '', '',
]


def main():
	characters = os.path.join(HERE, 'characters')
	projectile = os.path.join(HERE, 'projectile')

	write_strip(os.path.join(characters, 'bloater_16x16_strip8.png'), walk_frames(from_rows(BLOATER_MAP)))
	write_strip(os.path.join(characters, 'acid_slime_16x16_strip8.png'), walk_frames(from_rows(ACID_SLIME_MAP)))
	write_strip(
		os.path.join(characters, 'skitter_spider_16x16_strip8.png'),
		spider_crawl_frames(PALETTE['X'], PALETTE['x'], PALETTE['Y'], PALETTE['X'], PALETTE['R'], PALETTE['w'], marks=PALETTE['R']),
	)
	write_strip(
		os.path.join(characters, 'web_spider_16x16_strip8.png'),
		spider_crawl_frames(PALETTE['X'], PALETTE['e'], PALETTE['Y'], PALETTE['X'], PALETTE['R'], PALETTE['w'], marks=PALETTE['p']),
	)
	write_png(
		os.path.join(characters, 'skitter_spider_dead_16x16.png'),
		spider_frames(PALETTE['X'], PALETTE['x'], PALETTE['Y'], PALETTE['R'], PALETTE['w'], marks=PALETTE['R'])[0],
	)
	write_png(
		os.path.join(characters, 'web_spider_dead_16x16.png'),
		spider_frames(PALETTE['X'], PALETTE['e'], PALETTE['Y'], PALETTE['R'], PALETTE['w'], marks=PALETTE['p'])[0],
	)

	write_strip(os.path.join(characters, 'giant_zombie_64x64.png'), giant_zombie_frames())
	write_strip(os.path.join(characters, 'plague_mother_64x64.png'), plague_mother_frames())
	write_strip(os.path.join(characters, 'broodmother_64x64.png'), broodmother_frames())

	write_png(os.path.join(projectile, 'acid_spit_8x8.png'), acid_spit_projectile())
	write_png(os.path.join(projectile, 'web_8x8.png'), web_projectile())

	write_png(os.path.join(HERE, 'misc', 'web_trap_16x16.png'), web_trap_frame())
	write_png(os.path.join(HERE, 'misc', 'acid_puddle_24x16.png'), acid_puddle_frame())
	write_png(os.path.join(HERE, 'misc', 'slime_puddle_24x16.png'), slime_puddle_frame())


if __name__ == '__main__':
	main()
