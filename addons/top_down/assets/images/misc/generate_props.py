"""Paints the prop strips that have no hand-drawn art:

  portal_32x32_strip6.png    frame 0 a dormant stone ring, frames 1-5 its vortex swirling
  loot_box_24x24_strip2.png  frame 0 closed, frame 1 open with the gold showing
  storage_chest_24x24_strip2.png  home chest: frame 0 shut, frame 1 lid up, dark inside
  shrine_24x32_sheet4x3.png  healing shrine: row = tier (1/2/3 uses: stone/silver/gold),
                             column = uses left (0 spent ... 3), pips on the plinth

Standard library only; rerun to regenerate (same pixels every run).
  python3 addons/top_down/assets/images/misc/generate_props.py
"""
import math
import os
import sys

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
from generate_tile_variants import write_png  # noqa: E402

CLEAR = (0, 0, 0, 0)
OUTLINE = (24, 14, 30, 255)
# Stone of the stairs art, darkest to lightest.
STONE = [(36, 20, 44, 255), (57, 41, 70, 255), (91, 83, 125, 255), (132, 126, 168, 255)]
VORTEX = [(40, 16, 72, 255), (92, 40, 150, 255), (150, 84, 220, 255), (90, 220, 210, 255), (214, 255, 246, 255)]
WOOD = [(46, 26, 20, 255), (86, 50, 30, 255), (128, 80, 44, 255), (168, 116, 64, 255)]
IRON = [(40, 40, 52, 255), (96, 100, 118, 255), (168, 172, 186, 255)]
GOLD = [(150, 98, 20, 255), (226, 176, 48, 255), (255, 236, 140, 255)]

PORTAL = 32
PORTAL_FRAMES = 6
# Ring centre and radii; the pad diamond under it centres on PAD_Y.
RING_X, RING_Y, RING_RX, RING_RY = 15.5, 13.0, 9.5, 12.0
PAD_Y = 24


def blank(width, height):
	return [[CLEAR] * width for _ in range(height)]


def ring_distance(x, y):
	"""Elliptic radius of a pixel centre, 1.0 on the ring's outer edge."""
	return math.hypot((x + 0.5 - RING_X - 0.5) / RING_RX, (y + 0.5 - RING_Y) / RING_RY)


def portal_frame(frame):
	rows = blank(PORTAL, PORTAL)
	# Pad: an iso diamond, lit on the left, glowing once the portal is open.
	for y in range(PAD_Y - 7, PAD_Y + 8):
		for x in range(PORTAL):
			d = abs(x + 0.5 - 16) / 14 + abs(y + 0.5 - PAD_Y) / 7
			if d > 1.0:
				continue
			if d > 0.82:
				rows[y][x] = OUTLINE
			elif d > 0.62:
				rows[y][x] = STONE[2] if x < 16 else STONE[1]
			elif frame == 0:
				rows[y][x] = STONE[0]
			else:
				rows[y][x] = VORTEX[1] if (x + y + frame) % 4 else VORTEX[2]
	# Ring: stone with a lit top-left, its inside dark when dormant, a vortex when open.
	for y in range(PORTAL):
		for x in range(PORTAL):
			r = ring_distance(x, y)
			if r > 1.0:
				continue
			if r > 0.9:
				rows[y][x] = OUTLINE
			elif r > 0.7:
				lit = (x + 0.5 - RING_X) + (y + 0.5 - RING_Y) < -3
				rows[y][x] = STONE[3] if lit else STONE[2] if y < RING_Y else STONE[1]
			elif r > 0.62:
				rows[y][x] = OUTLINE
			elif frame == 0:
				rows[y][x] = STONE[0] if r > 0.3 else OUTLINE
			else:
				angle = math.atan2((y + 0.5 - RING_Y) / RING_RY, (x + 0.5 - RING_X - 0.5) / RING_RX)
				# Two spiral arms turning a fifth of a half-turn per frame.
				band = (angle * 2 / math.tau + r * 2.2 - frame * 0.2) % 1.0
				shade = 0 if r > 0.5 else 1
				if band < 0.18:
					shade = 3 if r < 0.45 else 2
				elif band < 0.4:
					shade += 1
				if r < 0.14:
					shade = 4
				rows[y][x] = VORTEX[min(shade, 4)]
	# Runes on the ring glow once it is open.
	if frame:
		for step in range(6):
			a = step * math.tau / 6 + frame * 0.35
			x = int(RING_X + 0.5 + math.cos(a) * RING_RX * 0.8)
			y = int(RING_Y + math.sin(a) * RING_RY * 0.8)
			if 0 <= x < PORTAL and 0 <= y < PORTAL and rows[y][x] != CLEAR:
				rows[y][x] = VORTEX[3]
	return rows


BOX = 24


def loot_box_frame(frame):
	rows = blank(BOX, BOX)

	def put(x, y, color):
		if 0 <= x < BOX and 0 <= y < BOX:
			rows[y][x] = color

	left, right, top, bottom = 3, 20, 11, 21
	# Body: wooden planks with iron bands at the ends and a darker right side.
	for y in range(top, bottom + 1):
		for x in range(left, right + 1):
			edge = x in (left, right) or y == bottom
			if edge:
				color = OUTLINE
			elif x in (left + 2, right - 2):
				color = IRON[1]
			elif (y - top) % 4 == 0:
				color = WOOD[0]
			else:
				color = WOOD[2] if x < 14 else WOOD[1]
			put(x, y, color)
	if frame == 0:
		# Closed lid: a rounded top over the body with a lock plate.
		for y in range(top - 5, top + 1):
			for x in range(left, right + 1):
				inset = max(0, 2 - (y - (top - 5)))
				if x < left + inset or x > right - inset:
					continue
				edge = y == top - 5 or x in (left + inset, right - inset) or y == top
				put(x, y, OUTLINE if edge else WOOD[3] if y < top - 2 else WOOD[2])
		for y in range(top - 1, top + 3):
			for x in range(10, 14):
				put(x, y, IRON[2] if y == top - 1 else IRON[1])
		put(11, top + 1, OUTLINE)
	else:
		# Open: the lid tipped back above, gold heaped inside with a glint.
		for y in range(top - 9, top - 3):
			for x in range(left + 1, right):
				edge = y in (top - 9, top - 4) or x in (left + 1, right - 1)
				put(x, y, OUTLINE if edge else WOOD[1])
		for y in range(top - 4, top):
			put(left, y, IRON[0])
			put(right, y, IRON[0])
		for x in range(left + 1, right):
			put(x, top, OUTLINE)
		for y in range(top - 3, top + 2):
			for x in range(left + 1, right):
				heap = abs(x + 0.5 - 12) / 8 + (top + 1 - y) / 4
				if heap <= 1.0:
					put(x, y, GOLD[2] if (x * 3 + y) % 5 == 0 else GOLD[1] if heap < 0.7 else GOLD[0])
		for x, y in ((9, top - 5), (9, top - 6), (8, top - 5), (10, top - 5), (15, top - 3)):
			put(x, y, GOLD[2])
	return rows


STEEL = [(30, 32, 44, 255), (62, 68, 88, 255), (104, 112, 134, 255), (150, 158, 178, 255)]
TEAL = (90, 220, 210, 255)


def storage_chest_frame(frame):
	"""Wider steel locker of the home base, wood trim, a teal status light."""
	rows = blank(BOX, BOX)

	def put(x, y, color):
		if 0 <= x < BOX and 0 <= y < BOX:
			rows[y][x] = color

	left, right, top, bottom = 2, 21, 11, 21
	for y in range(top, bottom + 1):
		for x in range(left, right + 1):
			if x in (left, right) or y == bottom:
				color = OUTLINE
			elif x in (left + 3, right - 3):
				color = WOOD[1]
			elif y == top + 4:
				color = STEEL[0]
			else:
				color = STEEL[2] if x < 13 else STEEL[1]
			put(x, y, color)
	# rivets on the trim
	for x in (left + 3, right - 3):
		put(x, top + 2, STEEL[3])
		put(x, bottom - 2, STEEL[3])
	if frame == 0:
		for y in range(top - 4, top + 1):
			for x in range(left, right + 1):
				inset = max(0, 1 - (y - (top - 4)))
				if x < left + inset or x > right - inset:
					continue
				edge = y == top - 4 or x in (left + inset, right - inset) or y == top
				put(x, y, OUTLINE if edge else STEEL[3] if y < top - 2 else STEEL[2])
		for y in range(top - 1, top + 3):
			for x in range(10, 14):
				put(x, y, IRON[2] if y == top - 1 else IRON[1])
		put(11, top + 1, TEAL)
		put(12, top + 1, TEAL)
	else:
		for y in range(top - 9, top - 3):
			for x in range(left + 1, right):
				edge = y in (top - 9, top - 4) or x in (left + 1, right - 1)
				put(x, y, OUTLINE if edge else STEEL[1])
		for x in range(left + 1, right):
			put(x, top, OUTLINE)
		for y in range(top - 3, top + 3):
			for x in range(left + 1, right):
				put(x, y, OUTLINE if y == top - 3 else STEEL[0])
		for x in range(8, 16):
			put(x, top + 2, TEAL if x % 3 == 0 else STEEL[1])
	return rows


SHRINE_W, SHRINE_H = 24, 32
# Tier looks: plinth shades (dark..light), crystal shades (dark..light).
SHRINE_TIERS = [
	(STONE, [(30, 60, 120, 255), (60, 120, 220, 255), (130, 190, 255, 255), (220, 240, 255, 255)]),
	([IRON[0], IRON[1], IRON[2], (210, 214, 226, 255)], [(20, 90, 60, 255), (50, 180, 110, 255), (130, 240, 170, 255), (225, 255, 235, 255)]),
	([GOLD[0], (190, 136, 34, 255), GOLD[1], GOLD[2]], [(140, 40, 30, 255), (230, 90, 60, 255), (255, 170, 110, 255), (255, 240, 210, 255)]),
]
DEAD = [(28, 24, 34, 255), (52, 48, 62, 255), (80, 76, 92, 255), (100, 96, 110, 255)]


def shrine_frame(tier, left):
	"""Plinth with a basin and a floating crystal; `left` uses lit as pips."""
	rows = blank(SHRINE_W, SHRINE_H)
	stone, crystal = SHRINE_TIERS[tier - 1]
	if left == 0:
		crystal = DEAD

	def put(x, y, color):
		if 0 <= x < SHRINE_W and 0 <= y < SHRINE_H:
			rows[y][x] = color

	# Base step (wide) and plinth column, lit on the left.
	for y in range(26, 31):
		for x in range(3, 21):
			edge = x in (3, 20) or y in (26, 30)
			put(x, y, OUTLINE if edge else stone[2] if x < 11 else stone[1])
	for y in range(15, 27):
		for x in range(6, 18):
			edge = x in (6, 17) or y == 15
			put(x, y, OUTLINE if edge else stone[3] if x < 9 else stone[2] if x < 13 else stone[1])
	# Basin lip on top of the column.
	for y in range(13, 16):
		for x in range(4, 20):
			edge = x in (4, 19) or y in (13, 15)
			put(x, y, OUTLINE if edge else stone[3] if x < 12 else stone[2])
	for x in range(6, 18):
		put(x, 14, crystal[1] if left else stone[0])
	# Pips: one per possible use, lit while it is left.
	for i in range(tier):
		px = 12 - (tier - 1) * 2 + i * 4
		for dy in (0, 1):
			for dx in (-1, 0):
				put(px + dx, 20 + dy, (crystal[3] if dy == 0 and dx == -1 else crystal[1]) if i < left else OUTLINE)
	# Floating crystal: a diamond, lit top-left, glint; cracked and grey when spent.
	cx, cy = 11.5, 6.5
	for y in range(0, 13):
		for x in range(SHRINE_W):
			d = abs(x + 0.5 - cx - 0.5) / 4.5 + abs(y + 0.5 - cy) / 6.0
			if d > 1.0:
				continue
			if d > 0.8:
				color = OUTLINE
			elif (x + 0.5 - cx) + (y + 0.5 - cy) < -1.5:
				color = crystal[2]
			elif x + 0.5 > cx + 1:
				color = crystal[0]
			else:
				color = crystal[1]
			put(x, y, color)
	if left:
		put(10, 4, crystal[3])
		put(10, 5, crystal[3])
		put(11, 4, crystal[3])
	else:
		for x, y in ((12, 3), (11, 5), (12, 6), (11, 8)):
			put(x, y, OUTLINE)
	return rows


def sheet(frame_rows):
	rows = []
	for frames in frame_rows:
		rows.extend(strip(frames))
	return rows


def strip(frames):
	rows = [[] for _ in frames[0]]
	for frame in frames:
		for y, row in enumerate(frame):
			rows[y].extend(row)
	return rows


def main():
	write_png(os.path.join(HERE, 'portal_32x32_strip6.png'), strip([portal_frame(i) for i in range(PORTAL_FRAMES)]))
	write_png(os.path.join(HERE, 'loot_box_24x24_strip2.png'), strip([loot_box_frame(i) for i in range(2)]))
	write_png(os.path.join(HERE, 'storage_chest_24x24_strip2.png'), strip([storage_chest_frame(i) for i in range(2)]))
	write_png(os.path.join(HERE, 'shrine_24x32_sheet4x3.png'), sheet([[shrine_frame(t, min(u, t)) for u in range(4)] for t in (1, 2, 3)]))


if __name__ == '__main__':
	main()
