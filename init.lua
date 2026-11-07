--- === BluetoothToggle ===
---
--- A simple Hammerspoon Spoon to quickly turn Bluetooth on and off using blueutil
---
--- Features:
---   - Toggle Bluetooth power with a hotkey (optional)
---   - Menubar icon for quick access (enabled by default)
---   - Optional on-screen alerts when toggling
---   - Optional custom sounds for on/off actions
---   - Reads current Bluetooth state from blueutil before each toggle
---   - Optional periodic refresh so menubar state follows manual changes

--- === BluetoothToggle:configure ===
--- Method
--- Configures the BluetoothToggle Spoon.
---
--- Parameters:
---  * opts - A table of options:
---    * blueutilPath (string) - Path to the blueutil binary (default: `blueutil`)
---    * enableMenubar (boolean) - Show menubar icon (default: true)
---    * hotkey (table) - Hotkey to toggle Bluetooth power (default: nil)
---    * enableAlert (boolean) - Show alert when toggling (default: false)
---    * menuIconSize (number|table|boolean) - Menubar icon size in points; number for square size, `{w=, h=}` table, or `false` to auto-size from menubar height (default: false)
---    * menuIconTemplate (boolean) - Render menubar icons as template images so macOS tints them to the menubar colour. Keeps icon colour when `false` (default: false)
---    * alertIconSize (number|table) - Alert icon size in points; number for square size or `{w=, h=}` table (default: 64)
---    * sounds (table) - Table with `off` and/or `on` sound file paths (default: nil)
---    * refreshInterval (number) - Seconds between menu refreshes; set to 0 to disable (default: 5)
---
--- Example:
---   hs.loadSpoon("BluetoothToggle")
---   spoon.BluetoothToggle:configure{
---     blueutilPath = "/opt/homebrew/bin/blueutil",
---     enableMenubar = true,
---     hotkey = {{"ctrl", "shift"}, "B"},
---     enableAlert = true,
---     menuIconSize = false,
---     refreshInterval = 5,
---     sounds = {
---       off = "/System/Library/Sounds/Bottle.aiff",
---       on = "/System/Library/Sounds/Pop.aiff"
---     }
---   }

--- === BluetoothToggle:toggleBluetooth ===
--- Method
--- Toggles Bluetooth power based on the current blueutil state.

--- === BluetoothToggle:turnBluetoothOff ===
--- Method
--- Turns Bluetooth off.

--- === BluetoothToggle:turnBluetoothOn ===
--- Method
--- Turns Bluetooth on.

local obj = {}
obj.__index = obj
obj.logger = hs.logger.new("BluetoothToggle", "info")

obj.name = "BluetoothToggle"
obj.version = "1.2.0" -- x-release-please-version
obj.author = "laluowen"
obj.license = "MIT - https://opensource.org/licenses/MIT"
obj.homepage = "https://github.com/laluowen/BluetoothToggle.spoon"

obj.blueutilPath = "blueutil"
obj.hotkey = nil
obj.enableMenubar = true
obj.bluetoothMenu = nil
obj.enableAlert = false
obj.menuIconSize = false
obj.menuIconTemplate = false
obj.alertIconSize = 64
obj.sounds = nil
obj.refreshInterval = 5
obj.menuRefreshTimer = nil
obj.resolvedBlueutilPath = nil
obj.sourceIcons = nil
obj.menuIcons = nil
obj.resolvedMenuIconSize = nil
obj.menuIconSizeRetryScheduled = false

local function shellQuote(value)
  return string.format("%q", value)
end

local function trim(value)
  if not value then return nil end
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function commandExists(path)
  local attr = hs.fs.attributes(path)
  return attr and attr.mode == "file"
end

local function getSpoonDirectory()
  local source = debug.getinfo(1, "S").source
  if not source then
    return nil
  end

  source = source:gsub("^@", "")
  return source:match("^(.*)/init%.lua$")
end

local function joinPath(base, child)
  if not base or base == "" then
    return child
  end
  return base .. "/" .. child
end

function obj:loadSourceIcons()
  if self.sourceIcons then
    return self.sourceIcons
  end

  local spoonDirectory = getSpoonDirectory()
  if not spoonDirectory then
    self.logger.w("Could not determine spoon directory for icon loading")
    return nil
  end

  local iconFiles = {
    on = "bluetooth-on.png",
    off = "bluetooth-off.png",
    unknown = "bluetooth-unknown.png",
  }

  local icons = {}
  for state, fileName in pairs(iconFiles) do
    local path = joinPath(spoonDirectory, fileName)
    self.logger.i("Loading menu icon for " .. state .. " state from " .. path)
    local image = hs.image.imageFromPath(path)
    if not image then
      self.logger.w("Failed to load menu icon: " .. path)
      return nil
    end
    icons[state] = image
  end

  self.sourceIcons = icons
  self.logger.i("Loaded Bluetooth source icons")
  return self.sourceIcons
end

function obj:normalizeIconSize(sizeValue, defaultSize)
  if type(sizeValue) == "number" then
    return { w = sizeValue, h = sizeValue }
  end

  if type(sizeValue) == "table" and sizeValue.w and sizeValue.h then
    return { w = sizeValue.w, h = sizeValue.h }
  end

  return { w = defaultSize, h = defaultSize }
end

function obj:getMenuIconSize()
  if self.resolvedMenuIconSize then
    return self.resolvedMenuIconSize
  end

  if self.menuIconSize ~= false then
    self.resolvedMenuIconSize = self:normalizeIconSize(self.menuIconSize, 18)
    self.logger.i("Using configured menubar icon size " .. tostring(self.resolvedMenuIconSize.w) .. "x" .. tostring(self.resolvedMenuIconSize.h))
    return self.resolvedMenuIconSize
  end

  if self.bluetoothMenu then
    local frame = self.bluetoothMenu:frame()
    if frame and frame.h and frame.h > 0 then
      -- NSStatusItem frame height includes vertical padding; keep glyph conservative.
      local derived = math.floor(frame.h * 0.6 + 0.5)
      derived = math.max(14, math.min(derived, 18))
      self.logger.i("Derived menubar icon size from frame height " .. tostring(frame.h) .. ": " .. tostring(derived))
      self.resolvedMenuIconSize = { w = derived, h = derived }
      return self.resolvedMenuIconSize
    end
  end

  self.logger.i("Menubar frame not ready; using temporary default 18")
  self.resolvedMenuIconSize = { w = 18, h = 18 }
  return self.resolvedMenuIconSize
end

function obj:scheduleMenuIconAutoSizeRetry()
  if self.menuIconSize ~= false then
    return
  end

  if self.menuIconSizeRetryScheduled then
    return
  end

  self.menuIconSizeRetryScheduled = true
  hs.timer.doAfter(0.25, function()
    self.menuIconSizeRetryScheduled = false
    self.resolvedMenuIconSize = nil
    self.menuIcons = nil
    self.logger.i("Retrying menubar icon auto-size after initial render")
    self:updateBluetoothMenu()
  end)
end

function obj:getAlertIconSize()
  return self:normalizeIconSize(self.alertIconSize, 64)
end

function obj:loadMenuIcons()
  local sourceIcons = self:loadSourceIcons()
  if not sourceIcons then
    return nil
  end

  local targetSize = self:getMenuIconSize()
  local cacheKey = string.format("%sx%s", tostring(targetSize.w), tostring(targetSize.h))
  if self.menuIcons and self.menuIcons.cacheKey == cacheKey then
    return self.menuIcons.icons
  end

  local icons = {}
  for state, image in pairs(sourceIcons) do
      local menuImage = image:copy()
    menuImage:size(targetSize, true)
    menuImage:template(self.menuIconTemplate)
    icons[state] = menuImage
  end

  self.menuIcons = {
    cacheKey = cacheKey,
    icons = icons,
  }
  self.logger.i("Prepared resized menubar icons at " .. cacheKey)
  return self.menuIcons.icons
end

function obj:getAlertIcon(iconState)
  local icons = self:loadSourceIcons()
  local image = icons and icons[iconState] or nil
  if not image then
    return nil
  end

  local alertImage = image:copy()
  alertImage:template(false)
  alertImage:size(self:getAlertIconSize(), true)
  return alertImage
end

function obj:showBluetoothAlert(message, iconState)
  local image = self:getAlertIcon(iconState)

  if image then
    hs.alert.showWithImage(message, image)
  else
    hs.alert.show(message)
  end
end

function obj:resolveBlueutilPath()
  self.logger.i("Resolving blueutil path")

  if self.blueutilPath and self.blueutilPath:find("/", 1, true) then
    self.logger.i("Checking configured absolute path: " .. tostring(self.blueutilPath))
    if commandExists(self.blueutilPath) then
      self.resolvedBlueutilPath = self.blueutilPath
      self.logger.i("Found blueutil at configured path: " .. tostring(self.resolvedBlueutilPath))
      return self.resolvedBlueutilPath
    end
    self.logger.w("Configured blueutilPath not found: " .. tostring(self.blueutilPath))
  else
    self.logger.i("No configured absolute blueutilPath; trying command lookup")
  end

  local output, status = hs.execute("command -v blueutil", true)
  self.logger.i("Ran command -v blueutil (status=" .. tostring(status) .. ") output=" .. tostring(trim(output) or "") )
  if status then
    local found = trim(output)
    if found and found ~= "" then
      self.resolvedBlueutilPath = found
      self.logger.i("Found blueutil via command lookup: " .. tostring(self.resolvedBlueutilPath))
      return self.resolvedBlueutilPath
    end
  end

  self.logger.w("command lookup did not return a usable path; falling back to common locations")

  local candidates = {
    "/opt/homebrew/bin/blueutil",
    "/usr/local/bin/blueutil",
    "/opt/homebrew/sbin/blueutil",
    "/usr/local/sbin/blueutil",
  }

  for _, candidate in ipairs(candidates) do
    self.logger.i("Checking fallback path: " .. candidate)
    if commandExists(candidate) then
      self.resolvedBlueutilPath = candidate
      self.logger.i("Found blueutil at fallback path: " .. tostring(self.resolvedBlueutilPath))
      return self.resolvedBlueutilPath
    end
  end

  self.resolvedBlueutilPath = nil
  self.logger.e("Could not resolve blueutil path")
  return nil
end

function obj:runBlueutil(args)
  local binary = self.resolvedBlueutilPath or self.blueutilPath
  local command = shellQuote(binary)
  if args and args ~= "" then
    command = command .. " " .. args
  end

  local output, status, statusType, returnCode = hs.execute(command .. " 2>&1", true)
  if not status then
    local failure = string.format(
      "blueutil command failed (type=%s rc=%s): %s",
      tostring(statusType),
      tostring(returnCode),
      trim(output) or "<no output>"
    )
    self.logger.e(failure)
    return nil, failure
  end

  return output
end

function obj:showActionableError(err)
  local msg = err or "Unknown bluetooth error"
  if msg:find("absence of access to Bluetooth AP", 1, true) then
    self:showBluetoothAlert("Enable Bluetooth access for Hammerspoon", "unknown")
    self.logger.e("Grant Bluetooth access: System Settings > Privacy & Security > Bluetooth > Hammerspoon")
    return
  end

  self:showBluetoothAlert("Bluetooth command failed", "unknown")
end

function obj:getBluetoothPowerState()
  local output, err = self:runBlueutil("-p")
  if not output then
    self.logger.e("Failed to read bluetooth power state: " .. tostring(err))
    return nil, err
  end

  local current = tonumber((output:gsub("%s+", "")))
  if current == nil then
    self.logger.e("Unexpected blueutil output for power state: " .. tostring(output))
    return nil, output
  end

  return current == 1
end

function obj:updateBluetoothMenu()
  if not self.bluetoothMenu then
    return
  end

  local icons = self:loadMenuIcons()

  local isPoweredOn = self:getBluetoothPowerState()
  if isPoweredOn == nil then
    if icons and icons.unknown then
      self.bluetoothMenu:setTitle(nil)
      self.bluetoothMenu:setIcon(icons.unknown, self.menuIconTemplate)
    else
      self.bluetoothMenu:setIcon(nil)
      self.bluetoothMenu:setTitle("BT?")
    end
    return
  end

  if isPoweredOn then
    if icons and icons.on then
      self.bluetoothMenu:setTitle(nil)
      self.bluetoothMenu:setIcon(icons.on, self.menuIconTemplate)
    else
      self.bluetoothMenu:setIcon(nil)
      self.bluetoothMenu:setTitle("BT")
    end
  else
    if icons and icons.off then
      self.bluetoothMenu:setTitle(nil)
      self.bluetoothMenu:setIcon(icons.off, self.menuIconTemplate)
    else
      self.bluetoothMenu:setIcon(nil)
      self.bluetoothMenu:setTitle("BT-")
    end
  end
end

function obj:setBluetoothPower(enabled)
  local target = enabled and 1 or 0
  local output, err = self:runBlueutil("-p " .. tostring(target))
  if not output then
    self.logger.e("Failed to set bluetooth power: " .. tostring(err))
    if self.enableAlert then
      self:showActionableError(err)
    end
    return false, err
  end

  self:updateBluetoothMenu()

  if self.sounds then
    local soundPath = enabled and self.sounds.on or self.sounds.off
    if soundPath then
      local sound = hs.sound.getByFile(soundPath)
      if sound then
        sound:play()
      end
    end
  end

  if self.enableAlert then
    self:showBluetoothAlert(enabled and "Bluetooth On" or "Bluetooth Off", enabled and "on" or "off")
  end

  return true
end

function obj:turnBluetoothOff()
  return self:setBluetoothPower(false)
end

function obj:turnBluetoothOn()
  return self:setBluetoothPower(true)
end

function obj:toggleBluetooth()
  local isPoweredOn, err = self:getBluetoothPowerState()
  if isPoweredOn == nil then
    self:updateBluetoothMenu()
    if self.enableAlert then
      self:showActionableError(err)
    end
    return false, err
  end

  return self:setBluetoothPower(not isPoweredOn)
end

function obj:checkPermissions()
  local output, err = self:runBlueutil("-p")
  if output then
    return true
  end
  if err and err:find("absence of access to Bluetooth AP", 1, true) then
    hs.alert.show("BluetoothToggle needs Bluetooth permission for Hammerspoon")
  else
    hs.alert.show("BluetoothToggle: blueutil failed, see console")
  end
  return false
end

function obj:bindHotkeys(mapping)
  if mapping and mapping.toggle then
    hs.hotkey.bind(mapping.toggle[1], mapping.toggle[2], function()
      self:toggleBluetooth()
    end)
  end
  return self
end

function obj:startRefreshTimer()
  if self.menuRefreshTimer then
    self.menuRefreshTimer:stop()
    self.menuRefreshTimer = nil
  end

  if self.enableMenubar and self.refreshInterval and self.refreshInterval > 0 then
    self.menuRefreshTimer = hs.timer.doEvery(self.refreshInterval, function()
      self:updateBluetoothMenu()
    end)
  end
end

function obj:start()
  self.logger.i("Using blueutil path: " .. tostring(self.resolvedBlueutilPath or self.blueutilPath))

  if self.enableMenubar then
    self.bluetoothMenu = hs.menubar.new()
    if self.bluetoothMenu then
      self.bluetoothMenu:setClickCallback(function()
        self:toggleBluetooth()
      end)
      self:updateBluetoothMenu()
      self:scheduleMenuIconAutoSizeRetry()
    end
  end

  self:startRefreshTimer()
  return self
end

function obj:init()
  -- For compatibility with SpoonInstall
end

function obj:configure(opts)
  if opts then
    if opts.blueutilPath then self.blueutilPath = opts.blueutilPath end
    if opts.enableMenubar ~= nil then self.enableMenubar = opts.enableMenubar end
    if opts.hotkey then self.hotkey = opts.hotkey end
    if opts.enableAlert ~= nil then self.enableAlert = opts.enableAlert end
    if opts.menuIconSize ~= nil then
      self.menuIconSize = opts.menuIconSize
      self.resolvedMenuIconSize = nil
      self.menuIcons = nil
    end
    if opts.alertIconSize ~= nil then self.alertIconSize = opts.alertIconSize end
    if opts.menuIconTemplate ~= nil then
      self.menuIconTemplate = opts.menuIconTemplate
      self.menuIcons = nil
    end
    if opts.sounds then self.sounds = opts.sounds end
    if opts.refreshInterval ~= nil then self.refreshInterval = opts.refreshInterval end
  end

  self:resolveBlueutilPath()
  self:checkPermissions()

  self:start()
  if self.hotkey then
    self:bindHotkeys({ toggle = self.hotkey })
  end
  return self
end

return obj
