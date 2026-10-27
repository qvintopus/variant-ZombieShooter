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
	'w': (232, 226, 200, 255),  # bone white
	'e': (223, 233, 240, 255),  # web white
	'R': (224, 48, 46, 255),    # red eyes
	'k': (27, 20, 32, 255),     # black
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


def spider_frames(body, abdomen, leg_color, eye_color, abdomen_rx, marks=None):
	"""Radial 8-legged spider with the legs wiggling over the frames."""
	angles = [-170, -125, -85, -50, -10, 35, 80, 125]
	frames = []
	for frame in range(FRAME_COUNT):
		phase = frame / FRAME_COUNT * 2 * math.pi
		canvas = new_canvas(16, 16)
		cx = 7.5
		cy = 8.0
		for index, angle_deg in enumerate(angles):
			angle = math.radians(angle_deg)
			wiggle = 0.3 * math.sin(phase + index * math.pi / 2)
			knee_x = cx + 4.0 * math.cos(angle + wiggle)
			knee_y = cy + 4.0 * math.sin(angle + wiggle)
			foot_x = knee_x + 3.2 * math.cos(angle + 0.9 * (1 if index % 2 == 0 else -1))
			foot_y = knee_y + 3.2 * math.sin(angle + 0.9 * (1 if index % 2 == 0 else -1))
			thick_line(canvas, cx, cy, knee_x, knee_y, 1.0, leg_color)
			thick_line(canvas, knee_x, knee_y, foot_x, foot_y, 1.0, leg_color)
		ellipse(canvas, cx - 2.5, cy, abdomen_rx, 2.8, abdomen)
		ellipse(canvas, cx + 2.5, cy - 0.5, 2.3, 2.1, body)
		if marks is not None:
			ellipse(canvas, cx - 2.5, cy, 1.2, 1.0, marks)
		put(canvas, 10, 7, eye_color)
		put(canvas, 12, 7, eye_color)
		frames.append(add_outline(canvas))
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


def giant_zombie_boss():
	canvas = new_canvas(64, 64)
	thick_line(canvas, 24, 50, 22, 62, 7, PALETTE['b'])
	thick_line(canvas, 40, 50, 42, 62, 7, PALETTE['b'])
	thick_line(canvas, 16, 30, 6, 48, 8, PALETTE['g'])
	thick_line(canvas, 48, 30, 58, 48, 8, PALETTE['g'])
	ellipse(canvas, 32, 38, 19, 15, PALETTE['g'])
	ellipse(canvas, 32, 47, 17, 9, PALETTE['r'])
	ellipse(canvas, 32, 17, 11, 11, PALETTE['g'])
	ellipse(canvas, 28, 11, 5, 3, PALETTE['l'])
	ellipse(canvas, 26, 17, 1.6, 1.6, PALETTE['R'])
	ellipse(canvas, 38, 17, 1.6, 1.6, PALETTE['R'])
	thick_line(canvas, 26, 25, 38, 25, 2, PALETTE['k'])
	thick_line(canvas, 26, 38, 30, 44, 1, PALETTE['b'])
	thick_line(canvas, 36, 36, 38, 42, 1, PALETTE['b'])
	return add_outline(canvas)


def plague_mother_boss():
	canvas = new_canvas(64, 64)
	thick_line(canvas, 14, 20, 6, 6, 3, PALETTE['a'])
	thick_line(canvas, 50, 20, 58, 6, 3, PALETTE['a'])
	thick_line(canvas, 32, 18, 32, 4, 3, PALETTE['a'])
	ellipse(canvas, 6, 6, 2, 2, PALETTE['A'])
	ellipse(canvas, 58, 6, 2, 2, PALETTE['A'])
	ellipse(canvas, 32, 38, 22, 20, PALETTE['p'])
	ellipse(canvas, 32, 47, 16, 9, PALETTE['P'])
	ellipse(canvas, 24, 28, 7, 4, PALETTE['P'])
	ellipse(canvas, 44, 46, 3, 3, PALETTE['y'])
	ellipse(canvas, 20, 46, 2, 2, PALETTE['y'])
	ellipse(canvas, 40, 30, 2, 2, PALETTE['y'])
	ellipse(canvas, 24, 34, 3.5, 3.5, PALETTE['R'])
	ellipse(canvas, 40, 34, 3.5, 3.5, PALETTE['R'])
	ellipse(canvas, 32, 27, 4, 4, PALETTE['R'])
	ellipse(canvas, 24, 34, 1.2, 1.2, PALETTE['k'])
	ellipse(canvas, 40, 34, 1.2, 1.2, PALETTE['k'])
	ellipse(canvas, 32, 27, 1.4, 1.4, PALETTE['k'])
	ellipse(canvas, 32, 48, 6, 3, PALETTE['k'])
	ellipse(canvas, 14, 56, 2, 3, PALETTE['a'])
	ellipse(canvas, 30, 58, 2, 4, PALETTE['a'])
	ellipse(canvas, 48, 57, 2, 3, PALETTE['a'])
	return add_outline(canvas)


def broodmother_boss():
	canvas = new_canvas(64, 64)
	center_x = 32.0
	center_y = 36.0
	for angle_deg in (-150, -120, -95, -70, 70, 95, 120, 150):
		angle = math.radians(angle_deg)
		knee_x = center_x + 20 * math.cos(angle)
		knee_y = center_y + 18 * math.sin(angle)
		foot_x = center_x + 29 * math.cos(angle)
		foot_y = center_y + 27 * math.sin(angle)
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
	return add_outline(canvas)


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
	rows = []
	for y in range(16):
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
		spider_frames(PALETTE['X'], PALETTE['X'], PALETTE['w'], PALETTE['R'], 3.0),
	)
	write_strip(
		os.path.join(characters, 'web_spider_16x16_strip8.png'),
		spider_frames(PALETTE['e'], PALETTE['w'], PALETTE['X'], PALETTE['R'], 3.4, marks=PALETTE['p']),
	)

	write_png(os.path.join(characters, 'giant_zombie_64x64.png'), giant_zombie_boss())
	write_png(os.path.join(characters, 'plague_mother_64x64.png'), plague_mother_boss())
	write_png(os.path.join(characters, 'broodmother_64x64.png'), broodmother_boss())

	write_png(os.path.join(projectile, 'acid_spit_8x8.png'), acid_spit_projectile())
	write_png(os.path.join(projectile, 'web_8x8.png'), web_projectile())


if __name__ == '__main__':
	main()
