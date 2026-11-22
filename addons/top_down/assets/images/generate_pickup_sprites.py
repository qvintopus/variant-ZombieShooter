#!/usr/bin/env python3
"""Pixel-art generator for the loot pickups and the room contraptions.

Reuses the helpers and palette of generate_enemy_sprites.py (standard library only):

    python3 generate_pickup_sprites.py

Output layout:
- items/*_8x8_strip3.png    3-frame idle shine strips, same format as coin_8x8_strip3.png
- misc/meat_grinder_24x32_strip4.png     idle + 3 crank frames
- misc/slime_workbench_32x24_strip2.png  idle + bubbling
- misc/slot_machine_24x32_strip3.png     idle, spinning, lever pulled
- projectile/bomb_16x16_strip4.png        bomb with a flickering fuse spark (ability)
- projectile/bomb_hot_16x16_strip2.png    white-hot bomb about to blow
- gui/ability_bomb_16x16.png              bomb ability HUD icon

Only the bomb:  python3 generate_pickup_sprites.py --bomb
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generate_enemy_sprites import HERE, PALETTE, add_outline, ellipse, new_canvas, write_png, write_strip

COLORS = dict(PALETTE)
COLORS.update({
	'F': (240, 150, 140, 255),  # raw meat fat
	'M': (150, 156, 170, 255),  # metal
	'N': (92, 96, 112, 255),    # metal dark
	'H': (214, 218, 228, 255),  # metal highlight
	'C': (255, 120, 220, 255),  # crystal glow
	'c': (196, 64, 176, 255),   # crystal body
	'D': (106, 30, 112, 255),   # crystal dark
	'G': (250, 204, 72, 255),   # gold
	'g': (180, 130, 40, 255),   # gold dark
	'E': (198, 40, 52, 255),    # cabinet red
	'e': (130, 22, 34, 255),    # cabinet red dark
	'K': (60, 52, 70, 255),     # screen black
	'T': (150, 104, 66, 255),   # wood
	't': (96, 62, 38, 255),     # wood dark
	'I': (255, 255, 255, 255),  # glint
})


def canvas_from_rows(rows, width, height):
	"""Palette-key rows, left aligned; '.' or a missing tail is transparent."""
	assert len(rows) == height, 'expected %d rows, got %d' % (height, len(rows))
	canvas = new_canvas(width, height)
	for y, text in enumerate(rows):
		assert len(text) <= width, text
		for x, key in enumerate(text):
			if key != '.':
				canvas[y][x] = COLORS[key]
	return canvas


def shine_frames(rows, glints):
	"""One outlined 8x8 frame per glint list; glints are (x, y) pixels painted white."""
	frames = []
	for points in glints:
		canvas = canvas_from_rows(rows, 8, 8)
		for x, y in points:
			canvas[y][x] = COLORS['I']
		frames.append(add_outline(canvas))
	return frames


MEAT = [
	'........',
	'..mEE...',
	'.mEFEE..',
	'.mEEEFw.',
	'.mmEEww.',
	'..mmmw..',
	'........',
	'........',
]
SLIME = [
	'........',
	'...SS...',
	'..SLSS..',
	'.SLSSSS.',
	'.SSSSSs.',
	'..ssss..',
	'........',
	'........',
]
CRYSTAL = [
	'...C....',
	'..cCc...',
	'..cCcD..',
	'.ccCcD..',
	'.cCccD..',
	'..cDD...',
	'...D....',
	'........',
]

GRINDER = [
	'........................',
	'...NNNNNNNNNNNNNNNNN....',
	'...NHHHHHHHHHHHHHHMN....',
	'....NMMMMMMMMMMMMMN.....',
	'.....NMMMKKKKKMMMN......',
	'......NMMKmEmKMMN.......',
	'.......NMMKKKMMN........',
	'........NMMMMMN.........',
	'.......NNNNNNNNN........',
	'.....NHHHHHHHHHHHN......',
	'....NHMMMMMMMMMMMMN.....',
	'....NMMMMMMMMMMMMMN.....',
	'....NMMNNNNNNNNMMMNNNNN.',
	'....NMMMMMMMMMMMMMMMMMMN',
	'....NMMMMMMMMMMMMMNNNNNN',
	'....NMMNNNNNNNNMMMN.....',
	'....NMMMMMMMMMMMMMN.....',
	'....NNMMMMMMMMMMMNN.....',
	'.....NNNNNNNNNNNNN......',
	'.......NMN...NMN........',
	'.......NMN...NMN........',
	'.......NMN...NMN........',
	'.......NMN...NMN........',
	'......NNMNN.NNMNN.......',
	'.....tTTTTTTTTTTTTt.....',
	'.....tTTTTTTTTTTTTt.....',
	'.....tttttttttttttt.....',
	'........................',
	'........................',
	'........................',
	'........................',
	'........................',
]
## Crank handle end positions for the three grinding frames (the idle frame uses the first).
GRINDER_CRANKS = [(20, 9), (22, 13), (20, 17), (21, 11)]

WORKBENCH = [
	'................................',
	'.....s..........................',
	'....sSs......NNN.......ss.......',
	'...sSLSs....NHMN......sSSs......',
	'...sSSSs....NMMN.....sSLSSs.....',
	'...sSSSs.....NN......sSSSSs.....',
	'....sss......NN.......ssss......',
	'tttttttttttttttttttttttttttttttt',
	'TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT',
	'TTTTsTTTTTTTTTTTTTTTTTTTTTTSSTTT',
	'tttttttttttttttttttttttttttttttt',
	'.tTt......................tTt...',
	'.tTt......................tTt...',
	'.tTt.....ttttttttttttt....tTt...',
	'.tTt.....tTTTTTTTTTTTt....tTt...',
	'.tTt.....tTsSSsTTTTTTt....tTt...',
	'.tTt.....tTTTTTTTTTTTt....tTt...',
	'.tTt.....ttttttttttttt....tTt...',
	'.tTt......................tTt...',
	'.tTt......................tTt...',
	'.tTt......................tTt...',
	'.ttt......................ttt...',
	'................................',
	'................................',
]

def _cabinet(inner):
	"""A slot machine cabinet row: dark red sides at x=4 and x=20 around 15 inner pixels."""
	assert len(inner) == 15, inner
	return '....e' + inner + 'e'


SLOT = [
	'......' + 'G' * 13,
	'.....g' + 'G' * 13 + 'g',
	_cabinet('E' * 15),
	_cabinet('EGEGEGEGEGEGEGE'),
	_cabinet('E' * 15),
	_cabinet('E' + 'K' * 13 + 'E'),
	_cabinet('EKwwwKwwwKwwwKE'),
	_cabinet('EKwwwKwwwKwwwKE'),
	_cabinet('EKwwwKwwwKwwwKE'),
	_cabinet('EKwwwKwwwKwwwKE'),
	_cabinet('E' + 'K' * 13 + 'E'),
	_cabinet('E' * 15),
	_cabinet('E' * 6 + 'KKK' + 'E' * 6),
	_cabinet('E' * 15),
	'...' + 'e' * 19,
	'...eH' + 'M' * 15 + 'He',
	'...e' + 'M' * 17 + 'e',
	'...' + 'e' * 19,
	_cabinet('E' * 15),
	_cabinet('E' * 15),
	_cabinet('EEEg' + 'G' * 7 + 'gEEE'),
	_cabinet('EEEg' + 'K' * 7 + 'gEEE'),
	_cabinet('EEE' + 'g' * 9 + 'EEE'),
	_cabinet('E' * 15),
	_cabinet('E' * 15),
	_cabinet('E' * 15),
	'....' + 'e' * 17,
	'....' + 'N' * 17,
	'',
	'',
	'',
	'',
]
## Symbols painted into the three reel windows: (x of window, rows of keys).
REEL_X = (7, 11, 15)
SYMBOLS = {
	'cherry': ['.E.', 'EEE', 'eE.'],
	'seven': ['GGG', '.gG', '.G.'],
	'meat': ['EE.', 'EFw', '.ww'],
	'blur': ['NHN', 'HNH', 'NHN'],
}


def grinder_frame(crank):
	canvas = canvas_from_rows(GRINDER, 24, 32)
	# Crank arm from the axle on the body's right side to the handle.
	ax, ay = 19, 13
	hx, hy = crank
	steps = max(abs(hx - ax), abs(hy - ay))
	for i in range(steps + 1):
		x = round(ax + (hx - ax) * i / steps)
		y = round(ay + (hy - ay) * i / steps)
		canvas[y][x] = COLORS['N']
	canvas[hy][hx] = COLORS['E']
	return add_outline(canvas)


def workbench_frame(bubbling):
	canvas = canvas_from_rows(WORKBENCH, 32, 24)
	if bubbling:
		for x, y in ((5, 0), (23, 1), (25, 0)):
			canvas[y][x] = COLORS['L']
	return add_outline(canvas)


def slot_frame(symbols, lever_down):
	canvas = canvas_from_rows(SLOT, 24, 32)
	for x0, name in zip(REEL_X, symbols):
		for dy, text in enumerate(SYMBOLS[name]):
			for dx, key in enumerate(text):
				if key != '.':
					canvas[6 + dy][x0 + dx] = COLORS[key]
	# Lever: a pole on the right with a red knob, pulled down when used.
	top = 11 if lever_down else 2
	for y in range(top + 1, 14):
		canvas[y][22] = COLORS['M']
	canvas[top][22] = COLORS['E']
	canvas[top - 1][22] = COLORS['E']
	return add_outline(canvas)


BOMB_BODY = (44, 42, 56, 255)
BOMB_MID = (70, 68, 88, 255)
BOMB_SHINE = (150, 150, 176, 255)
BOMB_CAP = (120, 112, 96, 255)
FUSE = (150, 104, 66, 255)
SPARK_HOT = (255, 250, 210, 255)
SPARK_MID = (255, 196, 64, 255)
SPARK_RED = (240, 90, 40, 255)

## Spark shapes per frame: (dx, dy, color) around the fuse tip
BOMB_SPARKS = [
	[(0, 0, SPARK_HOT), (-1, 0, SPARK_MID), (1, -1, SPARK_MID), (0, -2, SPARK_RED)],
	[(0, 0, SPARK_HOT), (1, 0, SPARK_MID), (-1, -1, SPARK_RED), (1, -2, SPARK_MID), (-2, -2, SPARK_RED)],
	[(0, 0, SPARK_MID), (0, -1, SPARK_HOT), (-1, -2, SPARK_MID)],
	[(0, 0, SPARK_HOT), (-1, -1, SPARK_MID), (1, -1, SPARK_MID), (0, -3, SPARK_RED), (2, -2, SPARK_RED)],
]


def bomb_frame(sparks, hot=0.0):
	"""16x16 round bomb, fuse to the upper right; `hot` 0..1 blends the body toward white."""
	def mix(color):
		if hot <= 0.0:
			return color
		return tuple(int(c + (255 - c) * hot) for c in color[:3]) + (255,)
	canvas = new_canvas(16, 16)
	ellipse(canvas, 7.5, 9.5, 5.5, 5.5, mix(BOMB_BODY))
	ellipse(canvas, 6.8, 8.6, 3.6, 3.6, mix(BOMB_MID))
	ellipse(canvas, 5.6, 7.4, 1.4, 1.4, mix(BOMB_SHINE))
	# cap
	for x in range(8, 11):
		canvas[4][x] = mix(BOMB_CAP)
		canvas[5][x] = mix(BOMB_CAP)
	# fuse
	for x, y in [(10, 3), (11, 2), (12, 2)]:
		canvas[y][x] = FUSE
	tip_x, tip_y = 13, 2
	framed = add_outline(canvas)
	for dx, dy, color in sparks:
		x, y = tip_x + dx, tip_y + dy
		if 0 <= x < 16 and 0 <= y < 16:
			framed[y][x] = color
	return framed


def bomb_main():
	projectile = os.path.join(HERE, 'projectile')
	gui = os.path.join(HERE, 'gui')
	write_strip(os.path.join(projectile, 'bomb_16x16_strip4.png'), [bomb_frame(s) for s in BOMB_SPARKS])
	write_strip(os.path.join(projectile, 'bomb_hot_16x16_strip2.png'), [bomb_frame(BOMB_SPARKS[0], 0.55), bomb_frame(BOMB_SPARKS[3], 0.9)])
	write_png(os.path.join(gui, 'ability_bomb_16x16.png'), bomb_frame(BOMB_SPARKS[1]))


def main():
	items = os.path.join(HERE, 'items')
	misc = os.path.join(HERE, 'misc')

	write_strip(os.path.join(items, 'meat_8x8_strip3.png'), shine_frames(MEAT, [[(3, 2)], [(4, 1)], []]))
	write_strip(os.path.join(items, 'slime_ball_8x8_strip3.png'), shine_frames(SLIME, [[(3, 2)], [(4, 2)], [(3, 3)]]))
	write_strip(os.path.join(items, 'boss_crystal_8x8_strip3.png'), shine_frames(CRYSTAL, [[(3, 1)], [(3, 3)], [(2, 4)]]))

	write_strip(os.path.join(misc, 'meat_grinder_24x32_strip4.png'), [grinder_frame(c) for c in GRINDER_CRANKS])
	write_strip(os.path.join(misc, 'slime_workbench_32x24_strip2.png'), [workbench_frame(False), workbench_frame(True)])
	write_strip(os.path.join(misc, 'slot_machine_24x32_strip3.png'), [
		slot_frame(('seven', 'cherry', 'meat'), False),
		slot_frame(('blur', 'blur', 'blur'), True),
		slot_frame(('blur', 'blur', 'blur'), False),
	])


def preview(path, scale=8):
	"""Writes an upscaled copy of every generated strip stacked vertically, for eyeballing."""
	import struct
	import zlib

	def read_png(file_path):
		with open(file_path, 'rb') as file:
			data = file.read()
		pos = 8
		idat = b''
		while pos < len(data):
			length = struct.unpack('>I', data[pos:pos + 4])[0]
			tag = data[pos + 4:pos + 8]
			body = data[pos + 8:pos + 8 + length]
			if tag == b'IHDR':
				width, height = struct.unpack('>II', body[:8])
			elif tag == b'IDAT':
				idat += body
			pos += 12 + length
		raw = zlib.decompress(idat)
		rows = []
		stride = width * 4 + 1
		for y in range(height):
			line = raw[y * stride + 1:(y + 1) * stride]
			rows.append([tuple(line[x * 4:x * 4 + 4]) for x in range(width)])
		return rows

	names = [
		'items/meat_8x8_strip3.png', 'items/slime_ball_8x8_strip3.png', 'items/boss_crystal_8x8_strip3.png',
		'misc/meat_grinder_24x32_strip4.png', 'misc/slime_workbench_32x24_strip2.png', 'misc/slot_machine_24x32_strip3.png',
	]
	images = [read_png(os.path.join(HERE, n)) for n in names]
	width = max(len(img[0]) for img in images) * scale
	out = []
	for img in images:
		for row in img:
			line = []
			for pixel in row:
				p = pixel if pixel[3] else (60, 70, 60, 255)
				line.extend([p] * scale)
			line.extend([(30, 30, 30, 255)] * (width - len(line)))
			out.extend([line] * scale)
		out.extend([[(30, 30, 30, 255)] * width] * 4)
	write_png(path, out)


if __name__ == '__main__':
	if '--bomb' in sys.argv:
		bomb_main()
		sys.exit(0)
	main()
	bomb_main()
	if len(sys.argv) > 1:
		preview(sys.argv[1])
