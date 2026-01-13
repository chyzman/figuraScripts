local chyzlib = {} -- made by chyzman

--- GLOBALS ----------------------------------------------------------------------------------

local TICK_LENGTH = 20;

--- UTIL -------------------------------------------------------------------------------------

---Applies variation to a base value
---@param base number
---@param variation number
---@return number
function chyzlib.applyVariation(base, variation)
    return base + (math.random() * 2 - 1) * variation
end

--- FACEPLATE --------------------------------------------------------------------------------

---@class chyzman.faceplate
---@field parts ModelPart|ModelPart[]
---@field config chyzman.faceplate.config
local faceplate = {}
faceplate.__index = faceplate

---@class chyzman.faceplate.config
---@field forceBlink boolean? -- force blink state (true = closed, false = open), nil = normal blinkin
---@field onActivate fun(self: chyzman.faceplate, faceObj: chyzman.face)? -- called when plate becomes active
---@field onDeactivate fun(self: chyzman.faceplate, faceObj: chyzman.face)? -- called when plate becomes inactive

---Creates a new faceplate
---@param parts ModelPart|ModelPart[]
---@param config chyzman.faceplate.config?
---@return chyzman.faceplate
function chyzlib.faceplate(parts, config)
    local obj = setmetatable({}, faceplate)
    obj.parts = type(parts) == "table" and parts or { parts }
    ---@class (partial) chyzman.faceplate.config
    obj.config = { -- default config
        forceBlink = nil,
        onActivate = nil,
        onDeactivate = nil
    }
    if config then
        obj:setConfig(config)
    end
    return obj
end

---Set faceplate config
---@param config chyzman.faceplate.config
---@return self
function faceplate:setConfig(config)
    for k, v in pairs(config) do
        self.config[k] = v
    end
    return self
end

---Set faceplate visibility
---@param visible boolean
---@return self
function faceplate:setVisible(visible)
    for _, part in ipairs(self.parts) do
        part:setVisible(visible)
    end
    return self
end

--- FACE -------------------------------------------------------------------------------------

---@class chyzman.face
---@field plates table<string, chyzman.faceplate>
---@field eyes ModelPart[]
---@field blinkPlate ModelPart[]
---@field config chyzman.face.config
local face = {}
face.__index = face

local activeFaces = {}

---@class chyzman.face.config
---@field blinkInterval number -- average SECONDS between blinks (default 6)
---@field blinkIntervalVariation number -- blink interval variation in SECONDS (default 2)
---@field blinkDuration number -- how long blinks last in SECONDS (default 1.5)
---@field blinkDurationVariation number -- blink duration variation in SECONDS (default 0)
---@field onBlinkStart fun(self: chyzman.face)? -- called when blink starts
---@field onBlinkEnd fun(self: chyzman.face)? -- called when blink ends

---Creates a new face
---@param eyes ModelPart|ModelPart[]?
---@param blinkPlate ModelPart|ModelPart[]?
---@param faceplates table<string, chyzman.faceplate>
---@param config chyzman.face.config?
---@return chyzman.face
function chyzlib.face(eyes, blinkPlate, faceplates, config)
    local obj = setmetatable({}, face)
    obj.eyes = eyes and (type(eyes) == "table" and eyes or { eyes }) or {}
    obj.blinkPlate = blinkPlate and (type(blinkPlate) == "table" and blinkPlate or { blinkPlate }) or {}
    obj.plates = faceplates or {}

    ---@class (partial) chyzman.face.config
    obj.config = { -- default config
        blinkInterval = 2,
        blinkIntervalVariation = 2,
        blinkDuration = 0.25,
        blinkDurationVariation = 0.1,
        onBlinkStart = nil,
        onBlinkEnd = nil
    }

    if config then
        obj:setConfig(config)
    end

    obj.currentPlate = next(faceplates)
    obj.blinking = false;
    obj.blinkTimer = obj:_chooseBlink()

    obj:_updateVisibility()
    activeFaces[obj] = obj
    return obj
end

---Set face config
---@param config chyzman.face.config
---@return self
function face:setConfig(config)
    for k, v in pairs(config) do
        self.config[k] = v
    end
    return self
end

---Set active faceplate
---@param plateName string
---@return self
function face:setFacePlate(plateName)
    if not self.plates[plateName] then
        error("Unknown faceplate: " .. plateName, 2)
    end

    if plateName == self.currentPlate then
        return self
    end

    local oldPlate = self.plates[self.currentPlate]
    if (oldPlate.config.onDeactivate) then
        oldPlate.config.onDeactivate(oldPlate, self)
    end

    local newPlate = self.plates[plateName]
    self.currentPlate = plateName
    if (newPlate.config.onActivate) then
        newPlate.config.onActivate(newPlate, self)
    end

    self:_updateVisibility()
    return self
end

---Get current faceplate
---@return chyzman.faceplate
function face:getCurrentPlate()
    return self.plates[self.currentPlate]
end

---Trigger a blink
function face:blink()
    self.blinking = true
    self.blinkTimer = 0
    return self
end

---Enable/Disable this face
---@param enabled boolean
---@return self
function face:setEnabled(enabled)
    activeFaces[self] = enabled and self or nil
    return self
end

---Chooses next blink timing
---@return number
function face:_chooseBlink()
    local base = self.blinking and self.config.blinkDuration or self.config.blinkInterval
    local variation = self.blinking and self.config.blinkDurationVariation or self.config.blinkIntervalVariation
    return math.floor(chyzlib.applyVariation(base, variation) * TICK_LENGTH)
end

function face:_updateVisibility()
    local target;
    for name, plate in pairs(self.plates) do
        if name ~= self.currentPlate then
            plate:setVisible(false)
        else
            target = plate
        end
    end
    target:setVisible(true)
    self:_updateEyeVisibility()
end

function face:_updateEyeVisibility()
    local currentPlate = self.plates[self.currentPlate]
    local eyeVisible = not (currentPlate.config.forceBlink or self.blinking)

    for _, eye in ipairs(self.eyes) do eye:setVisible(eyeVisible) end
    for _, blink in ipairs(self.blinkPlate) do blink:setVisible(not eyeVisible) end
end

function events.tick()
    if not next(activeFaces) then return end

    for face in pairs(activeFaces) do
        face.blinkTimer = face.blinkTimer - 1
        if face.blinkTimer <= 0 then
            face.blinking = not face.blinking
            face.blinkTimer = face:_chooseBlink()
            if face.blinking and face.config.onBlinkStart then
                face.config.onBlinkStart(face)
            elseif not face.blinking and face.config.onBlinkEnd then
                face.config.onBlinkEnd(face)
            end
        end
        face:_updateVisibility()
    end
end

return chyzlib
