--!strict
-- Pure cursive-script glyph geometry for the portal signs (issue #60
-- follow-up: real neon-tube signage instead of a flat TextLabel). Loadable
-- under both Rojo and Lune (test/neonScript.test.luau) -- follows the
-- roblox-lune-testable-module skill's exact pattern, zero references to
-- Roblox-only globals. MapBuilder.lua owns turning the point paths this
-- module produces into actual Neon-material tube/ball Instances.
--
-- Every letter is one continuous stroke (real cursive doesn't lift the pen
-- within a letter, and WordPath below doesn't lift it between letters
-- either) built from a short sequence of arcs and straight lines in a
-- local 2D glyph space: x grows rightward from 0, y grows upward with the
-- baseline at 0, x-height around 0.65, ascenders to ~1.0, descenders (the
-- "Y" tail) down to about -0.3. These are a first-pass, deliberately
-- simplified approximation of script letterforms, not typographically
-- precise -- see the plan's own note that this needs a round of visual
-- feedback once it's actually rendered in Studio.
local NeonScript = {}

export type Point2 = { x: number, y: number }

-- Points along a circular arc from startDeg to endDeg (degrees, standard
-- math convention: 0 = +x, 90 = +y, counterclockwise). The one reusable
-- curve primitive every glyph's flowing strokes are built from.
function NeonScript.ArcPoints(cx: number, cy: number, radius: number, startDeg: number, endDeg: number, segments: number): { Point2 }
	local points = {}
	for i = 0, segments do
		local t = i / segments
		local angleDeg = startDeg + (endDeg - startDeg) * t
		local angleRad = math.rad(angleDeg)
		table.insert(points, { x = cx + radius * math.cos(angleRad), y = cy + radius * math.sin(angleRad) })
	end
	return points
end

type ArcStroke = { kind: "arc", cx: number, cy: number, r: number, startDeg: number, endDeg: number, segments: number? }
type LineStroke = { kind: "line", x1: number, y1: number, x2: number, y2: number }
type Stroke = ArcStroke | LineStroke

local function strokesToPoints(strokes: { Stroke }): { Point2 }
	local points: { Point2 } = {}
	for _, stroke in ipairs(strokes) do
		if stroke.kind == "arc" then
			local arcPoints = NeonScript.ArcPoints(stroke.cx, stroke.cy, stroke.r, stroke.startDeg, stroke.endDeg, stroke.segments or 8)
			for _, p in ipairs(arcPoints) do
				table.insert(points, p)
			end
		else
			table.insert(points, { x = stroke.x1, y = stroke.y1 })
			table.insert(points, { x = stroke.x2, y = stroke.y2 })
		end
	end
	return points
end

-- One entry per letter this game's four difficulty labels actually need
-- (EASY/MEDIUM/HARD/VERY HARD -> E,A,S,Y,M,D,I,U,H,R,V) -- not a full
-- alphabet, since every glyph here is a hand-authored curve composition,
-- not a real font.
local GLYPH_STROKES: { [string]: { Stroke } } = {
	A = {
		{ kind = "arc", cx = 0.22, cy = 0.32, r = 0.22, startDeg = 0, endDeg = 350, segments = 10 },
		{ kind = "arc", cx = 0.48, cy = 0.5, r = 0.18, startDeg = 200, endDeg = 80, segments = 6 },
	},
	E = {
		{ kind = "arc", cx = 0.28, cy = 0.48, r = 0.22, startDeg = 70, endDeg = 320, segments = 8 },
		{ kind = "arc", cx = 0.25, cy = 0.18, r = 0.15, startDeg = 300, endDeg = 120, segments = 6 },
	},
	S = {
		{ kind = "arc", cx = 0.25, cy = 0.48, r = 0.18, startDeg = -30, endDeg = 200, segments = 7 },
		{ kind = "arc", cx = 0.25, cy = 0.15, r = 0.18, startDeg = 20, endDeg = 250, segments = 7 },
	},
	Y = {
		{ kind = "arc", cx = 0.15, cy = 0.5, r = 0.18, startDeg = 30, endDeg = 200, segments = 6 },
		{ kind = "arc", cx = 0.4, cy = 0.5, r = 0.18, startDeg = -20, endDeg = 150, segments = 6 },
		{ kind = "arc", cx = 0.3, cy = -0.05, r = 0.15, startDeg = 90, endDeg = 300, segments = 6 },
	},
	M = {
		{ kind = "line", x1 = 0.05, y1 = 0.0, x2 = 0.05, y2 = 0.45 },
		{ kind = "arc", cx = 0.2, cy = 0.45, r = 0.15, startDeg = 180, endDeg = 0, segments = 6 },
		-- Valley stem down to the baseline. The renderer (MapBuilder.lua's
		-- buildNeonTube) connects every consecutive point regardless of
		-- stroke boundaries, so getting back up to (0.35, 0.45) for the
		-- second hump's arc below doesn't need its own explicit stroke --
		-- a second "line back up" retracing this exact segment was here
		-- originally and was entirely redundant (an extra wasted tube
		-- segment for zero visual difference), found and removed by the
		-- bug-hunt loop.
		{ kind = "line", x1 = 0.35, y1 = 0.45, x2 = 0.35, y2 = 0.0 },
		{ kind = "arc", cx = 0.5, cy = 0.45, r = 0.15, startDeg = 180, endDeg = 0, segments = 6 },
		{ kind = "line", x1 = 0.65, y1 = 0.45, x2 = 0.65, y2 = 0.0 },
	},
	D = {
		{ kind = "line", x1 = 0.1, y1 = 0.0, x2 = 0.1, y2 = 0.7 },
		{ kind = "arc", cx = 0.25, cy = 0.3, r = 0.25, startDeg = 160, endDeg = -140, segments = 10 },
	},
	I = {
		{ kind = "arc", cx = 0.22, cy = 0.58, r = 0.08, startDeg = 0, endDeg = 340, segments = 6 },
		{ kind = "line", x1 = 0.22, y1 = 0.5, x2 = 0.2, y2 = 0.0 },
	},
	U = {
		{ kind = "line", x1 = 0.05, y1 = 0.6, x2 = 0.05, y2 = 0.25 },
		{ kind = "arc", cx = 0.25, cy = 0.25, r = 0.2, startDeg = 180, endDeg = 380, segments = 10 },
		{ kind = "line", x1 = 0.45, y1 = 0.25, x2 = 0.45, y2 = 0.6 },
	},
	H = {
		{ kind = "line", x1 = 0.1, y1 = 0.0, x2 = 0.1, y2 = 0.65 },
		{ kind = "arc", cx = 0.25, cy = 0.5, r = 0.18, startDeg = 180, endDeg = 0, segments = 6 },
		{ kind = "line", x1 = 0.43, y1 = 0.5, x2 = 0.43, y2 = 0.0 },
	},
	R = {
		{ kind = "line", x1 = 0.1, y1 = 0.0, x2 = 0.1, y2 = 0.65 },
		{ kind = "arc", cx = 0.22, cy = 0.5, r = 0.15, startDeg = 180, endDeg = -60, segments = 8 },
		{ kind = "line", x1 = 0.22, y1 = 0.35, x2 = 0.42, y2 = 0.0 },
	},
	V = {
		{ kind = "line", x1 = 0.05, y1 = 0.6, x2 = 0.25, y2 = 0.0 },
		{ kind = "line", x1 = 0.25, y1 = 0.0, x2 = 0.45, y2 = 0.6 },
	},
}

-- Precomputed once at module load -- pure data, cheap, and every caller
-- (both the Roblox renderer and Lune tests) wants the finished point path,
-- not the stroke description.
local GLYPHS: { [string]: { Point2 } } = {}
for letter, strokes in pairs(GLYPH_STROKES) do
	GLYPHS[letter] = strokesToPoints(strokes)
end
NeonScript.GLYPHS = GLYPHS

local function glyphWidth(glyph: { Point2 }): number
	local maxX = 0
	for _, p in ipairs(glyph) do
		maxX = math.max(maxX, p.x)
	end
	return maxX
end

-- `runs`, not a single flat `points` list: real cursive doesn't lift the
-- pen within a word, but a space still has to break the tube into a new,
-- unconnected run -- see WordPath's own comment below for why.
export type WordPathResult = { runs: { { Point2 } }, width: number }

-- Concatenates each letter's glyph into one continuous path, offsetting
-- each letter horizontally by the accumulated advance width -- genuine
-- cursive script doesn't lift the pen between letters, so consecutive
-- letters' point paths are just appended directly (MapBuilder.lua's
-- renderer connects every consecutive point with a tube segment, letter
-- boundaries included). A space is extra horizontal advance with no
-- glyph and, correctly, no connecting stroke drawn across the gap -- it
-- ends the current run and starts a new one, so MapBuilder.lua's renderer
-- never bridges a tube across a word gap (e.g. "VERY HARD").
function NeonScript.WordPath(word: string, letterSpacing: number): WordPathResult
	local runs: { { Point2 } } = {}
	local currentRun: { Point2 } = {}
	local advanceX = 0

	for i = 1, #word do
		local ch = word:sub(i, i):upper()
		if ch == " " then
			if #currentRun > 0 then
				table.insert(runs, currentRun)
				currentRun = {}
			end
			advanceX += letterSpacing * 3
		else
			local glyph = GLYPHS[ch]
			if glyph then
				for _, p in ipairs(glyph) do
					table.insert(currentRun, { x = p.x + advanceX, y = p.y })
				end
				advanceX += glyphWidth(glyph) + letterSpacing
			end
		end
	end

	if #currentRun > 0 then
		table.insert(runs, currentRun)
	end

	return { runs = runs, width = advanceX }
end

return NeonScript
