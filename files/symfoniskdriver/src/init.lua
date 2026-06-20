-- IKEA SYMFONISK Sound Controller – SmartThings Edge Driver
-- Version: 1.0.0
--
-- Based on the original Groovy DTH by Juha Tanskanen (jusa80)
-- https://github.com/jusa80/smartthings
--
-- Ported to Edge (Lua) with AI assistance (Claude by Anthropic).
-- See AI_DISCLOSURE.md for details.
--
-- Supported actions:
--   1× press  → button.pushed
--   2× press  → button.pushed_2x
--   3× press  → button.pushed_3x
--   Knob turn → switchLevel.level (time-based, 4s = 100%)
--   Battery   → battery.battery (%)

local capabilities = require "st.capabilities"
local ZigbeeDriver = require "st.zigbee"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local device_mgmt  = require "st.zigbee.device_management"
local log          = require "log"

-- Use socket.gettime() for millisecond precision knob timing
local ok_sock, socket = pcall(require, "socket")
local function now()
  if ok_sock and socket.gettime then return socket.gettime() end
  return os.time()
end

local PowerConfig = zcl_clusters.PowerConfiguration
local OnOff       = zcl_clusters.OnOff
local Level       = zcl_clusters.Level

-- ---------------------------------------------------------------------------
-- ZCL body field helpers
-- The SmartThings Edge SDK parses ZCL command bodies into named fields.
-- Field names vary slightly across SDK versions, so we try all known variants.
-- ---------------------------------------------------------------------------
local MOVE_FIELDS = { "move_mode", "move_step_mode", "MoveMode", "MoveStepMode" }
local STEP_FIELDS = { "step_mode", "step_step_mode", "StepMode", "move_step_mode", "MoveStepMode" }

local function read_mode(body, fields, context)
  for _, name in ipairs(fields) do
    local v = body[name]
    if v ~= nil then
      local val = (type(v) == "table") and (v.value ~= nil and v.value or v[1]) or v
      log.debug(string.format("[SYMFONISK] %s: field '%s' = %s", context, name, tostring(val)))
      return val
    end
  end
  -- Fallback: raw bytes (older SDK versions)
  local b = body.body_bytes
  if b ~= nil then
    if type(b) == "string" then return string.byte(b, 1) end
    if type(b) == "table"  then return b[1] end
  end
  log.warn("[SYMFONISK] " .. context .. ": could not read mode, body fields:")
  for k, v in pairs(body) do
    log.warn(string.format("[SYMFONISK]   .%s = %s", tostring(k), tostring(v)))
  end
  return nil
end

-- Normalize mode value to boolean: true = Up/clockwise, false = Down/counter-clockwise
local function is_up(mode)
  if mode == nil then return true end
  if mode == 0 or mode == 0x00 then return true end
  if mode == 1 or mode == 0x01 then return false end
  if type(mode) == "string" then return mode:upper():find("UP") ~= nil end
  if type(mode) == "table" and mode.value ~= nil then return is_up(mode.value) end
  return true
end

-- ---------------------------------------------------------------------------
-- Knob handlers (Level cluster)
-- The SYMFONISK sends Move when turning starts, Stop when it ends.
-- We record the start time and direction, then calculate the level delta on Stop.
-- ---------------------------------------------------------------------------
local function move_handler(driver, device, zb_rx)
  local body = zb_rx.body.zcl_body
  local mode = read_mode(body, MOVE_FIELDS, "move_handler")
  local up   = is_up(mode)
  device:set_field("move_start", now())
  device:set_field("move_dir",   up and 1 or -1)
  log.debug("[SYMFONISK] knob " .. (up and "right ↑" or "left ↓"))
end

local function stop_handler(driver, device, zb_rx)
  local t0  = device:get_field("move_start")
  local dir = device:get_field("move_dir") or 1
  if not t0 then return end

  local elapsed = math.min(now() - t0, 4.0)             -- cap at 4s = 100%
  local delta   = math.floor(elapsed / 4.0 * 100) * dir
  local current = device:get_field("current_level") or 0
  local new_lvl = math.max(0, math.min(100, current + delta))

  device:set_field("current_level", new_lvl)
  device:set_field("move_start", nil)
  device:emit_event(capabilities.switchLevel.level(new_lvl))
  log.info(string.format("[SYMFONISK] level → %d%% (%.2fs, delta=%+d)", new_lvl, elapsed, delta))
end

-- ---------------------------------------------------------------------------
-- Button handlers
-- ---------------------------------------------------------------------------

-- OnOff cluster Toggle (0x02) → single press
local function toggle_handler(driver, device, zb_rx)
  log.debug("[SYMFONISK] button: pushed")
  device:emit_event(capabilities.button.button({ value = "pushed" }, { state_change = true }))
end

-- Level cluster Step (0x02) → double or triple press
-- Step Up (mode=0) = double press, Step Down (mode=1) = triple press
local function step_handler(driver, device, zb_rx)
  local body = zb_rx.body.zcl_body
  local mode = read_mode(body, STEP_FIELDS, "step_handler")
  local val  = is_up(mode) and "pushed_2x" or "pushed_3x"
  log.debug("[SYMFONISK] button: " .. val)
  device:emit_event(capabilities.button.button({ value = val }, { state_change = true }))
end

-- ---------------------------------------------------------------------------
-- Battery
-- Attribute 0x0021 (BatteryPercentageRemaining): range 0–200, where 200 = 100%
-- ---------------------------------------------------------------------------
local function battery_handler(driver, device, value, zb_rx)
  local pct = math.floor(value.value / 2)
  device:emit_event(capabilities.battery.battery(pct))
  log.debug("[SYMFONISK] battery: " .. pct .. "%")
end

-- ---------------------------------------------------------------------------
-- Hub EUI helper
-- driver:get_hub_zigbee_eui() may return nil during early startup;
-- we fall back to environment_info fields if available.
-- ---------------------------------------------------------------------------
local function get_hub_eui(driver)
  do
    local ok, v = pcall(function() return driver:get_hub_zigbee_eui() end)
    if ok and v then return v end
  end
  if type(driver.environment_info) == "table" then
    local e = driver.environment_info
    if e.hub_zigbee_eui then return e.hub_zigbee_eui end
    if e.hub_zigbee_id  then return e.hub_zigbee_id  end
  end
  if driver.hub_zigbee_eui then return driver.hub_zigbee_eui end
  if driver.hub_zigbee_id  then return driver.hub_zigbee_id  end
  return nil
end

local function send_bind(device, cluster_id, hub_eui)
  -- Try with explicit hub EUI first, fall back to implicit (newer SDK)
  if hub_eui then
    local ok = pcall(function()
      device:send(device_mgmt.build_bind_request(device, cluster_id, hub_eui))
    end)
    if ok then
      log.info(string.format("[SYMFONISK] bind OK (with EUI)  cluster 0x%04X", cluster_id))
      return
    end
  end
  local ok, err = pcall(function()
    device:send(device_mgmt.build_bind_request(device, cluster_id))
  end)
  if ok then
    log.info(string.format("[SYMFONISK] bind OK (no EUI)    cluster 0x%04X", cluster_id))
  else
    log.error(string.format("[SYMFONISK] bind FAILED cluster 0x%04X: %s", cluster_id, tostring(err)))
  end
end

-- ---------------------------------------------------------------------------
-- Configuration: bind output clusters to hub + configure battery reporting
-- Called on: init (driver start), added (first pairing), doConfigure
-- ---------------------------------------------------------------------------
local function do_configure(driver, device)
  log.info("[SYMFONISK] configuring device...")
  local hub_eui = get_hub_eui(driver)

  send_bind(device, OnOff.ID,       hub_eui)
  send_bind(device, Level.ID,       hub_eui)
  send_bind(device, PowerConfig.ID, hub_eui)

  pcall(function()
    device:send(PowerConfig.attributes.BatteryPercentageRemaining:configure_reporting(
      device, 30, 21600, 1))
    device:send(PowerConfig.attributes.BatteryPercentageRemaining:read(device))
  end)

  -- Retry bindings after 8s in case the Zigbee stack wasn't fully ready
  driver:call_with_delay(8, function()
    local eui = get_hub_eui(driver)
    send_bind(device, OnOff.ID, eui)
    send_bind(device, Level.ID, eui)
  end)
end

-- ---------------------------------------------------------------------------
-- Lifecycle: device added (called immediately after pairing)
-- ---------------------------------------------------------------------------
local function device_added(driver, device)
  log.info("[SYMFONISK] device added, initialising...")
  device:emit_event(capabilities.button.supportedButtonValues(
    { "pushed", "pushed_2x", "pushed_3x" }, { visibility = { displayed = false } }))
  device:emit_event(
    capabilities.button.numberOfButtons({ value = 1 }, { visibility = { displayed = false } }))
  device:emit_event(capabilities.button.button({ value = "pushed" }, { state_change = false }))
  device:emit_event(capabilities.switchLevel.level(0))
  device:set_field("current_level", 0)
  do_configure(driver, device)
end

-- ---------------------------------------------------------------------------
-- Driver
-- ---------------------------------------------------------------------------
local driver = ZigbeeDriver("symfonisk-sound", {
  health_check = false,

  supported_capabilities = {
    capabilities.button,
    capabilities.battery,
    capabilities.refresh,
    capabilities.switchLevel,
  },

  lifecycle_handlers = {
    init        = do_configure,
    added       = device_added,
    doConfigure = do_configure,
  },

  zigbee_handlers = {
    attr = {
      [PowerConfig.ID] = {
        [PowerConfig.attributes.BatteryPercentageRemaining.ID] = battery_handler,
      },
    },
    cluster = {
      [OnOff.ID] = {
        [0x02] = toggle_handler,  -- Toggle → single press
      },
      [Level.ID] = {
        [0x01] = move_handler,    -- Move  → knob turning
        [0x02] = step_handler,    -- Step  → double / triple press
        [0x03] = stop_handler,    -- Stop  → knob released
        [0x07] = stop_handler,    -- Stop with on/off (some firmware versions)
      },
    },
  },

  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = function(driver, device)
        device:send(PowerConfig.attributes.BatteryPercentageRemaining:read(device))
      end,
    },
    [capabilities.switchLevel.ID] = {
      [capabilities.switchLevel.commands.setLevel.NAME] = function(driver, device, cmd)
        local lvl = math.max(0, math.min(100, cmd.args.level))
        device:set_field("current_level", lvl)
        device:emit_event(capabilities.switchLevel.level(lvl))
      end,
    },
  },
})

driver:run()
