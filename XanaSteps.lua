-- XanaSteps
-- Shows the current and next steps of the active RestedXP guide as numbered
-- pins on the world map and the minimap. Nothing else: no arrow, no routes,
-- no HUD.
--
-- The steps are read from RestedXP Guides (RXPGuides) at runtime. Positions are
-- worked out with Blizzard's C_Map API rather than RXPGuides' own map library,
-- whose coordinates don't line up with every map in WoW Forever.

local ADDON = ...

local MAX_STEPS = 6            -- steps shown: the current one(s) plus the next ones
local WORLD_PIN_SIZE = 22      -- on screen, at any world map zoom
local MINIMAP_PIN_SIZE = 16
local WORLD_REFRESH = 0.25     -- seconds between world map redraws while it is open
local MINIMAP_REFRESH = 0.05   -- seconds between minimap redraws (follows the player)
local STEPS_REFRESH = 0.5      -- seconds between re-reading the guide's steps

local COLOR_CURRENT = { 1, 0.82, 0 }      -- gold
local COLOR_NEXT = { 0.35, 0.7, 1 }       -- blue
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

-- Minimap diameter in yards for each zoom level (0-5), as used by the
-- HereBeDragons library for Classic-era clients.
local MINIMAP_YARDS = {
	outdoor = { 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 },
	indoor = { 300, 240, 180, 120, 80, 50 },
}

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33bbffXanaSteps:|r " .. tostring(msg))
end

---------------------------------------------------------------------------
-- Reading the guide
---------------------------------------------------------------------------
-- RXPGuides' own addon table (its global RXPGuides table is only a small
-- public API without the guide state).
local function RXP()
	local ace = LibStub and LibStub("AceAddon-3.0", true)
	return ace and ace:GetAddon("RXPGuides", true)
end

-- A step element's map position: uiMapID and 0-1 coordinates.
local function ElementPosition(e)
	if e.hidePin or e.skip then return nil end
	local mapID, x, y = tonumber(e.zone), tonumber(e.x), tonumber(e.y)
	if not (mapID and x and y) then return nil end
	return mapID, x / 100, y / 100   -- RXPGuides keeps x and y as 0-100
end

-- The active steps and the steps after them, up to MAX_STEPS steps that have a
-- position. Each entry: { index, step, current, positions = { {map, x, y} } }
--
-- RXPGuides clears `completed` on the steps it moves past, so finished steps
-- look like unreached ones. The guide's position is therefore taken from the
-- last active step: active "sticky" steps can sit earlier in the guide, but
-- the step the guide is on is always the last active one. Steps before it are
-- shown only while they are active (sticky); steps after it unless they are
-- already completed or skipped.
local function ReadSteps()
	local rxp = RXP()
	local guide = rxp and rxp.currentGuide
	if not (guide and guide.steps) then return {} end
	local currentIndex
	for index, step in ipairs(guide.steps) do
		if step.active then currentIndex = index end
	end
	if not currentIndex then return {} end
	local skipped = (RXPCData and RXPCData.stepSkip) or {}
	local list = {}
	for index, step in ipairs(guide.steps) do
		local show
		if index <= currentIndex then
			show = step.active and not step.completed
		else
			show = not step.completed and not skipped[index]
		end
		if show then
			local positions = {}
			for _, e in ipairs(step.elements or {}) do
				local mapID, x, y = ElementPosition(e)
				if mapID then positions[#positions + 1] = { mapID, x, y } end
			end
			if #positions > 0 then
				list[#list + 1] = { index = index, step = step, current = step.active and true or false,
				                    positions = positions }
				if #list >= MAX_STEPS then break end
			end
		end
	end
	return list
end

-- Both maps redraw far more often than the guide changes, so the step list is
-- re-read at most every STEPS_REFRESH seconds.
local cachedSteps, stepsReadAt = {}, -math.huge
local function UpcomingSteps()
	local now = GetTime()
	if now - stepsReadAt >= STEPS_REFRESH then
		cachedSteps, stepsReadAt = ReadSteps(), now
	end
	return cachedSteps
end

---------------------------------------------------------------------------
-- Map positions
---------------------------------------------------------------------------
local function XY(pos)
	if not pos then return nil end
	if pos.GetXY then return pos:GetXY() end
	return pos.x, pos.y
end

local function Vector(x, y)
	return CreateVector2D and CreateVector2D(x, y) or { x = x, y = y }
end

local function WorldPos(mapID, x, y)
	if not (C_Map and C_Map.GetWorldPosFromMapPos) then return nil end
	local ok, continent, world = pcall(C_Map.GetWorldPosFromMapPos, mapID, Vector(x, y))
	if ok and continent and world then return continent, world end
	return nil
end

-- Position of (mapID, x, y) on another map. Coordinates outside 0-1 (beyond
-- that map's edges) are returned only when `outside` is true.
local function PositionOn(targetMap, mapID, x, y, outside)
	local px, py
	if mapID == targetMap then
		px, py = x, y
	else
		if not (C_Map and C_Map.GetMapPosFromWorldPos) then return nil end
		local continent, world = WorldPos(mapID, x, y)
		if not continent then return nil end
		local ok, _, pos = pcall(C_Map.GetMapPosFromWorldPos, continent, world, targetMap)
		if not ok then return nil end
		px, py = XY(pos)
		if not (px and py) then return nil end
	end
	if outside or (px >= 0 and px <= 1 and py >= 0 and py <= 1) then return px, py end
	return nil
end

-- A map's width and height in yards: the world distance between its corners.
-- Measured rather than assumed, so it doesn't matter which way the world axes run.
local mapYards = {}
local function MapYards(mapID)
	local size = mapYards[mapID]
	if size == nil then
		size = false
		local c0, w0 = WorldPos(mapID, 0, 0)
		local c1, w1 = WorldPos(mapID, 1, 0)
		local c2, w2 = WorldPos(mapID, 0, 1)
		if c0 and c1 and c2 then
			local x0, y0 = XY(w0)
			local x1, y1 = XY(w1)
			local x2, y2 = XY(w2)
			local width = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
			local height = math.sqrt((x2 - x0) ^ 2 + (y2 - y0) ^ 2)
			if width > 0 and height > 0 then size = { width, height } end
		end
		mapYards[mapID] = size
	end
	if size then return size[1], size[2] end
	return nil
end

---------------------------------------------------------------------------
-- Pins (shared by both maps)
---------------------------------------------------------------------------
local function PinOnEnter(pin)
	local data = pin.data
	if not data then return end
	GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
	GameTooltip:AddLine(("Step %d%s"):format(data.index, data.current and " (current)" or ""), 1, 0.82, 0)
	for _, e in ipairs(data.step.elements or {}) do
		local text = e.mapTooltip or e.tooltipText or e.text
		if type(text) == "string" and text ~= "" then
			GameTooltip:AddLine(text, 1, 1, 1, true)
		end
	end
	GameTooltip:Show()
end

local function PinOnLeave()
	GameTooltip:Hide()
end

local function CreatePin(parent, size)
	local pin = CreateFrame("Frame", nil, parent)
	pin:SetSize(size, size)
	pin:EnableMouse(true)

	pin.edge = pin:CreateTexture(nil, "ARTWORK", nil, 1)
	pin.edge:SetTexture(CIRCLE)
	pin.edge:SetVertexColor(0, 0, 0, 0.9)
	pin.edge:SetPoint("CENTER")
	pin.edge:SetSize(size, size)

	pin.fill = pin:CreateTexture(nil, "ARTWORK", nil, 2)
	pin.fill:SetTexture(CIRCLE)
	pin.fill:SetPoint("CENTER")
	pin.fill:SetSize(size - 4, size - 4)

	pin.number = pin:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	if size < 20 then -- smaller digits so three of them still fit
		local font, _, flags = pin.number:GetFont()
		if font then pin.number:SetFont(font, 8, flags) end
	end
	pin.number:SetPoint("CENTER", 0, 0)
	pin.number:SetTextColor(0, 0, 0)

	pin:SetScript("OnEnter", PinOnEnter)
	pin:SetScript("OnLeave", PinOnLeave)
	return pin
end

-- A set of pins on one parent frame, reused from redraw to redraw.
local function NewPinSet(size)
	local set = { pins = {}, used = 0, size = size }

	function set:Begin(parent)
		if parent ~= self.parent then
			for _, pin in ipairs(self.pins) do pin:Hide() end
			self.parent, self.pins = parent, {}
		end
		self.used = 0
	end

	function set:Add(data, alpha)
		self.used = self.used + 1
		local pin = self.pins[self.used] or CreatePin(self.parent, self.size)
		self.pins[self.used] = pin
		local color = data.current and COLOR_CURRENT or COLOR_NEXT
		pin.data = data
		pin.fill:SetVertexColor(color[1], color[2], color[3], 1)
		pin.number:SetText(data.index)
		pin:SetAlpha(alpha or (data.current and 1 or 0.85))
		pin:SetFrameLevel(self.parent:GetFrameLevel() + self.used)
		pin:ClearAllPoints()
		pin:Show()
		return pin
	end

	function set:Finish()
		for i = self.used + 1, #self.pins do self.pins[i]:Hide() end
	end

	return set
end

---------------------------------------------------------------------------
-- World map
---------------------------------------------------------------------------
local worldPins = NewPinSet(WORLD_PIN_SIZE)
local worldOverlay, worldCanvas

local function WorldCanvas()
	local sc = WorldMapFrame and WorldMapFrame.ScrollContainer
	if not sc then return nil end
	return sc.Child or (sc.GetScrollChild and sc:GetScrollChild()) or nil
end

local function CanvasScale()
	local sc = WorldMapFrame.ScrollContainer
	local scale = sc and sc.GetCanvasScale and sc:GetCanvasScale()
	if type(scale) == "number" and scale > 0 then return scale end
	return 1
end

local function RedrawWorld()
	if not (WorldMapFrame and WorldMapFrame:IsShown()) then return end
	local canvas = WorldCanvas()
	if not canvas then return end
	if canvas ~= worldCanvas then
		worldCanvas = canvas
		worldOverlay = CreateFrame("Frame", nil, canvas)
		worldOverlay:SetAllPoints(canvas)
		worldOverlay:SetFrameStrata("HIGH")
		worldOverlay:SetFrameLevel((canvas:GetFrameLevel() or 1) + 20)
	end
	worldPins:Begin(worldOverlay)

	local shownMap = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
	local width, height = worldOverlay:GetWidth(), worldOverlay:GetHeight()
	if shownMap and width and width >= 10 then
		local pinScale = 1 / CanvasScale()
		-- Later steps first, so the current step's pins are drawn on top.
		local steps = UpcomingSteps()
		for s = #steps, 1, -1 do
			local data = steps[s]
			for _, p in ipairs(data.positions) do
				local x, y = PositionOn(shownMap, p[1], p[2], p[3])
				if x then
					local pin = worldPins:Add(data)
					pin:SetScale(pinScale)
					pin:SetPoint("CENTER", worldOverlay, "TOPLEFT", x * width / pinScale, -y * height / pinScale)
				end
			end
		end
	end
	worldPins:Finish()
end

---------------------------------------------------------------------------
-- Minimap
---------------------------------------------------------------------------
local minimapPins = NewPinSet(MINIMAP_PIN_SIZE)

local function MinimapDiameterYards()
	local zoom = (Minimap.GetZoom and Minimap:GetZoom() or 0) + 1
	local sizes = (IsIndoors and IsIndoors()) and MINIMAP_YARDS.indoor or MINIMAP_YARDS.outdoor
	return sizes[zoom] or sizes[1]
end

local function MinimapRotates()
	return GetCVar and GetCVar("rotateMinimap") == "1"
end

local function RedrawMinimap()
	if not (Minimap and Minimap:IsVisible()) then return end
	minimapPins:Begin(Minimap)

	local playerMap = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	local player = playerMap and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(playerMap, "player")
	local px, py = XY(player)
	local mapWidth, mapHeight
	if px and py then mapWidth, mapHeight = MapYards(playerMap) end

	if mapWidth then
		local radius = Minimap:GetWidth() / 2
		local pixelsPerYard = Minimap:GetWidth() / MinimapDiameterYards()
		local facing = MinimapRotates() and GetPlayerFacing and GetPlayerFacing()
		-- Facing can be unavailable (nil) or hidden from addons (a secret value).
		if type(facing) ~= "number" or (issecretvalue and issecretvalue(facing)) then facing = nil end
		local sinF, cosF = facing and math.sin(facing) or 0, facing and math.cos(facing) or 1
		local edge = radius - MINIMAP_PIN_SIZE / 2

		local steps = UpcomingSteps()
		for s = #steps, 1, -1 do
			local data = steps[s]
			for _, p in ipairs(data.positions) do
				local tx, ty = PositionOn(playerMap, p[1], p[2], p[3], true)
				if tx then
					-- Offset in pixels: east = +x, north = +y (map y runs south).
					local east = (tx - px) * mapWidth * pixelsPerYard
					local north = -(ty - py) * mapHeight * pixelsPerYard
					-- A rotating minimap turns with the player, so their facing points up.
					local x = east * cosF + north * sinF
					local y = -east * sinF + north * cosF
					local distance = math.sqrt(x * x + y * y)
					local alpha
					if distance > edge then
						-- Off the minimap: the current step stays at the edge, dimmed,
						-- as a pointer; later steps aren't shown.
						if data.current then
							x, y, alpha = x / distance * edge, y / distance * edge, 0.6
						end
					end
					if distance <= edge or data.current then
						local pin = minimapPins:Add(data, alpha)
						pin:SetPoint("CENTER", Minimap, "CENTER", x, y)
					end
				end
			end
		end
	end
	minimapPins:Finish()
end

---------------------------------------------------------------------------
-- Drivers
---------------------------------------------------------------------------
local function Guarded(name, fn, frame)
	local ok, err = pcall(fn)
	if not ok then
		frame:Hide()
		Print(name .. " pins stopped after an error: " .. tostring(err))
	end
end

-- World map: redraw a few times a second while it is open. That covers
-- changing maps, zooming and guide progress without hooking any of them.
local worldDriver = CreateFrame("Frame")
worldDriver:Hide()
local worldElapsed = 0
worldDriver:SetScript("OnUpdate", function(self, dt)
	worldElapsed = worldElapsed + dt
	if worldElapsed < WORLD_REFRESH then return end
	worldElapsed = 0
	Guarded("World map", RedrawWorld, self)
end)

-- Minimap: redraw often, so the pins move smoothly as the player moves and turns.
local minimapDriver = CreateFrame("Frame")
minimapDriver:Hide()
local minimapElapsed = 0
minimapDriver:SetScript("OnUpdate", function(self, dt)
	minimapElapsed = minimapElapsed + dt
	if minimapElapsed < MINIMAP_REFRESH then return end
	minimapElapsed = 0
	Guarded("Minimap", RedrawMinimap, self)
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_ACTION_FORBIDDEN")
events:RegisterEvent("ADDON_ACTION_BLOCKED")
events:SetScript("OnEvent", function(_, event, addon, fn)
	if event == "PLAYER_LOGIN" then
		if not RXP() then
			Print("RestedXP Guides isn't loaded - nothing to show.")
			return
		end
		if WorldMapFrame then
			WorldMapFrame:HookScript("OnShow", function()
				worldElapsed = WORLD_REFRESH -- draw on the first frame
				worldDriver:Show()
			end)
			WorldMapFrame:HookScript("OnHide", function() worldDriver:Hide() end)
			if WorldMapFrame:IsShown() then worldDriver:Show() end
		end
		if Minimap then minimapDriver:Show() end
	elseif addon == ADDON then
		Print(("%s: the game blocked %s"):format(event, tostring(fn)))
	end
end)
