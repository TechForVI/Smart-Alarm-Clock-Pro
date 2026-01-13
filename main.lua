require "import"
import "android.content.*"
import "android.widget.*"
import "android.view.*"
import "android.preference.PreferenceManager"
import "android.net.Uri"
import "android.media.MediaPlayer"
import "android.os.Environment"
import "android.media.RingtoneManager"
import "java.io.File"
import "java.util.Calendar"
import "android.media.AudioManager"
import "android.os.Vibrator"
import "java.io.FileInputStream"
import "java.io.FileOutputStream"

local prefs = PreferenceManager.getDefaultSharedPreferences(service)
local edit = prefs.edit()

local mainDialog = nil
alarm_data = {}
current_alarm_id = 0
currentMediaPlayer = nil
currentAlertDialog = nil

local ALARM_DURATION_DEFAULT = 30000
local SNOOZE_DURATION_DEFAULT = 5
local SNOOZE_REPEAT_COUNT_DEFAULT = 3
local VIBRATE_MODE_DEFAULT = "Medium"
local VIBRATE_ENABLED_DEFAULT = true
local SOUND_ENABLED_DEFAULT = true
local CURRENT_SOUND_DEFAULT = "Default Alarm Sound"

local alarmDuration = ALARM_DURATION_DEFAULT
local snoozeDuration = SNOOZE_DURATION_DEFAULT
local snoozeRepeatCount = SNOOZE_REPEAT_COUNT_DEFAULT
local snoozeEnabled = true
local vibrateEnabled = VIBRATE_ENABLED_DEFAULT
local vibrateMode = VIBRATE_MODE_DEFAULT
local current_sound = CURRENT_SOUND_DEFAULT
local current_sound_enabled = SOUND_ENABLED_DEFAULT

local vibrator = service.getSystemService(service.VIBRATOR_SERVICE)
local vibrationPatterns = {
 Low = {0, 500, 1500},
 Medium = {0, 1000, 1000},
 High = {0, 2000, 500}
}
local vibrationPattern = vibrationPatterns[vibrateMode] or vibrationPatterns.Medium
local vibrationRepeatIndex = 0

local days_of_week = {"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"}
local days_of_week_short = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"}

local DESTINATION_FOLDER = Environment.getExternalStorageDirectory().getPath() .. "/Download/Smart Alarm Clock Sound"

-- Auto Update Variables
local CURRENT_VERSION = "1.1"
local GITHUB_RAW_URL = "https://raw.githubusercontent.com/TechForVI/Smart-Alarm-Clock-Pr/main/"
local VERSION_URL = GITHUB_RAW_URL .. "version.txt"
local SCRIPT_URL = GITHUB_RAW_URL .. "main.lua"
local PLUGIN_PATH = "/sdcard/解说/Plugins/Smart Alarm Clock Pr/main.lua"
local updateInProgress = false
local updateDlg = nil
local updateAvailable = false

function checkUpdate(manualCheck)
 if updateInProgress then 
  if manualCheck then
   service.speak("Update check already in progress")
  end
  return 
 end
 
 local checkType = manualCheck and "manual" or "auto"
 
 Http.get(VERSION_URL, function(code, onlineVersion)
  if code == 200 and onlineVersion then
   onlineVersion = tostring(onlineVersion):match("^%s*(.-)%s*$")
   if onlineVersion and onlineVersion ~= CURRENT_VERSION then
    updateAvailable = true
    if manualCheck then
     showUpdateDialog(onlineVersion)
    else
     updateMainDialogButton()
    end
   else
    updateAvailable = false
    if manualCheck then
     local noUpdateDlg = LuaDialog(service)
     noUpdateDlg.setTitle("Update Status")
     noUpdateDlg.setMessage("You have the latest version (" .. CURRENT_VERSION .. "). No update available.")
     noUpdateDlg.setButton("OK", function()
      noUpdateDlg.dismiss()
      service.speak("You have the latest version")
     end)
     noUpdateDlg.show()
    end
    updateMainDialogButton()
   end
  else
   if manualCheck then
    local errorDlg = LuaDialog(service)
    errorDlg.setTitle("Update Check Failed")
    errorDlg.setMessage("Could not check for updates. Please check your internet connection.")
    errorDlg.setButton("OK", function()
     errorDlg.dismiss()
     service.speak("Update check failed")
    end)
    errorDlg.show()
   end
  end
  updateInProgress = false
 end)
end

function showUpdateDialog(onlineVersion)
 updateDlg = LuaDialog(service)
 updateDlg.setTitle("New Update Available!")
 updateDlg.setMessage("Current Version: " .. CURRENT_VERSION .. "\nNew Version: " .. onlineVersion .. "\n\nWould you like to update now?")
 
 updateDlg.setButton("Update Now", function()
  updateDlg.dismiss()
  service.speak("Downloading update, please wait...")
  downloadAndInstallUpdate()
 end)
 
 updateDlg.setButton2("Later", function()
  updateDlg.dismiss()
  service.speak("Update postponed")
 end)
 
 updateDlg.show()
end

function downloadAndInstallUpdate()
 updateInProgress = true
 
 local function performUpdate()
  Http.get(SCRIPT_URL, function(code, newContent)
   if code == 200 and newContent then
    local tempPath = PLUGIN_PATH .. ".temp_update"
    local backupPath = PLUGIN_PATH .. ".backup"
    
    local function restoreFromBackup()
     if File(backupPath).exists() then
      os.rename(backupPath, PLUGIN_PATH)
      return true
     end
     return false
    end
    
    local function cleanupFiles()
     pcall(function() os.remove(tempPath) end)
     pcall(function() os.remove(backupPath) end)
    end
    
    local f = io.open(tempPath, "w")
    if f then
     f:write(newContent)
     f:close()
     
     if File(PLUGIN_PATH).exists() then
      local backupFile = io.open(PLUGIN_PATH, "r")
      if backupFile then
       local backupContent = backupFile:read("*a")
       backupFile:close()
       local bf = io.open(backupPath, "w")
       if bf then
        bf:write(backupContent)
        bf:close()
       end
      end
     end
     
     local success = pcall(function()
      os.remove(PLUGIN_PATH)
      os.rename(tempPath, PLUGIN_PATH)
     end)
     
     if success then
      cleanupFiles()
      
      local successDialog = LuaDialog(service)
      successDialog.setTitle("Update Successful")
      successDialog.setMessage("Please restart the plugin.")
      successDialog.setButton("OK", function()
       successDialog.dismiss()
       service.speak("Update successful. Please restart plugin.")
       
       local handler = luajava.bindClass("android.os.Handler")(service.getMainLooper())
       handler.postDelayed(luajava.createProxy("java.lang.Runnable", {
        run = function()
         if mainDialog and mainDialog.dismiss then
          mainDialog.dismiss()
         end
        end
       }), 1000)
      end)
      successDialog.show()
     else
      local restored = restoreFromBackup()
      cleanupFiles()
      
      local errorDialog = LuaDialog(service)
      if restored then
       errorDialog.setTitle("Update Failed")
       errorDialog.setMessage("Update failed. Old version restored.")
      else
       errorDialog.setTitle("Update Failed")
       errorDialog.setMessage("Update failed. Please try again.")
      end
      errorDialog.setButton("OK", function()
       errorDialog.dismiss()
       if restored then
        service.speak("Update failed, old version restored.")
       else
        service.speak("Update failed, please try again.")
       end
      end)
      errorDialog.show()
     end
    else
     local errorDialog = LuaDialog(service)
     errorDialog.setTitle("Update Failed")
     errorDialog.setMessage("Cannot write temporary file.")
     errorDialog.setButton("OK", function()
      errorDialog.dismiss()
      service.speak("Update failed, cannot write file.")
     end)
     errorDialog.show()
    end
   else
    local errorDialog = LuaDialog(service)
    errorDialog.setTitle("Update Failed")
    errorDialog.setMessage("Cannot download new script.")
    errorDialog.setButton("OK", function()
     errorDialog.dismiss()
     service.speak("Update failed, download error.")
    end)
    errorDialog.show()
   end
   updateInProgress = false
  end)
 end
 
 performUpdate()
end

function updateMainDialogButton()
 if mainDialog then
  service.postExecute(100, "update_button_text", nil, function()
   local checkUpdateButton = mainDialog.findViewById(android.R.id.content).getRootView().findViewWithTag("checkUpdateButton")
   if checkUpdateButton then
    if updateAvailable then
     checkUpdateButton.setText("New Update Available")
    else
     checkUpdateButton.setText("Check Update")
    end
   end
  end)
 end
end

function load_user_settings()
 alarmDuration = prefs.getLong("alarm_duration", ALARM_DURATION_DEFAULT)
 snoozeDuration = prefs.getInt("snooze_duration", SNOOZE_DURATION_DEFAULT)
 snoozeRepeatCount = prefs.getInt("snooze_repeat_count", SNOOZE_REPEAT_COUNT_DEFAULT)
 snoozeEnabled = prefs.getBoolean("snooze_enabled", true)
 vibrateMode = prefs.getString("vibrate_mode", VIBRATE_MODE_DEFAULT)
 vibrateEnabled = prefs.getBoolean("vibrate_enabled", VIBRATE_ENABLED_DEFAULT)
 current_sound = prefs.getString("current_sound", CURRENT_SOUND_DEFAULT)
 current_sound_enabled = prefs.getBoolean("current_sound_enabled", SOUND_ENABLED_DEFAULT)
 
 if not vibrationPatterns[vibrateMode] then
  vibrateMode = VIBRATE_MODE_DEFAULT
 end
end

function save_user_settings()
 edit.putLong("alarm_duration", alarmDuration)
 edit.putInt("snooze_duration", snoozeDuration)
 edit.putInt("snooze_repeat_count", snoozeRepeatCount)
 edit.putBoolean("snooze_enabled", snoozeEnabled)
 edit.putString("vibrate_mode", vibrateMode)
 edit.putBoolean("vibrate_enabled", vibrateEnabled)
 edit.putString("current_sound", current_sound)
 edit.putBoolean("current_sound_enabled", current_sound_enabled)
 edit.commit()
end

local firstRun = prefs.getBoolean("first_run", true)
if firstRun then
 edit.putString("saved_alarms", "")
 edit.putLong("alarm_duration", ALARM_DURATION_DEFAULT)
 edit.putInt("snooze_duration", SNOOZE_DURATION_DEFAULT)
 edit.putInt("snooze_repeat_count", SNOOZE_REPEAT_COUNT_DEFAULT)
 edit.putBoolean("snooze_enabled", true)
 edit.putString("vibrate_mode", VIBRATE_MODE_DEFAULT)
 edit.putBoolean("vibrate_enabled", VIBRATE_ENABLED_DEFAULT)
 edit.putString("current_sound", CURRENT_SOUND_DEFAULT)
 edit.putBoolean("current_sound_enabled", SOUND_ENABLED_DEFAULT)
 edit.putBoolean("first_run", false)
 edit.commit()
 load_user_settings()
end

load_user_settings()

function load_notification_settings()
 notificationEnabled = prefs.getBoolean("notification_enabled", false)
 notificationMinutes = tonumber(prefs.getString("notification_minutes", "5")) or 5
end

function save_notification_settings()
 edit.putBoolean("notification_enabled", notificationEnabled)
 edit.putString("notification_minutes", tostring(notificationMinutes))
 edit.commit()
end

load_notification_settings()

function string_split(inputstr, sep)
 if sep == nil then
  sep = "%s"
 end
 local t = {}
 for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
  table.insert(t, str)
 end
 return t
end

function days_to_string(days_table)
 local selected_days = {}
 for i, day in ipairs(days_of_week) do
  if days_table[i] then
   table.insert(selected_days, days_of_week_short[i])
  end
 end
 if #selected_days == 0 then
  return "Once"
 elseif #selected_days == 7 then
  return "Every Day"
 else
  return table.concat(selected_days, ",")
 end
end

function string_to_days(days_string)
 local days_table = {false, false, false, false, false, false, false}
 if days_string == "Every Day" then
  for i = 1, 7 do
   days_table[i] = true
  end
 elseif days_string ~= "Once" then
  local days_list = string_split(days_string, ",")
  for _, day_short in ipairs(days_list) do
   for i, short_name in ipairs(days_of_week_short) do
    if day_short == short_name then
     days_table[i] = true
     break
    end
   end
  end
 end
 return days_table
end

function save_alarms_to_storage()
 local alarms_json = ""
 for i, alarm in ipairs(alarm_data) do
  if i > 1 then
   alarms_json = alarms_json .. "|"
  end
  
  local days = alarm.days or {false, false, false, false, false, false, false}
  local days_str = days_to_string(days)
  
  alarms_json = alarms_json .. string.format("%d,%d,%d,%s,%s,%s,%s,%s,%s,%s,%d,%d,%s,%s,%s", 
   alarm.id, alarm.hour, alarm.minute, alarm.ampm, 
   alarm.message or "Alarm time", 
   tostring(alarm.repeat_alarm or false), 
   tostring(alarm.active or false),
   alarm.sound_file or CURRENT_SOUND_DEFAULT,
   alarm.repeat_type or "Once", 
   tostring(alarm.snooze_enabled or false),
   alarm.snooze_count or 0, 
   alarm.max_snooze_count or snoozeRepeatCount,
   alarm.vibrate_mode or VIBRATE_MODE_DEFAULT,
   tostring(alarm.sound_enabled or SOUND_ENABLED_DEFAULT),
   days_str)
 end
 edit.putString("saved_alarms", alarms_json)
 edit.commit()
end

function load_alarms_from_storage()
 local saved_alarms = prefs.getString("saved_alarms", "")
 if saved_alarms ~= "" then
  alarm_data = {}
  local alarm_parts = string_split(saved_alarms, "|")
  for _, alarm_str in ipairs(alarm_parts) do
   local parts = string_split(alarm_str, ",")
   if #parts >= 7 then
    
    local days_str = parts[15]
    if days_str == nil then
     days_str = parts[9] == "Every Day" and "Every Day" or "Once"
    end
    
    local alarm = {
     id = tonumber(parts[1]) or 0,
     hour = tonumber(parts[2]) or 0,
     minute = tonumber(parts[3]) or 0,
     ampm = parts[4] or "AM",
     message = parts[5] or "Alarm time",
     repeat_alarm = parts[6] == "true",
     active = parts[7] == "true",
     sound_file = parts[8] or CURRENT_SOUND_DEFAULT,
     repeat_type = parts[9] or "Once",
     snooze_enabled = parts[10] == "true",
     snooze_count = tonumber(parts[11]) or 0,
     max_snooze_count = tonumber(parts[12]) or snoozeRepeatCount,
     vibrate_mode = parts[13] or VIBRATE_MODE_DEFAULT,
     sound_enabled = parts[14] == "true",
     days = string_to_days(days_str)
    }
    
    local hour_24 = alarm.hour
    local display_hour = hour_24
    
    if hour_24 >= 12 then
     if hour_24 > 12 then
      display_hour = hour_24 - 12
     end
    else
     if hour_24 == 0 then
      display_hour = 12
     end
    end
    alarm.original_hour = display_hour
    
    table.insert(alarm_data, alarm)
    current_alarm_id = math.max(current_alarm_id, alarm.id)
   end
  end
 end
end

function stop_alarm_sound()
 if currentMediaPlayer ~= nil then
  pcall(function()
   if currentMediaPlayer.isPlaying() then
    currentMediaPlayer.stop()
   end
   currentMediaPlayer.release()
   currentMediaPlayer = nil
  end)
 end
end

function start_vibration()
 if vibrator and vibrateEnabled then
  pcall(function()
   vibrationPattern = vibrationPatterns[vibrateMode] or vibrationPatterns.Medium
   vibrator.vibrate(vibrationPattern, 0)
  end)
 end
end

function stop_vibration()
 if vibrator then
  pcall(function()
   vibrator.cancel()
  end)
 end
end

function play_alarm_sound(sound_file)
 stop_alarm_sound()
 stop_vibration()
 
 local sound_enabled_for_alarm = true
 
 if current_sound_enabled == false then
  sound_enabled_for_alarm = false
 end
 
 if sound_enabled_for_alarm then
  pcall(function()
   currentMediaPlayer = MediaPlayer()
   currentMediaPlayer.setAudioStreamType(AudioManager.STREAM_ALARM)
   currentMediaPlayer.setVolume(1.0, 1.0)
   
   if sound_file == "default" or sound_file == "Default Alarm Sound" or sound_file == nil then
    local default_ringtone = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
    currentMediaPlayer.setDataSource(service, default_ringtone)
   else
    local sound_path = DESTINATION_FOLDER .. "/" .. sound_file
    local sound_file_obj = File(sound_path)
    
    if sound_file_obj.exists() then
     currentMediaPlayer.setDataSource(sound_path)
    else
     local default_ringtone = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
     currentMediaPlayer.setDataSource(service, default_ringtone)
    end
   end
   
   currentMediaPlayer.prepare()
   currentMediaPlayer.start()
   currentMediaPlayer.setLooping(true)
  end)
 end
 
 if vibrateEnabled then
  start_vibration()
 end
 
 service.postExecute(alarmDuration, "stop_alarm", nil, function()
  stop_alarm_sound()
  stop_vibration()
 end)
end

function test_alarm()
 if current_sound_enabled == false and vibrateEnabled == false then
  service.speak("Test Alarm skipped. Both sound and vibration are disabled in settings.")
  return
 end
 
 local test_sound = current_sound or CURRENT_SOUND_DEFAULT
 
 service.speak("Testing alarm in 3 seconds with sound: " .. (current_sound_enabled and test_sound or "Off") .. " and vibration: " .. (vibrateEnabled and vibrateMode or "Off"))
 
 service.postExecute(3000, "speak", nil, function()
  local test_alarm_data = {
   id = current_alarm_id + 1,
   hour = 0,
   minute = 0,
   message = "Test Alarm",
   repeat_alarm = false,
   active = true,
   sound_file = test_sound,
   sound_enabled = current_sound_enabled,
   snooze_enabled = false,
   snooze_count = 0,
   max_snooze_count = snoozeRepeatCount,
   vibrate_mode = vibrateMode,
   days = {false, false, false, false, false, false, false}
  }
  
  show_alarm_alert_dialog(test_alarm_data)
 end)
end

function get_next_alarm_time_with_days(alarm)
 local now = os.time()
 local current_date = os.date("*t", now)
 
 local alarm_hour_24 = alarm.hour or 0
 local alarm_minute = alarm.minute or 0
 local alarm_second = alarm.second or 0
 
 local days = alarm.days or {false, false, false, false, false, false, false}
 
 local function is_day_selected(check_wday)
  local day_index = check_wday
  if day_index == 1 then day_index = 7 else day_index = day_index - 1 end
  return days[day_index]
 end
 
 local today_wday = current_date.wday
 
 local today_alarm_time = os.time({
  year = current_date.year,
  month = current_date.month,
  day = current_date.day,
  hour = alarm_hour_24,
  min = alarm_minute,
  sec = alarm_second
 })
 
 if today_alarm_time > now and is_day_selected(today_wday) then
  return today_alarm_time - now, today_alarm_time
 end
 
 for offset = 1, 7 do
  local check_time = now + (offset * 86400)
  local check_date = os.date("*t", check_time)
  local check_wday = check_date.wday
  
  if is_day_selected(check_wday) then
   local candidate_time = os.time({
    year = check_date.year,
    month = check_date.month,
    day = check_date.day,
    hour = alarm_hour_24,
    min = alarm_minute,
    sec = alarm_second
   })
   return candidate_time - now, candidate_time
  end
 end
 
 local is_any_day_selected = false
 for i = 1, 7 do
  if days[i] then
   is_any_day_selected = true
   break
  end
 end
 
 if not is_any_day_selected then
  if today_alarm_time > now then
   return today_alarm_time - now, today_alarm_time
  else
   local tomorrow = now + 86400
   local tomorrow_date = os.date("*t", tomorrow)
   local tomorrow_alarm_time = os.time({
    year = tomorrow_date.year,
    month = tomorrow_date.month,
    day = tomorrow_date.day,
    hour = alarm_hour_24,
    min = alarm_minute,
    sec = alarm_second
   })
   return tomorrow_alarm_time - now, tomorrow_alarm_time
  end
 end
 
 return math.huge, nil
end

function getVibrationButtonText()
 if vibrateEnabled == true then 
  return "Vibration: " .. (vibrateMode or VIBRATE_MODE_DEFAULT)
 else
  return "Vibration: Off"
 end
end

function get_next_alarm_info()
 if #alarm_data == 0 then return "No alarms set" end
 
 local active_alarms = {}
 local now = os.time()
 
 for _, alarm in ipairs(alarm_data) do
  if alarm.active then
   local diff, timestamp = get_next_alarm_time_with_days(alarm)
   if timestamp and diff > 0 then
    table.insert(active_alarms, {data = alarm, diff = diff, time = timestamp})
   end
  end
 end
 
 if #active_alarms == 0 then return "No active alarms found" end
 
 table.sort(active_alarms, function(a, b) return a.diff < b.diff end)
 
 local nearest = active_alarms[1]
 local alarm = nearest.data
 
 local display_hour = alarm.original_hour or alarm.hour
 local ampm = alarm.ampm or "AM"
 local time_str = string.format("%d:%02d %s", display_hour, alarm.minute, ampm)
 
 local total_sec = nearest.diff
 local days = math.floor(total_sec / 86400)
 local hours = math.floor((total_sec % 86400) / 3600)
 local mins = math.floor((total_sec % 3600) / 60)
 
 local remain_str = ""
 if days > 0 then remain_str = remain_str .. days .. " days " end
 if hours > 0 then remain_str = remain_str .. hours .. " hours " end
 remain_str = remain_str .. mins .. " minutes remaining"
 
 local target_date = os.date("*t", nearest.time)
 local day_name = days_of_week[target_date.wday]
 
 return string.format("Next Alarm: %s (%s)\nTime: %s", time_str, day_name, remain_str)
end

function showSoundSelectionDialog(callback)
 local initial_sound_enabled = current_sound_enabled
 local initial_sound = current_sound
 
 local soundDlg = LuaDialog(service)
 soundDlg.setTitle("Select Ringtone")
 
 local layout = LinearLayout(service)
 layout.setOrientation(1)
 layout.setPadding(40, 30, 40, 30)
 layout.setFocusable(true)
 layout.setFocusableInTouchMode(true)
 
 local switchLayout = LinearLayout(service)
 switchLayout.setOrientation(0)
 switchLayout.setGravity(17)
 switchLayout.setPadding(0, 0, 0, 20)
 
 local soundSwitchLayout = LinearLayout(service)
 soundSwitchLayout.setOrientation(1)
 soundSwitchLayout.setLayoutParams(LinearLayout.LayoutParams(
  0,
  LinearLayout.LayoutParams.WRAP_CONTENT,
  1
 ))
 
 local soundSwitchLabel = TextView(service)
 soundSwitchLabel.setText("Sound:")
 soundSwitchLabel.setTextSize(16)
 soundSwitchLabel.setGravity(17)
 soundSwitchLayout.addView(soundSwitchLabel)
 
 local soundSwitch = Switch(service)
 soundSwitch.setChecked(initial_sound_enabled)
 soundSwitch.setGravity(17)
 soundSwitchLayout.addView(soundSwitch)
 
 switchLayout.addView(soundSwitchLayout)
 layout.addView(switchLayout)
 
 local soundSpinner = Spinner(service)
 local available_sounds = get_available_sounds()
 local soundAdapter = ArrayAdapter(service, android.R.layout.simple_spinner_item, available_sounds)
 soundAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
 soundSpinner.setAdapter(soundAdapter)
 
 for i, sound in ipairs(available_sounds) do
  if sound == initial_sound then
   soundSpinner.setSelection(i-1)
   break
  end
 end
 
 soundSpinner.setEnabled(initial_sound_enabled)
 layout.addView(soundSpinner)
 
 local customRingtoneButton = Button(service)
 customRingtoneButton.setText("Add Custom Ringtone")
 customRingtoneButton.setTextSize(16)
 customRingtoneButton.setPadding(0, 20, 0, 10)
 customRingtoneButton.setFocusable(true)
 layout.addView(customRingtoneButton)
 
 local buttonLayout = LinearLayout(service)
 buttonLayout.setOrientation(0)
 buttonLayout.setGravity(17)
 buttonLayout.setPadding(0, 10, 0, 0)
 
 local saveButton = Button(service)
 saveButton.setText("Save")
 saveButton.setLayoutParams(LinearLayout.LayoutParams(
  0,
  LinearLayout.LayoutParams.WRAP_CONTENT,
  1
 ))
 saveButton.setPadding(0, 0, 10, 0)
 
 local cancelButton = Button(service)
 cancelButton.setText("Cancel")
 cancelButton.setLayoutParams(LinearLayout.LayoutParams(
  0,
  LinearLayout.LayoutParams.WRAP_CONTENT,
  1
 ))
 cancelButton.setPadding(10, 0, 0, 0)
 
 buttonLayout.addView(saveButton)
 buttonLayout.addView(cancelButton)
 layout.addView(buttonLayout)
 
 local selected_sound = initial_sound
 local is_sound_enabled = initial_sound_enabled
 
 soundSwitch.setOnCheckedChangeListener({
  onCheckedChanged = function(button, isChecked)
   is_sound_enabled = isChecked
   soundSpinner.setEnabled(isChecked)
   if isChecked then
    service.speak("Sound on")
   else
    service.speak("Sound off")
   end
  end
 })
 
 soundSpinner.setOnItemSelectedListener({
  onItemSelected = function(parent, view, position, id)
   selected_sound = available_sounds[position + 1]
   if is_sound_enabled == true then
    service.speak("Alarm sound " .. selected_sound)
   end
  end
 })
 
 customRingtoneButton.onClick = function()
  soundDlg.dismiss()
  showCustomRingtoneDialog(function()
   local new_sounds = get_available_sounds()
   local newAdapter = ArrayAdapter(service, android.R.layout.simple_spinner_item, new_sounds)
   newAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
   soundSpinner.setAdapter(newAdapter)
   
   for i, sound in ipairs(new_sounds) do
    if sound == selected_sound then
     soundSpinner.setSelection(i-1)
     break
    end
   end
   
   showSoundSelectionDialog(callback)
  end)
 end
 
 saveButton.onClick = function()
  current_sound_enabled = is_sound_enabled
  current_sound = selected_sound
  
  if current_sound_enabled == true then
   service.speak("Ringtone selected: " .. current_sound)
  else
   service.speak("Sound off")
  end
  
  save_user_settings()
  
  soundDlg.dismiss()
  if callback then 
   callback()
  end
 end
 
 cancelButton.onClick = function()
  soundDlg.dismiss()
 end
 
 soundDlg.setView(layout)
 soundDlg.show()
 soundSwitch.requestFocus()
end

function showVibrationSettingsDialog(callback)
 local vibrateDlg = LuaDialog(service)
 vibrateDlg.setTitle("Vibration Settings")
 
 local layout = LinearLayout(service)
 layout.setOrientation(1)
 layout.setPadding(40, 30, 40, 30)
 layout.setFocusable(true)
 layout.setFocusableInTouchMode(true)
 
 local switchLayout = LinearLayout(service)
 switchLayout.setOrientation(0)
 switchLayout.setGravity(17)
 switchLayout.setPadding(0, 0, 0, 20)
 
 local vibrationSwitchLayout = LinearLayout(service)
 vibrationSwitchLayout.setOrientation(1)
 vibrationSwitchLayout.setLayoutParams(LinearLayout.LayoutParams(
  0,
  LinearLayout.LayoutParams.WRAP_CONTENT,
  1
 ))
 
 local vibrationSwitchLabel = TextView(service)
 vibrationSwitchLabel.setText("Vibration:")
 vibrationSwitchLabel.setTextSize(16)
 vibrationSwitchLabel.setGravity(17)
 vibrationSwitchLayout.addView(vibrationSwitchLabel)
 
 local vibrationSwitch = Switch(service)
 vibrationSwitch.setChecked(vibrateEnabled)
 vibrationSwitch.setGravity(17)
 vibrationSwitchLayout.addView(vibrationSwitch)
 
 switchLayout.addView(vibrationSwitchLayout)
 layout.addView(switchLayout)
 
 local strengthLayout = LinearLayout(service)
 strengthLayout.setOrientation(1)
 strengthLayout.setPadding(0, 0, 0, 20)
 
 local strengthLabel = TextView(service)
 strengthLabel.setText("Vibration Strength:")
 strengthLabel.setTextSize(16)
 strengthLabel.setPadding(0, 0, 0, 10)
 strengthLayout.addView(strengthLabel)
 
 local strengthSpinner = Spinner(service)
 local strength_options = {"Low", "Medium", "High"}
 local strengthAdapter = ArrayAdapter(service, android.R.layout.simple_spinner_item, strength_options)
 strengthAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
 strengthSpinner.setAdapter(strengthAdapter)
 
 for i, strength in ipairs(strength_options) do
  if strength == vibrateMode then
   strengthSpinner.setSelection(i-1)
   break
  end
 end
 
 strengthSpinner.setEnabled(vibrateEnabled)
 strengthLayout.addView(strengthSpinner)
 layout.addView(strengthLayout)
 
 local buttonLayout = LinearLayout(service)
 buttonLayout.setOrientation(0)
 buttonLayout.setGravity(17)
 buttonLayout.setPadding(0, 10, 0, 0)
 
 local saveButton = Button(service)
 saveButton.setText("Save")
 saveButton.setLayoutParams(LinearLayout.LayoutParams(
  0,
  LinearLayout.LayoutParams.WRAP_CONTENT,
  1
 ))
 saveButton.setPadding(0, 0, 10, 0)
 
 local cancelButton = Button(service)
 cancelButton.setText("Cancel")
 cancelButton.setLayoutParams(LinearLayout.LayoutParams(
  0,
  LinearLayout.LayoutParams.WRAP_CONTENT,
  1
 ))
 cancelButton.setPadding(10, 0, 0, 0)
 
 buttonLayout.addView(saveButton)
 buttonLayout.addView(cancelButton)
 layout.addView(buttonLayout)
 
 vibrationSwitch.setOnCheckedChangeListener({
  onCheckedChanged = function(button, isChecked)
   strengthSpinner.setEnabled(isChecked)
   if isChecked then
    service.speak("Vibration on")
   else
    service.speak("Vibration off")
   end
  end
 })
 
 saveButton.onClick = function()
  vibrateEnabled = vibrationSwitch.isChecked()
  vibrateMode = strength_options[strengthSpinner.getSelectedItemPosition() + 1]
  
  if vibrateEnabled then
   service.speak("Vibration set to " .. vibrateMode)
  else
   service.speak("Vibration off")
  end
  
  save_user_settings()
  
  vibrateDlg.dismiss()
  if callback then 
   callback()
  end
 end
 
 cancelButton.onClick = function()
  vibrateDlg.dismiss()
 end
 
 vibrateDlg.setView(layout)
 vibrateDlg.show()
 vibrationSwitch.requestFocus()
end

function get_available_sounds()
 local sounds = {"Default Alarm Sound"}
 
 pcall(function()
  local sound_dir = DESTINATION_FOLDER
  local sound_folder = File(sound_dir)
  
  if sound_folder.exists() and sound_folder.isDirectory() then
   local files = sound_folder.listFiles()
   if files then
    for i = 0, #files - 1 do
     local file = files[i]
     if file.isFile() then
      local filename = file.getName()
      if string.match(filename, "%.mp3$") or string.match(filename, "%.wav$") or string.match(filename, "%.ogg$") then
       table.insert(sounds, filename)
      end
     end
    end
   end
  else
   sound_folder.mkdirs()
  end
 end)
 
 return sounds
end

function get_current_time()
 local current_time = os.date("*t")
 if not current_time then
  return {
   hour = 12,
   minute = 0,
   second = 0
  }
 end
 return {
  hour = current_time.hour or 12,
  minute = current_time.min or 0,
  second = current_time.sec or 0
 }
end

function get_current_date_info()
 local calendar = Calendar.getInstance()
 local year = calendar.get(Calendar.YEAR)
 local month = calendar.get(Calendar.MONTH) + 1
 local day = calendar.get(Calendar.DAY_OF_MONTH)
 local day_of_week = calendar.get(Calendar.DAY_OF_WEEK)
 
 local month_names = {"January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December"}
 local day_names = {"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"}
 
 local current_time = get_current_time()
 local display_hour = current_time.hour
 local ampm = "AM"
 
 if display_hour >= 12 then
  ampm = "PM"
  if display_hour > 12 then
   display_hour = display_hour - 12
  end
 else
  if display_hour == 0 then
   display_hour = 12
  end
 end
 
 local minute_str = string.format("%02d", current_time.minute)
 local current_time_str = string.format("%d:%s %s", display_hour, minute_str, ampm)
 
 return {
  year = year,
  month = month,
  month_name = month_names[month],
  day = day,
  day_name = day_names[day_of_week],
  full_date = string.format("%s, %d %s %d", day_names[day_of_week], day, month_names[month], year),
  current_time = current_time_str
 }
end

function get_day_number(day_name)
 for i, day in ipairs(days_of_week) do
  if day == day_name then
   return i
  end
 end
 return 1
end

function get_day_name(day_number)
 return days_of_week[day_number] or "Sunday"
end

function get_snooze_feedback_message(alarm)
 local remaining_snooze = (alarm.max_snooze_count or snoozeRepeatCount) - (alarm.snooze_count or 0)
 
 if alarm.snooze_enabled then
  if remaining_snooze > 1 then
   return "Snooze " .. remaining_snooze .. " times remaining"
  elseif remaining_snooze == 1 then
   return "Snooze last time"
  else
   return "No snooze remaining"
  end
 else
  return "No snooze enabled"
 end
end

function setup_auto_dismiss(alertDlg, alarm)
 service.postExecute(alarmDuration, "auto_dismiss_alarm_"..alarm.id, nil, function()
  if currentAlertDialog ~= nil then
   local remaining_snooze = (alarm.max_snooze_count or snoozeRepeatCount) - (alarm.snooze_count or 0)
   stop_alarm_sound()
   stop_vibration()
   
   if alarm.snooze_enabled and remaining_snooze > 0 then
    service.speak("Auto snooze " .. remaining_snooze .. " times remaining")
    alertDlg.dismiss()
    currentAlertDialog = nil
    auto_snooze_alarm(alarm)
   else
    service.speak("Alarm stop")
    local days = alarm.days or {false, false, false, false, false, false, false}
    local has_selected_days = false
    for i = 1, 7 do
     if days[i] then
      has_selected_days = true
      break
     end
    end
    
    if not has_selected_days then
     alarm.active = false
    end
    save_alarms_to_storage()
    alertDlg.dismiss()
    currentAlertDialog = nil
    update_main_dialog_alarm_info()
   end
  end
 end)
 
 alertDlg.setOnDismissListener({
  onDismiss = function()
  end
 })
end

function auto_snooze_alarm(alarm)
 if not alarm.snooze_enabled then
  return
 end
 
 local now = os.date("*t")
 local new_minute = now.min + snoozeDuration
 local new_hour = now.hour
 local ampm = "AM"
 
 if new_minute >= 60 then
  new_minute = new_minute - 60
  new_hour = new_hour + 1
  if new_hour >= 24 then
   new_hour = new_hour - 24
  end
 end
 
 local display_hour = new_hour
 if new_hour >= 12 then
  ampm = "PM"
  if new_hour > 12 then
   display_hour = new_hour - 12
  end
 else
  if new_hour == 0 then
   display_hour = 12
  end
 end
 
 local snooze_alarm = {
  id = current_alarm_id + 1,
  hour = new_hour,
  minute = new_minute,
  ampm = ampm,
  original_hour = display_hour,
  message = "Snooze: " .. alarm.message,
  repeat_alarm = false,
  active = true,
  sound_file = alarm.sound_file,
  sound_enabled = alarm.sound_enabled,
  snooze_enabled = alarm.snooze_enabled,
  snooze_count = (alarm.snooze_count or 0) + 1,
  max_snooze_count = alarm.max_snooze_count or snoozeRepeatCount,
  vibrate_mode = alarm.vibrate_mode or vibrateMode,
  days = {false, false, false, false, false, false, false}
 }
 
 current_alarm_id = current_alarm_id + 1
 table.insert(alarm_data, snooze_alarm)
 save_alarms_to_storage()
 schedule_single_alarm(snooze_alarm)
 update_main_dialog_alarm_info()
end

function update_main_dialog_alarm_info()
 if mainDialog then
  service.postExecute(100, "update_alarm_info", nil, function()
   local nextAlarmText = mainDialog.findViewById(android.R.id.content).getRootView().findViewWithTag("nextAlarmText")
   if nextAlarmText then
    nextAlarmText.setText(get_next_alarm_info())
   end
  end)
 end
end

function show_alarm_alert_dialog(alarm)
 if currentAlertDialog ~= nil then
  pcall(function()
   currentAlertDialog.dismiss()
   currentAlertDialog = nil
  end)
 end
 
 local alertDlg = LuaDialog(service)
 alertDlg.setTitle("Alarm Alert!")
 alertDlg.setCancelable(false)
 currentAlertDialog = alertDlg
 
 alertDlg.getWindow().setType(WindowManager.LayoutParams.TYPE_SYSTEM_ALERT)
 alertDlg.getWindow().addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED |
  WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON |
  WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON |
  WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD)
 
 local layout = LinearLayout(service)
 layout.setOrientation(1)
 layout.setPadding(40, 30, 40, 30)
 layout.setFocusable(true)
 layout.setFocusableInTouchMode(true)
 
 local titleText = TextView(service)
 titleText.setText("Alarm Time!")
 titleText.setTextSize(20)
 titleText.setGravity(17)
 titleText.setTextColor(0xFFD32F2F)
 titleText.setPadding(0, 0, 0, 20)
 layout.addView(titleText)
 
 local messageText = TextView(service)
 messageText.setText(alarm.message)
 messageText.setTextSize(18)
 messageText.setGravity(17)
 messageText.setPadding(0, 0, 0, 30)
 layout.addView(messageText)
 
 local timeText = TextView(service)
 
 local display_hour = alarm.original_hour or alarm.hour
 local ampm_display = alarm.ampm or "AM"
 
 local display_minute = string.format("%02d", alarm.minute)
 timeText.setText(string.format("Time: %d:%s %s", display_hour, display_minute, ampm_display))
 timeText.setTextSize(16)
 timeText.setGravity(17)
 timeText.setPadding(0, 0, 0, 20)
 layout.addView(timeText)
 
 local days_text = ""
 local days = alarm.days or {false, false, false, false, false, false, false}
 local selected_days = {}
 for i = 1, 7 do
  if days[i] then
   table.insert(selected_days, days_of_week[i])
  end
 end
 
 if #selected_days > 0 then
  if #selected_days == 7 then
   days_text = "Repeat: Every Day"
  else
   days_text = "Days: " .. table.concat(selected_days, ", ")
  end
 else
  days_text = "Repeat: Once"
 end
 
 local daysText = TextView(service)
 daysText.setText(days_text)
 daysText.setTextSize(14)
 daysText.setGravity(17)
 daysText.setTextColor(0xFF666666)
 daysText.setPadding(0, 0, 0, 15)
 layout.addView(daysText)
 
 local snoozeStatusText = TextView(service)
 local remaining_snooze = (alarm.max_snooze_count or snoozeRepeatCount) - (alarm.snooze_count or 0)
 
 if alarm.snooze_enabled then
  if remaining_snooze > 1 then
   snoozeStatusText.setText("Snooze: " .. remaining_snooze .. " times remaining (" .. snoozeDuration .. " minutes each)")
  elseif remaining_snooze == 1 then
   snoozeStatusText.setText("Snooze: Last time remaining (" .. snoozeDuration .. " minutes)")
  else
   snoozeStatusText.setText("Snooze: No snooze remaining")
  end
 else
  snoozeStatusText.setText("Snooze: No snooze enabled")
 end
 
 snoozeStatusText.setTextSize(14)
 snoozeStatusText.setGravity(17)
 snoozeStatusText.setTextColor(0xFF666666)
 snoozeStatusText.setPadding(0, 0, 0, 20)
 layout.addView(snoozeStatusText)
 
 local buttonLayout = LinearLayout(service)
 buttonLayout.setOrientation(0)
 buttonLayout.setGravity(17)
 
 local stopButton = Button(service)
 stopButton.setText("Stop Alarm")
 stopButton.setLayoutParams(LinearLayout.LayoutParams(
  0,
  LinearLayout.LayoutParams.WRAP_CONTENT,
  1
 ))
 stopButton.setPadding(0, 0, 10, 0)
 
 local snoozeButton = nil
 
 local showSnoozeButton = alarm.snooze_enabled and remaining_snooze > 0
 
 if showSnoozeButton then
  snoozeButton = Button(service)
  
  if remaining_snooze > 1 then
   snoozeButton.setText("Snooze (" .. snoozeDuration .. " minutes × " .. remaining_snooze .. " times)")
  else
   snoozeButton.setText("Snooze (" .. snoozeDuration .. " minutes × " .. remaining_snooze .. " remaining)")
  end
  
  snoozeButton.setLayoutParams(LinearLayout.LayoutParams(
   0,
   LinearLayout.LayoutParams.WRAP_CONTENT,
   1
  ))
  snoozeButton.setPadding(10, 0, 0, 0)
  snoozeButton.setEnabled(true)
  buttonLayout.addView(snoozeButton)
 end
 
 buttonLayout.addView(stopButton)
 layout.addView(buttonLayout)
 
 local current_vibrate_mode = alarm.vibrate_mode or vibrateMode
 local current_vibration_pattern = vibrationPatterns[current_vibrate_mode] or vibrationPatterns.Medium
 
 if alarm.sound_enabled ~= false then
  play_alarm_sound(alarm.sound_file)
 elseif vibrateEnabled then
  start_vibration()
 end
 
 setup_auto_dismiss(alertDlg, alarm)
 
 alertDlg.setOnDismissListener({
  onDismiss = function()
   stop_alarm_sound()
   stop_vibration()
   currentAlertDialog = nil
  end
 })
 
 local feedback_message = get_snooze_feedback_message(alarm)
 
 local sound_name = "Default Alarm Sound"
 if alarm.sound_file and alarm.sound_file ~= "Default Alarm Sound" then
  sound_name = alarm.sound_file
 end
 
 local announcement_count = math.min((alarm.snooze_count or 0) + 1, 3)
 for i = 1, announcement_count do
  service.postExecute((i-1) * 2000, "announce_alarm_"..i, nil, function()
   if alarm.sound_enabled ~= false then
    service.speak("Alarm! " .. alarm.message .. " with " .. sound_name .. ". " .. feedback_message)
   else
    service.speak("Alarm! " .. alarm.message .. ". " .. feedback_message)
   end
  end)
 end
 
 stopButton.onClick = function()
  local days = alarm.days or {false, false, false, false, false, false, false}
  local has_selected_days = false
  for i = 1, 7 do
   if days[i] then
    has_selected_days = true
    break
   end
  end
  
  if not has_selected_days then
   alarm.active = false
  end
  save_alarms_to_storage()
  stop_alarm_sound()
  stop_vibration()
  alertDlg.dismiss()
  currentAlertDialog = nil
  service.speak("Alarm stop")
  update_main_dialog_alarm_info()
 end
 
 if showSnoozeButton and snoozeButton then
  snoozeButton.onClick = function()
   stop_alarm_sound()
   stop_vibration()
   alertDlg.dismiss()
   currentAlertDialog = nil
   
   local feedback_message = get_snooze_feedback_message(alarm)
   service.speak("Snooze activated. " .. feedback_message)
   auto_snooze_alarm(alarm)
  end
 end
 
 alertDlg.setView(layout)
 alertDlg.show()
 
 if showSnoozeButton and snoozeButton then
  snoozeButton.requestFocus()
 else
  stopButton.requestFocus()
 end
end

function schedule_single_alarm(alarm)
 local now = os.time()
 
 local time_diff, alarm_time = get_next_alarm_time_with_days(alarm)
 
 if time_diff and time_diff > 0 then
  local delay_ms = time_diff * 1000
  
  service.postExecute(delay_ms, "alarm_trigger_"..alarm.id, nil, function()
   if alarm.active then
    show_alarm_alert_dialog(alarm)
    
    local days = alarm.days or {false, false, false, false, false, false, false}
    local has_selected_days = false
    for i = 1, 7 do
     if days[i] then
      has_selected_days = true
      break
     end
    end
    
    if has_selected_days then
     schedule_single_alarm(alarm)
    else
     alarm.active = false
     save_alarms_to_storage()
    end
    
    update_main_dialog_alarm_info()
   end
  end)
 elseif time_diff == 0 then
  show_alarm_alert_dialog(alarm)
  
  local days = alarm.days or {false, false, false, false, false, false, false}
  local has_selected_days = false
  for i = 1, 7 do
   if days[i] then
    has_selected_days = true
    break
   end
  end
  
  if not has_selected_days then
   alarm.active = false
   save_alarms_to_storage()
  end
 end
end

function schedule_all_alarms()
 for _, alarm in ipairs(alarm_data) do
  if alarm.active then
   schedule_single_alarm(alarm)
  end
 end
end

function schedule_notification_for_alarm(alarm)
 if not notificationEnabled then
  return
 end
 
 local now = os.time()
 local current_time = os.date("*t", now)
 
 local alarm_hour_24 = alarm.hour
 
 local alarm_time_today = os.time{
  year = current_time.year,
  month = current_time.month,
  day = current_time.day,
  hour = alarm_hour_24,
  min = alarm.minute,
  sec = 0
 }
 
 local notification_time = alarm_time_today - (notificationMinutes * 60)
 local time_diff = notification_time - now
 
 if time_diff > 0 then
  service.postExecute(time_diff * 1000, "notification_"..alarm.id, nil, function()
   if alarm.active then
    show_notification_dialog(alarm)
   end
  end)
 end
end

function create_new_alarm(hour, minute, second, ampm, message, repeat_type, sound_file, sound_enabled, snooze_enabled, days)
 current_alarm_id = current_alarm_id + 1
 
 local hour_24 = tonumber(hour)
 
 if ampm == "PM" then
  if hour_24 ~= 12 then
   hour_24 = hour_24 + 12
  end
 else
  if hour_24 == 12 then
   hour_24 = 0
  end
 end
 
 local repeat_alarm = (repeat_type ~= "Once")
 
 if not days then
  days = {false, false, false, false, false, false, false}
  if repeat_type == "Every Day" then
   for i = 1, 7 do
    days[i] = true
   end
  end
 end
 
 local new_alarm = {
  id = current_alarm_id,
  hour = hour_24,
  minute = tonumber(minute),
  second = tonumber(second) or 0,
  ampm = ampm,
  original_hour = tonumber(hour),
  message = message or "Alarm time",
  repeat_alarm = repeat_alarm,
  repeat_type = repeat_type or "Once",
  active = true,
  sound_file = sound_file or current_sound,
  sound_enabled = sound_enabled ~= false,
  snooze_enabled = snooze_enabled,
  snooze_count = 0,
  max_snooze_count = snoozeRepeatCount,
  vibrate_mode = vibrateMode,
  days = days
 }
 
 table.insert(alarm_data, new_alarm)
 save_alarms_to_storage()
 schedule_single_alarm(new_alarm)
 
 if notificationEnabled then
  schedule_notification_for_alarm(new_alarm)
 end
 
 update_main_dialog_alarm_info()
 
 return new_alarm.id
end

function update_alarm(alarm_id, hour, minute, second, ampm, message, repeat_type, sound_file, sound_enabled, snooze_enabled, days)
 for i, alarm in ipairs(alarm_data) do
  if alarm.id == alarm_id then
   alarm.active = false
   save_alarms_to_storage()
   break
  end
 end
 
 for i, alarm in ipairs(alarm_data) do
  if alarm.id == alarm_id then
   local hour_24 = tonumber(hour)
   
   if ampm == "PM" then
    if hour_24 ~= 12 then
     hour_24 = hour_24 + 12
    end
   else
    if hour_24 == 12 then
     hour_24 = 0
    end
   end
   
   local repeat_alarm = (repeat_type ~= "Once")
   
   if not days then
    days = {false, false, false, false, false, false, false}
    if repeat_type == "Every Day" then
     for i = 1, 7 do
      days[i] = true
     end
    end
   end
   
   alarm.hour = hour_24
   alarm.minute = tonumber(minute)
   alarm.second = tonumber(second) or 0
   alarm.ampm = ampm
   alarm.original_hour = tonumber(hour)
   alarm.message = message or "Alarm time"
   alarm.repeat_alarm = repeat_alarm
   alarm.repeat_type = repeat_type or "Once"
   alarm.sound_file = sound_file or current_sound
   alarm.sound_enabled = sound_enabled ~= false
   alarm.snooze_enabled = snooze_enabled
   alarm.max_snooze_count = snoozeRepeatCount
   alarm.vibrate_mode = vibrateMode
   alarm.days = days
   alarm.active = true
   
   save_alarms_to_storage()
   schedule_single_alarm(alarm)
   
   if notificationEnabled then
    schedule_notification_for_alarm(alarm)
   end
   
   local display_hour = tonumber(hour)
   service.speak("Alarm updated for " .. display_hour .. " " .. minute .. " " .. ampm .. " with sound: " .. sound_file)
   
   update_main_dialog_alarm_info()
   return true
  end
 end
 return false
end

function stop_all_alarms()
 for _, alarm in ipairs(alarm_data) do
  alarm.active = false
 end
 save_alarms_to_storage()
 stop_alarm_sound()
 stop_vibration()
 if currentAlertDialog ~= nil then
  pcall(function()
   currentAlertDialog.dismiss()
   currentAlertDialog = nil
  end)
 end
 service.speak("All alarms stopped")
 
 update_main_dialog_alarm_info()
end

function delete_alarm(alarm_id)
 for i, alarm in ipairs(alarm_data) do
  if alarm.id == alarm_id then
   table.remove(alarm_data, i)
   save_alarms_to_storage()
   update_main_dialog_alarm_info()
   return true
  end
 end
 return false
end

function delete_all_alarms()
 alarm_data = {}
 current_alarm_id = 0
 save_alarms_to_storage()
 stop_alarm_sound()
 stop_vibration()
 if currentAlertDialog ~= nil then
  pcall(function()
   currentAlertDialog.dismiss()
   currentAlertDialog = nil
  end)
 end
 service.speak("All alarms deleted")
 
 update_main_dialog_alarm_info()
end

function showAlarmDurationDialog()
 local durationDlg = LuaDialog(service)
 durationDlg.setTitle("Alarm Sound Duration")
 
 local layout = LinearLayout(service)
 layout.setOrientation(1)
 layout.setPadding(40, 30, 40, 30)
 layout.setFocusable(true)
 layout.setFocusableInTouchMode(true)
 
 local titleText = TextView(service)
 titleText.setText("Select Alarm Sound Duration")
 titleText.setTextSize(18)
 titleText.setGravity(17)
 titleText.setPadding(0, 0, 0, 20)
 layout.addView(titleText)
 
 local durationOptions = {
  {10, "10 seconds"},
  {20, "20 seconds"}, 
  {30, "30 seconds"},
  {40, "40 seconds"},
  {50, "50 seconds"},
  {60, "1 minute"},
  {120, "2 minutes"},
  {180, "3 minutes"},
  {240, "4 minutes"},
  {300, "5 minutes"}
 }
 
 for _, duration in ipairs(durationOptions) do
  local durationButton = Button(service)
  durationButton.setText(duration[2])
  durationButton.setTextSize(16)
  durationButton.setPadding(0, 10, 0, 10)
  durationButton.setFocusable(true)
  durationButton.setFocusableInTouchMode(true)
  
  durationButton.onClick = function()
   alarmDuration = duration[1] * 1000
   service.speak("Alarm duration set to " .. duration[2])
   
   save_user_settings()
   
   durationDlg.dismiss()
   if mainDialog then
    mainDialog.findViewById(android.R.id.content).requestFocus()
    local alarmDurationButton = mainDialog.findViewById(android.R.id.content).getRootView().findViewWithTag("alarmDurationButton")
    if alarmDurationButton then
     alarmDurationButton.setText("Alarm Sound Duration: " .. (alarmDuration / 1000) .. " seconds")
    end
   end
  end
  
  layout.addView(durationButton)
 end
 
 local cancelButton = Button(service)
 cancelButton.setText("Cancel")
 cancelButton.setTextSize(16)
 cancelButton.setPadding(0, 20, 0, 0)
 cancelButton.setFocusable(true)
 cancelButton.setFocusableInTouchMode(true)
 
 cancelButton.onClick = function()
  durationDlg.dismiss()
  if mainDialog then
   mainDialog.findViewById(android.R.id.content).requestFocus()
  end
 end
 
 layout.addView(cancelButton)
 durationDlg.setView(layout)
 durationDlg.show()
 layout.getChildAt(0).requestFocus()
end

function getSnoozeButtonText()
 if snoozeEnabled then
  return "Snooze Settings: " .. snoozeDuration .. " minutes, " .. snoozeRepeatCount .. " times"
 else
  return "Snooze Settings: Snooze Off"
 end
end

function get_all_folders()
 local folders = {}
 local base_path = "/storage/emulated/0"
 local base_folder = File(base_path)
 
 if base_folder.exists() and base_folder.isDirectory() then
  local files = base_folder.listFiles()
  if files then
   for i = 0, #files - 1 do
    local file = files[i]
    if file.isDirectory() then
     table.insert(folders, {
      name = file.getName(),
      path = file.getAbsolutePath()
     })
    end
   end
  end
 end
 
 table.sort(folders, function(a, b)
  return a.name < b.name
 end)
 
 return folders
end

function get_audio_files_from_folder(folder_path)
 local audio_list = {}
 local folder = File(folder_path)
 
 if folder.exists() and folder.isDirectory() then
  local files = folder.listFiles()
  if files then
   for i = 0, #files - 1 do
    local file = files[i]
    if not file.isDirectory() then
     local file_name = file.getName():lower()
     if file_name:match("%.mp3$") or file_name:match("%.wav$") or 
      file_name:match("%.ogg$") or file_name:match("%.m4a$") or
      file_name:match("%.aac$") or file_name:match("%.flac$") then
      table.insert(audio_list, {
       name = file.getName(),
       path = file.getAbsolutePath()
      })
     end
    end
   end
  end
 end
 
 table.sort(audio_list, function(a, b)
  return a.name < b.name
 end)
 
 return audio_list
end

function copy_file_to_sounds_folder(filePath, fileName)
 if not filePath or type(filePath) ~= "string" or filePath == "" then
  service.speak("Invalid file path")
  return false
 end
 
 local destFolder = File(DESTINATION_FOLDER)
 if not destFolder.exists() then
  if not destFolder.mkdirs() then
   service.speak("Failed to create Sounds folder")
   return false
  end
 end
 
 local sourceFile = File(filePath)
 if not sourceFile.exists() then
  service.speak("Source file not found: " .. fileName)
  return false
 end
 
 local destFile = File(DESTINATION_FOLDER, fileName)
 if destFile.exists() then
  service.speak("File already exists: " .. fileName)
  return false
 end
 
 local success = false
 local fis, fos = nil, nil
 local buffer = byte[1024]
 local bytesRead = 0
 
 pcall(function()
  fis = FileInputStream(sourceFile)
  fos = FileOutputStream(destFile)
  
  while true do
   bytesRead = fis.read(buffer)
   if bytesRead == -1 then break end
   fos.write(buffer, 0, bytesRead)
  end
  
  success = true
 end)
 
 if fis ~= nil then
  pcall(function() fis.close() end)
 end
 if fos ~= nil then
  pcall(function() fos.close() end)
 end
 
 if success then
  service.speak("File copied: " .. fileName)
  
  pcall(function()
   local mediaScanIntent = Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE)
   mediaScanIntent.setData(Uri.fromFile(destFile))
   service.sendBroadcast(mediaScanIntent)
  end)
  
  return true
 else
  service.speak("Failed to copy: " .. fileName)
  return false
 end
end

function showCustomRingtoneDialog(callback)
 local customDlg = LuaDialog(service)
 customDlg.setTitle("Add Custom Ringtone")
 
 local layout = LinearLayout(service)
 layout.setOrientation(1)
 layout.setPadding(30, 20, 30, 20)
 layout.setFocusable(true)
 layout.setFocusableInTouchMode(true)
 
 local titleText = TextView(service)
 titleText.setText("Select Audio Folder")
 titleText.setTextSize(18)
 titleText.setGravity(17)
 titleText.setPadding(0, 0, 0, 20)
 layout.addView(titleText)
 
 local folderSpinner = Spinner(service)
 local folders = get_all_folders()
 local folder_names = {}
 for _, folder in ipairs(folders) do
  table.insert(folder_names, folder.name)
 end
 
 local folderAdapter = ArrayAdapter(service, android.R.layout.simple_spinner_item, folder_names)
 folderAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
 folderSpinner.setAdapter(folderAdapter)
 
 layout.addView(folderSpinner)
 
 local fileListView = ListView(service)
 local fileAdapter = ArrayAdapter(service, android.R.layout.simple_list_item_multiple_choice, {})
 fileListView.setAdapter(fileAdapter)
 fileListView.setChoiceMode(ListView.CHOICE_MODE_MULTIPLE)
 fileListView.setLayoutParams(LinearLayout.LayoutParams(
  LinearLayout.LayoutParams.MATCH_PARENT,
  300
 ))
 
 layout.addView(fileListView)
 
 local buttonLayout = LinearLayout(service)
 buttonLayout.setOrientation(0)
 buttonLayout.setGravity(17)
 buttonLayout.setPadding(0, 20, 0, 0)
 
 local selectButton = Button(service)
 selectButton.setText("Copy Selected")
 selectButton.setLayoutParams(LinearLayout.LayoutParams(
  0,
  LinearLayout.LayoutParams.WRAP_CONTENT,
  1
 ))
 selectButton.setPadding(0, 0, 10, 0)
 
 local cancelButton = Button(service)
 cancelButton.setText("Cancel")
 cancelButton.setLayoutParams(LinearLayout.LayoutParams(
  0,
  LinearLayout.LayoutParams.WRAP_CONTENT,
  1
 ))
 cancelButton.setPadding(10, 0, 0, 0)
 
 buttonLayout.addView(selectButton)
 buttonLayout.addView(cancelButton)
 layout.addView(buttonLayout)
 
 local current_files = {}
 
 folderSpinner.setOnItemSelectedListener({
  onItemSelected = function(parent, view, position, id)
   local folder_name = folder_names[position + 1]
   local folder_path = folders[position + 1].path
   current_files = get_audio_files_from_folder(folder_path)
   
   local file_names = {}
   for _, file in ipairs(current_files) do
    table.insert(file_names, file.name)
   end
   
   local newAdapter = ArrayAdapter(service, android.R.layout.simple_list_item_multiple_choice, file_names)
   fileListView.setAdapter(newAdapter)
   
   for i = 0, #file_names - 1 do
    fileListView.setItemChecked(i, false)
   end
   
   service.speak("Loaded " .. #file_names .. " audio files from " .. folder_name)
  end
 })
 
 if #folders > 0 then
  folderSpinner.setSelection(0)
 end
 
 selectButton.onClick = function()
  local selected_count = 0
  local success_count = 0
  
  for i = 0, fileListView.getCount() - 1 do
   if fileListView.isItemChecked(i) then
    selected_count = selected_count + 1
    local file_data = current_files[i + 1]
    
    if file_data and copy_file_to_sounds_folder(file_data.path, file_data.name) then
     success_count = success_count + 1
    end
   end
  end
  
  if selected_count == 0 then
   service.speak("No files selected")
   return
  end
  
  if success_count > 0 then
   service.speak(success_count .. " files copied successfully")
   customDlg.dismiss()
   if callback then
    callback()
   end
  else
   service.speak("No files were copied")
  end
 end
 
 cancelButton.onClick = function()
  customDlg.dismiss()
 end
 
 customDlg.setView(layout)
 customDlg.show()
 folderSpinner.requestFocus()
end

current_hour = "1"
current_minute = "00"
current_second = "00"
current_ampm = "AM"
current_repeat_type = "Once"
current_day = "Sunday"
current_am_pm = "AM"

function showDayAndTimeSettingsDialog(originalName, callback)
 local dateTimeDlg = LuaDialog(service)
 dateTimeDlg.setTitle("Day and Time Settings")
 
 local layout = ScrollView(service)
 local mainLayout = LinearLayout(service)
 mainLayout.setOrientation(1)
 mainLayout.setPadding(40, 30, 40, 30)
 mainLayout.setFocusable(true)
 mainLayout.setFocusableInTouchMode(true)
 
 local dateInfo = get_current_date_info()
 
 local currentDateTimeText = TextView(service)
 currentDateTimeText.setText("Current: " .. dateInfo.full_date .. ", " .. dateInfo.current_time)
 currentDateTimeText.setTextSize(16)
 currentDateTimeText.setGravity(17)
 currentDateTimeText.setTextColor(0xFF1976D2)
 currentDateTimeText.setPadding(0, 0, 0, 20)
 mainLayout.addView(currentDateTimeText)
 
 local repeatLayout = LinearLayout(service)
 repeatLayout.setOrientation(1)
 repeatLayout.setPadding(0, 0, 0, 20)
 
 local repeatLabel = TextView(service)
 repeatLabel.setText("Repeat Type:")
 repeatLabel.setTextSize(16)
 repeatLabel.setPadding(0, 0, 0, 8)
 repeatLayout.addView(repeatLabel)
 
 local repeatSpinner = Spinner(service)
 local repeat_options = {"Once", "Every Day"}
 local repeatAdapter = ArrayAdapter(service, android.R.layout.simple_spinner_item, repeat_options)
 repeatAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
 repeatSpinner.setAdapter(repeatAdapter)
 
 for i, option in ipairs(repeat_options) do
  if option == current_repeat_type then
   repeatSpinner.setSelection(i-1)
   break
  end
 end
 
 repeatLayout.addView(repeatSpinner)
 mainLayout.addView(repeatLayout)
 
 local dayContainer = LinearLayout(service)
 dayContainer.setOrientation(1)
 dayContainer.setPadding(0, 0, 0, 20)
 
 local dayLabel = TextView(service)
 dayLabel.setText("Select Day:")
 dayLabel.setTextSize(16)
 dayLabel.setPadding(0, 0, 0, 10)
 dayContainer.addView(dayLabel)
 
 local daySpinner = Spinner(service)
 local day_options = {"Select Day", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"}
 local dayAdapter = ArrayAdapter(service, android.R.layout.simple_spinner_item, day_options)
 dayAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
 daySpinner.setAdapter(dayAdapter)
 
 daySpinner.setSelection(0)
 
 dayContainer.addView(daySpinner)
 mainLayout.addView(dayContainer)
 
 local timeSectionLabel = TextView(service)
 timeSectionLabel.setText("Set Alarm Time:")
 timeSectionLabel.setTextSize(16)
 timeSectionLabel.setPadding(0, 10, 0, 15)
 mainLayout.addView(timeSectionLabel)
 
 local timeLayout = LinearLayout(service)
 timeLayout.setOrientation(0)
 timeLayout.setGravity(17)
 
 local hourLayout = LinearLayout(service)
 hourLayout.setOrientation(1)
 hourLayout.setLayoutParams(LinearLayout.LayoutParams(
  0,
  LinearLayout.LayoutParams.WRAP_CONTENT,
  1
 ))
 
 local hourLabel = TextView(service)
 hourLabel.setText("Hour")
 hourLabel.setTextSize(14)
 hourLabel.setGravity(17)
 hourLayout.addView(hourLabel)
 
 local hourSpinner = Spinner(service)
 local hours = {"1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12"}
 local hourAdapter = ArrayAdapter(service, android.R.layout.simple_spinner_item, hours)
 hourAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
 hourSpinner.setAdapter(hourAdapter)
 
 for i, hour in ipairs(hours) do
  if hour == current_hour then
   hourSpinner.setSelection(i-1)
   break
  end
 end
 
 hourSpinner.setContentDescription("Hour spinner, " .. #hours .. " options available")
 hourLayout.addView(hourSpinner)
 timeLayout.addView(hourLayout)
 
 local minuteLayout = LinearLayout(service)
 minuteLayout.setOrientation(1)
 minuteLayout.setLayoutParams(LinearLayout.LayoutParams(
  0,
  LinearLayout.LayoutParams.WRAP_CONTENT,
  1
 ))
 
 local minuteLabel = TextView(service)
 minuteLabel.setText("Minute")
 minuteLabel.setTextSize(14)
 minuteLabel.setGravity(17)
 minuteLayout.addView(minuteLabel)
 
 local minuteSpinner = Spinner(service)
 local minutes = {}
 for i = 0, 59 do
  table.insert(minutes, string.format("%02d", i))
 end
 local minuteAdapter = ArrayAdapter(service, android.R.layout.simple_spinner_item, minutes)
 minuteAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
 minuteSpinner.setAdapter(minuteAdapter)
 
 for i, minute in ipairs(minutes) do
  if minute == current_minute then
   minuteSpinner.setSelection(i-1)
   break
  end
 end
 
 minuteSpinner.setContentDescription("Minute spinner, " .. #minutes .. " options available")
 minuteLayout.addView(minuteSpinner)
 timeLayout.addView(minuteLayout)
 
 local secondLayout = LinearLayout(service)
 secondLayout.setOrientation(1)
 secondLayout.setLayoutParams(LinearLayout.LayoutParams(
  0,
  LinearLayout.LayoutParams.WRAP_CONTENT,
  1
 ))
 
 local secondLabel = TextView(service)
 secondLabel.setText("Second")
 secondLabel.setTextSize(14)
 secondLabel.setGravity(17)
 secondLayout.addView(secondLabel)
 
 local secondSpinner = Spinner(service)
 local seconds = {}
 for i = 0, 59 do
  table.insert(seconds, string.format("%02d", i))
 end
 local secondAdapter = ArrayAdapter(service, android.R.layout.simple_spinner_item, seconds)
 secondAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
 secondSpinner.setAdapter(secondAdapter)
 
 for i, second in ipairs(seconds) do
  if second == current_second then
   secondSpinner.setSelection(i-1)
   break
  end
 end
 
 secondSpinner.setContentDescription("Second spinner, " .. #seconds .. " options available")
 secondLayout.addView(secondSpinner)
 timeLayout.addView(secondLayout)
 
 local ampmContainer = LinearLayout(service)
 ampmContainer.setOrientation(1)
 ampmContainer.setLayoutParams(LinearLayout.LayoutParams(
  0,
  LinearLayout.LayoutParams.WRAP_CONTENT,
  1
 ))
 
 local ampmContainerInner = LinearLayout(service)
 ampmContainerInner.setOrientation(0)
 ampmContainerInner.setGravity(17)
 ampmContainerInner.setLayoutParams(LinearLayout.LayoutParams(
  LinearLayout.LayoutParams.MATCH_PARENT,
  LinearLayout.LayoutParams.WRAP_CONTENT
 ))
 
 local amCheckbox = CheckBox(service)
 amCheckbox.setText("AM")
 amCheckbox.setTextSize(12)
 amCheckbox.setPadding(5, 0, 5, 0)
 amCheckbox.setLayoutParams(LinearLayout.LayoutParams(
  0,
  LinearLayout.LayoutParams.WRAP_CONTENT,
  1
 ))
 
 local pmCheckbox = CheckBox(service)
 pmCheckbox.setText("PM")
 pmCheckbox.setTextSize(12)
 pmCheckbox.setPadding(5, 0, 5, 0)
 pmCheckbox.setLayoutParams(LinearLayout.LayoutParams(
  0,
  LinearLayout.LayoutParams.WRAP_CONTENT,
  1
 ))
 
 local function updateAmPmCheckboxes()
  if current_am_pm == "AM" then
   amCheckbox.setChecked(true)
   pmCheckbox.setChecked(false)
  elseif current_am_pm == "PM" then
   amCheckbox.setChecked(false)
   pmCheckbox.setChecked(true)
  else
   amCheckbox.setChecked(true)
   pmCheckbox.setChecked(false)
   current_am_pm = "AM"
  end
 end
 
 updateAmPmCheckboxes()
 
 amCheckbox.setOnCheckedChangeListener({
  onCheckedChanged = function(button, isChecked)
   if isChecked then
    pmCheckbox.setChecked(false)
    current_am_pm = "AM"
    service.speak("AM checked")
   else
    if not pmCheckbox.isChecked() then
     amCheckbox.setChecked(true)
    else
     service.speak("AM unchecked")
    end
   end
   amCheckbox.requestFocus()
  end
 })
 
 pmCheckbox.setOnCheckedChangeListener({
  onCheckedChanged = function(button, isChecked)
   if isChecked then
    amCheckbox.setChecked(false)
    current_am_pm = "PM"
    service.speak("PM checked")
   else
    if not amCheckbox.isChecked() then
     pmCheckbox.setChecked(true)
    else
     service.speak("PM unchecked")
    end
   end
   pmCheckbox.requestFocus()
  end
 })
 
 ampmContainerInner.addView(amCheckbox)
 ampmContainerInner.addView(pmCheckbox)
 ampmContainer.addView(ampmContainerInner)
 timeLayout.addView(ampmContainer)
 
 mainLayout.addView(timeLayout)
 
 local buttonLayout = LinearLayout(service)
 buttonLayout.setOrientation(0)
 buttonLayout.setGravity(17)
 buttonLayout.setPadding(0, 20, 0, 0)
 
 local cancelButton = Button(service)
 cancelButton.setText("Cancel")
 cancelButton.setLayoutParams(LinearLayout.LayoutParams(
  0,
  LinearLayout.LayoutParams.WRAP_CONTENT,
  1
 ))
 cancelButton.setOnClickListener({
  onClick = function()
   dateTimeDlg.dismiss()
  end
 })
 
 local saveButton = Button(service)
 saveButton.setText("SAVE")
 saveButton.setLayoutParams(LinearLayout.LayoutParams(
  0,
  LinearLayout.LayoutParams.WRAP_CONTENT,
  1
 ))
 saveButton.setOnClickListener({
  onClick = function()
   current_repeat_type = repeat_options[repeatSpinner.getSelectedItemPosition() + 1]
   
   local selectedDayIndex = daySpinner.getSelectedItemPosition() + 1
   if selectedDayIndex == 1 then
    current_day = nil
   else
    current_day = day_options[selectedDayIndex]
   end
   
   current_hour = hours[hourSpinner.getSelectedItemPosition() + 1]
   current_minute = minutes[minuteSpinner.getSelectedItemPosition() + 1]
   current_second = seconds[secondSpinner.getSelectedItemPosition() + 1]
   
   if amCheckbox.isChecked() then
    current_am_pm = "AM"
   elseif pmCheckbox.isChecked() then
    current_am_pm = "PM"
   else
    current_am_pm = "AM"
   end
   
   dateTimeDlg.dismiss()
   if callback then
    callback(originalName)
   end
  end
 })
 
 buttonLayout.addView(cancelButton)
 buttonLayout.addView(saveButton)
 mainLayout.addView(buttonLayout)
 
 layout.addView(mainLayout)
 dateTimeDlg.setView(layout)
 dateTimeDlg.show()
end

function showNewAlarmDialog()
 if current_sound_enabled == nil then
  current_sound_enabled = true
 end
 
 local alarmDlg = LuaDialog(service)
 alarmDlg.setTitle("Set New Alarm")
 
 local layout = ScrollView(service)
 local mainLayout = LinearLayout(service)
 mainLayout.setOrientation(1)
 mainLayout.setPadding(30, 20, 30, 20)
 mainLayout.setFocusable(true)
 mainLayout.setFocusableInTouchMode(true)
 
 local nameHeading = TextView(service)
 nameHeading.setText("Alarm Name")
 nameHeading.setTextSize(18)
 nameHeading.setGravity(17)
 nameHeading.setTextColor(0xFF2E7D32)
 nameHeading.setPadding(0, 0, 0, 10)
 mainLayout.addView(nameHeading)
 
 local nameEdit = EditText(service)
 nameEdit.setText("My Alarm")
 nameEdit.setTextSize(16)
 nameEdit.setHint("Enter alarm name")
 nameEdit.setPadding(0, 0, 0, 20)
 mainLayout.addView(nameEdit)
 
 local dateTimeButton = Button(service)
 dateTimeButton.setText("Day and Time Settings")
 dateTimeButton.setTextSize(16)
 dateTimeButton.setPadding(0, 0, 0, 10)
 dateTimeButton.setFocusable(true)
 mainLayout.addView(dateTimeButton)
 
 local ringtoneButton = Button(service)
 local ringtoneButtonText = ""
 if current_sound_enabled == true then
  ringtoneButtonText = "Select Ringtone: " .. (current_sound or "Default Alarm Sound")
 else
  ringtoneButtonText = "Select Ringtone: Sound Off"
 end
 ringtoneButton.setText(ringtoneButtonText)
 ringtoneButton.setTextSize(16)
 ringtoneButton.setPadding(0, 0, 0, 10)
 ringtoneButton.setFocusable(true)
 ringtoneButton.setEnabled(true)
 mainLayout.addView(ringtoneButton)
 
 local vibrationButton = Button(service)
 vibrationButton.setText(getVibrationButtonText())
 vibrationButton.setTextSize(16)
 vibrationButton.setPadding(0, 0, 0, 10)
 vibrationButton.setFocusable(true)
 mainLayout.addView(vibrationButton)
 
 local snoozeButton = Button(service)
 snoozeButton.setText(getSnoozeButtonText())
 snoozeButton.setTextSize(16)
 snoozeButton.setPadding(0, 0, 0, 20)
 snoozeButton.setFocusable(true)
 mainLayout.addView(snoozeButton)
 
 local previewLayout = LinearLayout(service)
 previewLayout.setOrientation(1)
 previewLayout.setPadding(0, 10, 0, 20)
 previewLayout.setBackgroundColor(0xFFF5F5F5)
 previewLayout.setPadding(15, 15, 15, 15)
 
 local previewLabel = TextView(service)
 previewLabel.setText("Alarm Preview:")
 previewLabel.setTextSize(16)
 previewLabel.setTextColor(0xFF2E7D32)
 previewLabel.setPadding(0, 0, 0, 10)
 previewLayout.addView(previewLabel)
 
 local previewText = TextView(service)
 
 local function updatePreview()
  local display_hour = current_hour or "1"
  local display_minute = current_minute or "00"
  local ampm_display = current_ampm or "AM"
  local repeat_status = current_repeat_type or "Once"
  
  local sound_status = ""
  if current_sound_enabled == true then
   sound_status = current_sound or "Default Alarm Sound"
  else
   sound_status = "Sound Off"
  end
  
  local snooze_status = snoozeEnabled and (snoozeDuration .. " minutes, " .. snoozeRepeatCount .. " times") or "Snooze Off"
  local vibration_status = vibrateEnabled and vibrateMode or "Off"
  
  local days_info = ""
  if current_repeat_type == "Every Day" then
   days_info = "Days: Every Day"
  else
   if current_day then
    days_info = "Day: " .. current_day
   else
    days_info = "Day: Not Selected"
   end
  end
  
  local preview_content = string.format("Time: %s:%s %s\n%s\nSound: %s\nVibration: %s\nSnooze: %s",
   display_hour, display_minute, ampm_display, days_info, sound_status, vibration_status, snooze_status)
  
  previewText.setText(preview_content)
  
  if current_sound_enabled == true then
   ringtoneButton.setText("Select Ringtone: " .. (current_sound or "Default Alarm Sound"))
  else
   ringtoneButton.setText("Select Ringtone: Sound Off")
  end
  
  vibrationButton.setText(getVibrationButtonText())
  snoozeButton.setText(getSnoozeButtonText())
 end
 
 updatePreview()
 previewLayout.addView(previewText)
 mainLayout.addView(previewLayout)
 
 local buttonLayout = LinearLayout(service)
 buttonLayout.setOrientation(1)
 buttonLayout.setGravity(17)
 buttonLayout.setPadding(0, 10, 0, 0)
 
 local activateButton = Button(service)
 activateButton.setText("Activate Alarm")
 activateButton.setTextSize(16)
 activateButton.setPadding(0, 15, 0, 15)
 activateButton.setFocusable(true)
 
 local cancelButton = Button(service)
 cancelButton.setText("Cancel")
 cancelButton.setTextSize(16)
 cancelButton.setPadding(0, 15, 0, 15)
 cancelButton.setFocusable(true)
 
 buttonLayout.addView(activateButton)
 buttonLayout.addView(cancelButton)
 mainLayout.addView(buttonLayout)
 
 local current_alarm_name = "My Alarm"
 
 dateTimeButton.onClick = function()
  current_alarm_name = nameEdit.getText().toString()
  if current_alarm_name == "" then
   current_alarm_name = "My Alarm"
  end
  
  showDayAndTimeSettingsDialog(current_alarm_name, function(returnedName)
   if returnedName then
    nameEdit.setText(returnedName)
   end
   updatePreview()
  end)
 end
 
 ringtoneButton.onClick = function()
  showSoundSelectionDialog(function()
   updatePreview()
  end)
 end
 
 vibrationButton.onClick = function()
  showVibrationSettingsDialog(function()
   updatePreview()
  end)
 end
 
 snoozeButton.onClick = function()
  showSnoozeSettingsDialog(function()
   updatePreview()
  end)
 end
 
 nameEdit.addTextChangedListener({
  onTextChanged = function(text, start, before, count)
   updatePreview()
  end
 })
 
 activateButton.onClick = function()
  local message = nameEdit.getText().toString()
  if message == "" then
   message = "My Alarm"
  end
  
  local days = {false, false, false, false, false, false, false}
  if current_repeat_type == "Every Day" then
   for i = 1, 7 do
    days[i] = true
   end
  elseif current_day then
   local day_index = get_day_number(current_day)
   if day_index >= 1 and day_index <= 7 then
    days[day_index] = true
   end
  end
  
  create_new_alarm(current_hour or "1", current_minute or "00", current_second or "00", 
   current_ampm or "AM", message, current_repeat_type or "Once", 
   current_sound or "Default Alarm Sound", current_sound_enabled == true,
   snoozeEnabled, days)
  
  local display_hour = current_hour or "1"
  local display_minute = current_minute or "00"
  local ampm_display = current_ampm or "AM"
  
  local days_info = ""
  if current_repeat_type == "Every Day" then
   days_info = "Every Day"
  else
   if current_day then
    days_info = current_day
   else
    days_info = "Not Selected"
   end
  end
  
  if current_sound_enabled == true then
   service.speak("Alarm set for " .. display_hour .. " " .. display_minute .. " " .. ampm_display .. " on " .. days_info .. " with sound: " .. (current_sound or "Default Alarm Sound"))
  else
   service.speak("Alarm set for " .. display_hour .. " " .. display_minute .. " " .. ampm_display .. " on " .. days_info .. " with sound off")
  end
  
  alarmDlg.dismiss()
  
  update_main_dialog_alarm_info()
 end
 
 cancelButton.onClick = function()
  alarmDlg.dismiss()
 end
 
 layout.addView(mainLayout)
 alarmDlg.setView(layout)
 alarmDlg.show()
 nameEdit.requestFocus()
end

function sort_alarms_by_time()
 local now = os.time()
 
 local active_alarms = {}
 local inactive_alarms = {}
 
 for _, alarm in ipairs(alarm_data) do
  if alarm.active then
   local diff, _ = get_next_alarm_time_with_days(alarm)
   if diff and diff > 0 then
    table.insert(active_alarms, {alarm = alarm, diff = diff})
   else
    table.insert(inactive_alarms, alarm)
   end
  else
   table.insert(inactive_alarms, alarm)
  end
 end
 
 table.sort(active_alarms, function(a, b) return a.diff < b.diff end)
 
 local sorted_alarms = {}
 for _, item in ipairs(active_alarms) do
  table.insert(sorted_alarms, item.alarm)
 end
 
 for _, alarm in ipairs(inactive_alarms) do
  table.insert(sorted_alarms, alarm)
 end
 
 return sorted_alarms
end

function showAlarmsListDialog()
 local listDlg = LuaDialog(service)
 listDlg.setTitle("Current Alarms")
 
 local layout = ScrollView(service)
 local mainLayout = LinearLayout(service)
 mainLayout.setOrientation(1)
 mainLayout.setPadding(30, 20, 30, 20)
 mainLayout.setFocusable(true)
 mainLayout.setFocusableInTouchMode(true)
 
 if #alarm_data == 0 then
  local noAlarmsText = TextView(service)
  noAlarmsText.setText("No alarms set")
  noAlarmsText.setTextSize(18)
  noAlarmsText.setGravity(17)
  noAlarmsText.setPadding(0, 0, 0, 20)
  mainLayout.addView(noAlarmsText)
 else
  local sorted_alarms = sort_alarms_by_time()
  
  for index, alarm in ipairs(sorted_alarms) do
  
   local alarmLayout = LinearLayout(service)
   alarmLayout.setOrientation(1)
   alarmLayout.setPadding(15, 15, 15, 15)
   alarmLayout.setBackgroundColor(0xFFF5F5F5)
   
   local display_hour = alarm.original_hour or alarm.hour
   local display_minute = string.format("%02d", alarm.minute)
   local ampm_display = alarm.ampm or "AM"
   
   local selected_days = {}
   local days = alarm.days or {false, false, false, false, false, false, false}
   for i = 1, 7 do
    if days[i] then 
     table.insert(selected_days, days_of_week[i])
    end
   end
   
   local days_str = ""
   if #selected_days == 7 then
    days_str = "Every Day"
   elseif #selected_days == 1 then
    days_str = "Day: " .. selected_days[1]
   else
    days_str = "Once"
   end
   
   local status_str = alarm.active and "Active" or "Inactive"
   local vib_str = "Vibration: " .. (alarm.vibrate_mode or "Medium")
   
   local soundName = alarm.sound_file or "Default Alarm Sound"
   local snd_str = alarm.sound_enabled and ("Sound: " .. soundName) or "Sound: Off"
   
   local snooze_str = alarm.snooze_enabled and ("Snooze: " .. snoozeDuration .. " minutes, " .. snoozeRepeatCount .. " times") or "Snooze: Disabled"
   
   local alarm_msg = (alarm.message and alarm.message ~= "") and alarm.message or "My Alarm"
   
   local diff_str = ""
   if alarm.active then
    local diff, _ = get_next_alarm_time_with_days(alarm)
    if diff and diff > 0 then
     local hours = math.floor(diff / 3600)
     local mins = math.floor((diff % 3600) / 60)
     diff_str = string.format(" (%d:%02d remaining)", hours, mins)
    end
   end
   
   local infoLine = TextView(service)
   local full_detail = string.format("%d. Time: %d:%s %s%s\nName: %s\nStatus: %s\n%s\n%s\n%s", 
    index, display_hour, display_minute, ampm_display, diff_str, alarm_msg, status_str, days_str, vib_str, snd_str, snooze_str)
   
   infoLine.setText(full_detail)
   infoLine.setTextSize(15)
   infoLine.setPadding(0, 0, 0, 10)
   alarmLayout.addView(infoLine)
   
   local buttonLayout = LinearLayout(service)
   buttonLayout.setOrientation(0)
   
   local editButton = Button(service)
   editButton.setText("Edit")
   editButton.setLayoutParams(LinearLayout.LayoutParams(0, -2, 1))
   
   local toggleButton = Button(service)
   toggleButton.setText(alarm.active and "Stop" or "Activate")
   toggleButton.setLayoutParams(LinearLayout.LayoutParams(0, -2, 1))
   
   local deleteButton = Button(service)
   deleteButton.setText("Delete")
   deleteButton.setLayoutParams(LinearLayout.LayoutParams(0, -2, 1))
   
   buttonLayout.addView(editButton)
   buttonLayout.addView(toggleButton)
   buttonLayout.addView(deleteButton)
   alarmLayout.addView(buttonLayout)
   
   editButton.onClick = function()
    listDlg.dismiss()
    showEditAlarmDialog(alarm)
   end
   
   toggleButton.onClick = function()
    alarm.active = not alarm.active
    save_alarms_to_storage()
    if alarm.active then
     schedule_single_alarm(alarm)
     service.speak("Alarm activated")
    else
     service.speak("Alarm stopped")
    end
    update_main_dialog_alarm_info()
    listDlg.dismiss()
    showAlarmsListDialog()
   end
   
   deleteButton.onClick = function()
    delete_alarm(alarm.id)
    service.speak("Alarm deleted")
    listDlg.dismiss()
    showAlarmsListDialog()
   end
   
   mainLayout.addView(alarmLayout)
   local space = View(service)
   space.setLayoutParams(LinearLayout.LayoutParams(-1, 20))
   mainLayout.addView(space)
  end
 end
 
 local bottomNavLayout = LinearLayout(service)
 bottomNavLayout.setOrientation(0)
 bottomNavLayout.setPadding(0, 20, 0, 0)
 
 local deleteAllButton = Button(service)
 deleteAllButton.setText("Delete All")
 deleteAllButton.setLayoutParams(LinearLayout.LayoutParams(0, -2, 1))
 
 deleteAllButton.onClick = function()
  local confirmDlg = LuaDialog(service)
  confirmDlg.setTitle("Confirm Delete")
  confirmDlg.setMessage("Are you sure you want to delete all alarms permanently?")
  
  confirmDlg.setPositiveButton("Yes", function()
   delete_all_alarms()
   confirmDlg.dismiss()
   listDlg.dismiss()
   showAlarmsListDialog()
  end)
  
  confirmDlg.setNegativeButton("No", function()
   confirmDlg.dismiss()
  end)
  
  confirmDlg.show()
 end
 
 local closeButton = Button(service)
 closeButton.setText("Close")
 closeButton.setLayoutParams(LinearLayout.LayoutParams(0, -2, 1))
 closeButton.onClick = function()
  listDlg.dismiss()
 end
 
 bottomNavLayout.addView(deleteAllButton)
 bottomNavLayout.addView(closeButton)
 mainLayout.addView(bottomNavLayout)
 
 layout.addView(mainLayout)
 listDlg.setView(layout)
 listDlg.show()
 
 closeButton.requestFocus()
end

function showSnoozeSettingsDialog(callback)
 local snoozeDlg = LuaDialog(service)
 snoozeDlg.setTitle("Snooze Settings")
 
 local layout = LinearLayout(service)
 layout.setOrientation(1)
 layout.setPadding(40, 30, 40, 30)
 layout.setFocusable(true)
 layout.setFocusableInTouchMode(true)
 
 local switchLayout = LinearLayout(service)
 switchLayout.setOrientation(0)
 switchLayout.setGravity(17)
 switchLayout.setPadding(0, 0, 0, 20)
 
 local snoozeSwitchLayout = LinearLayout(service)
 snoozeSwitchLayout.setOrientation(1)
 snoozeSwitchLayout.setLayoutParams(LinearLayout.LayoutParams(
  0,
  LinearLayout.LayoutParams.WRAP_CONTENT,
  1
 ))
 
 local snoozeSwitchLabel = TextView(service)
 snoozeSwitchLabel.setText("Snooze:")
 snoozeSwitchLabel.setTextSize(16)
 snoozeSwitchLabel.setGravity(17)
 snoozeSwitchLayout.addView(snoozeSwitchLabel)
 
 local snoozeSwitch = Switch(service)
 snoozeSwitch.setChecked(snoozeEnabled)
 snoozeSwitch.setGravity(17)
 snoozeSwitchLayout.addView(snoozeSwitch)
 
 switchLayout.addView(snoozeSwitchLayout)
 layout.addView(switchLayout)
 
 local durationLayout = LinearLayout(service)
 durationLayout.setOrientation(1)
 durationLayout.setPadding(0, 0, 0, 20)
 
 local durationLabel = TextView(service)
 durationLabel.setText("Snooze Duration (minutes):")
 durationLabel.setTextSize(16)
 durationLabel.setPadding(0, 0, 0, 8)
 durationLayout.addView(durationLabel)
 
 local durationSpinner = Spinner(service)
 local duration_options = {"5", "10", "15", "20", "30"}
 local durationAdapter = ArrayAdapter(service, android.R.layout.simple_spinner_item, duration_options)
 durationAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
 durationSpinner.setAdapter(durationAdapter)
 
 for i, duration in ipairs(duration_options) do
  if tonumber(duration) == snoozeDuration then
   durationSpinner.setSelection(i-1)
   break
  end
 end
 
 durationSpinner.setEnabled(snoozeEnabled)
 durationLayout.addView(durationSpinner)
 layout.addView(durationLayout)
 
 local repeatLayout = LinearLayout(service)
 repeatLayout.setOrientation(1)
 repeatLayout.setPadding(0, 0, 0, 20)
 
 local repeatLabel = TextView(service)
 repeatLabel.setText("Maximum Snooze Count:")
 repeatLabel.setTextSize(16)
 repeatLabel.setPadding(0, 0, 0, 8)
 repeatLayout.addView(repeatLabel)
 
 local repeatSpinner = Spinner(service)
 local repeat_options = {"1", "2", "3", "4", "5", "10"}
 local repeatAdapter = ArrayAdapter(service, android.R.layout.simple_spinner_item, repeat_options)
 repeatAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
 repeatSpinner.setAdapter(repeatAdapter)
 
 for i, repeat_count in ipairs(repeat_options) do
  if tonumber(repeat_count) == snoozeRepeatCount then
   repeatSpinner.setSelection(i-1)
   break
  end
 end
 
 repeatSpinner.setEnabled(snoozeEnabled)
 repeatLayout.addView(repeatSpinner)
 layout.addView(repeatLayout)
 
 local buttonLayout = LinearLayout(service)
 buttonLayout.setOrientation(0)
 buttonLayout.setGravity(17)
 buttonLayout.setPadding(0, 10, 0, 0)
 
 local saveButton = Button(service)
 saveButton.setText("Save")
 saveButton.setLayoutParams(LinearLayout.LayoutParams(
  0,
  LinearLayout.LayoutParams.WRAP_CONTENT,
  1
 ))
 saveButton.setPadding(0, 0, 10, 0)
 
 local cancelButton = Button(service)
 cancelButton.setText("Cancel")
 cancelButton.setLayoutParams(LinearLayout.LayoutParams(
  0,
  LinearLayout.LayoutParams.WRAP_CONTENT,
  1
 ))
 cancelButton.setPadding(10, 0, 0, 0)
 
 buttonLayout.addView(saveButton)
 buttonLayout.addView(cancelButton)
 layout.addView(buttonLayout)
 
 snoozeSwitch.setOnCheckedChangeListener({
  onCheckedChanged = function(button, isChecked)
   durationSpinner.setEnabled(isChecked)
   repeatSpinner.setEnabled(isChecked)
   if isChecked then
    service.speak("Snooze on")
   else
    service.speak("Snooze off")
   end
  end
 })
 
 saveButton.onClick = function()
  snoozeEnabled = snoozeSwitch.isChecked()
  snoozeDuration = tonumber(duration_options[durationSpinner.getSelectedItemPosition() + 1])
  snoozeRepeatCount = tonumber(repeat_options[repeatSpinner.getSelectedItemPosition() + 1])
  
  if snoozeEnabled then
   service.speak("Snooze set to " .. snoozeDuration .. " minutes, " .. snoozeRepeatCount .. " times")
  else
   service.speak("Snooze off")
  end
  
  save_user_settings()
  
  snoozeDlg.dismiss()
  if callback then 
   callback()
  end
 end
 
 cancelButton.onClick = function()
  snoozeDlg.dismiss()
 end
 
 snoozeDlg.setView(layout)
 snoozeDlg.show()
 snoozeSwitch.requestFocus()
end

function showEditAlarmDialog(alarm)
 local editDlg = LuaDialog(service)
 editDlg.setTitle("Edit Alarm")
 
 local layout = ScrollView(service)
 local mainLayout = LinearLayout(service)
 mainLayout.setOrientation(1)
 mainLayout.setPadding(30, 20, 30, 20)
 mainLayout.setFocusable(true)
 mainLayout.setFocusableInTouchMode(true)
 
 local nameHeading = TextView(service)
 nameHeading.setText("Alarm Name")
 nameHeading.setTextSize(18)
 nameHeading.setGravity(17)
 nameHeading.setTextColor(0xFF2E7D32)
 nameHeading.setPadding(0, 0, 0, 10)
 mainLayout.addView(nameHeading)
 
 local nameEdit = EditText(service)
 nameEdit.setText(alarm.message or "My Alarm")
 nameEdit.setTextSize(16)
 nameEdit.setHint("Enter alarm name")
 nameEdit.setPadding(0, 0, 0, 20)
 mainLayout.addView(nameEdit)
 
 local dateTimeButton = Button(service)
 dateTimeButton.setText("Day and Time Settings")
 dateTimeButton.setTextSize(16)
 dateTimeButton.setPadding(0, 0, 0, 10)
 dateTimeButton.setFocusable(true)
 mainLayout.addView(dateTimeButton)
 
 local ringtoneButton = Button(service)
 local ringtoneButtonText = ""
 if alarm.sound_enabled == true then
  ringtoneButtonText = "Select Ringtone: " .. (alarm.sound_file or "Default Alarm Sound")
 else
  ringtoneButtonText = "Select Ringtone: Sound Off"
 end
 ringtoneButton.setText(ringtoneButtonText)
 ringtoneButton.setTextSize(16)
 ringtoneButton.setPadding(0, 0, 0, 10)
 ringtoneButton.setFocusable(true)
 ringtoneButton.setEnabled(true)
 mainLayout.addView(ringtoneButton)
 
 local vibrationButton = Button(service)
 vibrationButton.setText("Vibration: " .. (alarm.vibrate_mode or vibrateMode))
 vibrationButton.setTextSize(16)
 vibrationButton.setPadding(0, 0, 0, 10)
 vibrationButton.setFocusable(true)
 mainLayout.addView(vibrationButton)
 
 local snoozeButton = Button(service)
 local snoozeButtonText = alarm.snooze_enabled and ("Snooze Settings: " .. snoozeDuration .. " minutes, " .. snoozeRepeatCount .. " times") or "Snooze Settings: Snooze Off"
 snoozeButton.setText(snoozeButtonText)
 snoozeButton.setTextSize(16)
 snoozeButton.setPadding(0, 0, 0, 20)
 snoozeButton.setFocusable(true)
 mainLayout.addView(snoozeButton)
 
 local previewLayout = LinearLayout(service)
 previewLayout.setOrientation(1)
 previewLayout.setPadding(0, 10, 0, 20)
 previewLayout.setBackgroundColor(0xFFF5F5F5)
 previewLayout.setPadding(15, 15, 15, 15)
 
 local previewLabel = TextView(service)
 previewLabel.setText("Alarm Preview:")
 previewLabel.setTextSize(16)
 previewLabel.setTextColor(0xFF2E7D32)
 previewLabel.setPadding(0, 0, 0, 10)
 previewLayout.addView(previewLabel)
 
 local previewText = TextView(service)
 
 local function updatePreview()
  local display_hour = alarm.original_hour or alarm.hour
  local display_minute = string.format("%02d", alarm.minute)
  local ampm_display = alarm.ampm or "AM"
  local repeat_status = alarm.repeat_type or "Once"
  
  local sound_status = ""
  if alarm.sound_enabled == true then
   sound_status = alarm.sound_file or "Default Alarm Sound"
  else
   sound_status = "Sound Off"
  end
  
  local snooze_status = alarm.snooze_enabled and (snoozeDuration .. " minutes, " .. snoozeRepeatCount .. " times") or "Snooze Off"
  local vibration_status = alarm.vibrate_mode or vibrateMode
  
  local selected_days = {}
  local days_table = alarm.days or {false, false, false, false, false, false, false}
  for i = 1, 7 do
   if days_table[i] then
    table.insert(selected_days, days_of_week[i])
   end
  end
  
  local days_info = ""
  if #selected_days == 7 then
   days_info = "Days: Every Day"
  elseif #selected_days == 1 then
   days_info = "Day: " .. selected_days[1]
  else
   days_info = "Days: Once"
  end
  
  local preview_content = string.format("Time: %s:%s %s\n%s\nSound: %s\nVibration: %s\nSnooze: %s",
   display_hour, display_minute, ampm_display, days_info, sound_status, vibration_status, snooze_status)
  
  previewText.setText(preview_content)
  
  if alarm.sound_enabled == true then
   ringtoneButton.setText("Select Ringtone: " .. (alarm.sound_file or "Default Alarm Sound"))
  else
   ringtoneButton.setText("Select Ringtone: Sound Off")
  end
  
  vibrationButton.setText("Vibration: " .. (alarm.vibrate_mode or vibrateMode))
  snoozeButton.setText(snoozeButtonText)
 end
 
 updatePreview()
 previewLayout.addView(previewText)
 mainLayout.addView(previewLayout)
 
 local buttonLayout = LinearLayout(service)
 buttonLayout.setOrientation(1)
 buttonLayout.setGravity(17)
 buttonLayout.setPadding(0, 10, 0, 0)
 
 local updateButton = Button(service)
 updateButton.setText("Update Alarm")
 updateButton.setTextSize(16)
 updateButton.setPadding(0, 15, 0, 15)
 updateButton.setFocusable(true)
 
 local cancelButton2 = Button(service)
 cancelButton2.setText("Cancel")
 cancelButton2.setTextSize(16)
 cancelButton2.setPadding(0, 15, 0, 15)
 cancelButton2.setFocusable(true)
 
 buttonLayout.addView(updateButton)
 buttonLayout.addView(cancelButton2)
 mainLayout.addView(buttonLayout)
 
 local temp_sound_enabled = alarm.sound_enabled
 local temp_sound = alarm.sound_file
 local temp_vibrate_mode = alarm.vibrate_mode
 local temp_snooze_enabled = alarm.snooze_enabled
 
 dateTimeButton.onClick = function()
  current_hour = tostring(alarm.original_hour or alarm.hour)
  current_minute = string.format("%02d", alarm.minute)
  current_second = "00"
  current_ampm = alarm.ampm or "AM"
  current_repeat_type = alarm.repeat_type or "Once"
  
  local days = alarm.days or {false, false, false, false, false, false, false}
  for i = 1, 7 do
   if days[i] then
    current_day = days_of_week[i]
    break
   end
  end
  
  if not current_day then
   current_day = nil
  end
  
  showDayAndTimeSettingsDialog(nameEdit.getText().toString(), function(returnedName)
   if returnedName then
    nameEdit.setText(returnedName)
   end
   
   local days = {false, false, false, false, false, false, false}
   if current_repeat_type == "Every Day" then
    for i = 1, 7 do
     days[i] = true
    end
   elseif current_day then
    local day_index = get_day_number(current_day)
    if day_index >= 1 and day_index <= 7 then
     days[day_index] = true
    end
   end
   
   update_alarm(alarm.id, current_hour, current_minute, current_second, current_ampm, 
    nameEdit.getText().toString(), current_repeat_type, temp_sound, 
    temp_sound_enabled, temp_snooze_enabled, days)
   editDlg.dismiss()
  end)
 end
 
 ringtoneButton.onClick = function()
  local original_sound = current_sound
  local original_sound_enabled = current_sound_enabled
  
  current_sound = temp_sound
  current_sound_enabled = temp_sound_enabled
  
  showSoundSelectionDialog(function()
   temp_sound = current_sound
   temp_sound_enabled = current_sound_enabled
   updatePreview()
   
   current_sound = original_sound
   current_sound_enabled = original_sound_enabled
  end)
 end
 
 vibrationButton.onClick = function()
  local original_vibrate_mode = vibrateMode
  local original_vibrate_enabled = vibrateEnabled
  
  vibrateMode = temp_vibrate_mode
  vibrateEnabled = true
  
  showVibrationSettingsDialog(function()
   temp_vibrate_mode = vibrateMode
   updatePreview()
   
   vibrateMode = original_vibrate_mode
   vibrateEnabled = original_vibrate_enabled
  end)
 end
 
 snoozeButton.onClick = function()
  showSnoozeSettingsDialog(function()
   temp_snooze_enabled = snoozeEnabled
   updatePreview()
  end)
 end
 
 nameEdit.addTextChangedListener({
  onTextChanged = function(text, start, before, count)
   updatePreview()
  end
 })
 
 updateButton.onClick = function()
  local message = nameEdit.getText().toString()
  if message == "" then
   message = "My Alarm"
  end
  
  local days = {false, false, false, false, false, false, false}
  if current_repeat_type == "Every Day" then
   for i = 1, 7 do
    days[i] = true
   end
  elseif current_day then
   local day_index = get_day_number(current_day)
   if day_index >= 1 and day_index <= 7 then
    days[day_index] = true
   end
  end
  
  update_alarm(alarm.id, current_hour or "1", current_minute or "00", current_second or "00", 
   current_ampm or "AM", message, current_repeat_type or "Once", 
   temp_sound or "Default Alarm Sound", temp_sound_enabled == true,
   temp_snooze_enabled, days)
  
  editDlg.dismiss()
 end
 
 cancelButton2.onClick = function()
  editDlg.dismiss()
 end
 
 layout.addView(mainLayout)
 editDlg.setView(layout)
 editDlg.show()
 nameEdit.requestFocus()
end

function show_notification_dialog(alarm)
 local notificationDlg = LuaDialog(service)
 notificationDlg.setTitle("Upcoming Alarm Reminder")
 
 local layout = LinearLayout(service)
 layout.setOrientation(1)
 layout.setPadding(40, 30, 40, 30)
 layout.setFocusable(true)
 layout.setFocusableInTouchMode(true)
 
 local titleText = TextView(service)
 titleText.setText("Alarm Reminder!")
 titleText.setTextSize(20)
 titleText.setGravity(17)
 titleText.setTextColor(0xFF1976D2)
 titleText.setPadding(0, 0, 0, 20)
 layout.addView(titleText)
 
 local messageText = TextView(service)
 local display_hour = alarm.original_hour or alarm.hour
 local display_minute = string.format("%02d", alarm.minute)
 local ampm_display = alarm.ampm or "AM"
 
 messageText.setText("Your alarm '" .. alarm.message .. "'\nwill ring at " .. display_hour .. ":" .. display_minute .. " " .. ampm_display .. "\n\n(" .. notificationMinutes .. " minutes remaining)")
 messageText.setTextSize(16)
 messageText.setGravity(17)
 messageText.setPadding(0, 0, 0, 30)
 layout.addView(messageText)
 
 local closeButton = Button(service)
 closeButton.setText("OK")
 closeButton.setTextSize(16)
 closeButton.setPadding(0, 0, 0, 0)
 closeButton.setFocusable(true)
 layout.addView(closeButton)
 
 service.speak("Reminder! Your alarm will ring in " .. notificationMinutes .. " minutes")
 
 closeButton.onClick = function()
  notificationDlg.dismiss()
 end
 
 notificationDlg.setView(layout)
 notificationDlg.show()
 closeButton.requestFocus()
 
 service.postExecute(30000, "close_notification", nil, function()
  if notificationDlg then
   notificationDlg.dismiss()
  end
 end)
end

function show_notification_settings_dialog()
 local settingsDlg = LuaDialog(service)
 settingsDlg.setTitle("Upcoming Notification Settings")
 
 local layout = LinearLayout(service)
 layout.setOrientation(1)
 layout.setPadding(40, 30, 40, 30)
 layout.setFocusable(true)
 layout.setFocusableInTouchMode(true)
 
 local titleText = TextView(service)
 titleText.setText("Upcoming Notification Settings")
 titleText.setTextSize(20)
 titleText.setGravity(17)
 titleText.setTextColor(0xFF2E7D32)
 titleText.setPadding(0, 0, 0, 20)
 layout.addView(titleText)
 
 local notificationSwitchLayout = LinearLayout(service)
 notificationSwitchLayout.setOrientation(0)
 notificationSwitchLayout.setGravity(16)
 notificationSwitchLayout.setPadding(0, 0, 0, 30)
 
 local notificationSwitchLabel = TextView(service)
 notificationSwitchLabel.setText("Notification:")
 notificationSwitchLabel.setTextSize(16)
 notificationSwitchLabel.setLayoutParams(LinearLayout.LayoutParams(
  0,
  LinearLayout.LayoutParams.WRAP_CONTENT,
  1
 ))
 
 local notificationSwitch = Switch(service)
 notificationSwitch.setChecked(notificationEnabled)
 notificationSwitch.setLayoutParams(LinearLayout.LayoutParams(
  0,
  LinearLayout.LayoutParams.WRAP_CONTENT,
  1
 ))
 
 notificationSwitchLayout.addView(notificationSwitchLabel)
 notificationSwitchLayout.addView(notificationSwitch)
 layout.addView(notificationSwitchLayout)
 
 local timeLabel = TextView(service)
 timeLabel.setText("Notify before alarm:")
 timeLabel.setTextSize(16)
 timeLabel.setPadding(0, 0, 0, 15)
 layout.addView(timeLabel)
 
 local radioGroup = RadioGroup(service)
 radioGroup.setOrientation(1)
 radioGroup.setPadding(0, 0, 0, 30)
 
 local timeOptions = {
  {5, "5 minutes"},
  {10, "10 minutes"},
  {15, "15 minutes"},
  {20, "20 minutes"},
  {25, "25 minutes"},
  {30, "30 minutes"}
 }
 
 local radioButtons = {}
 for i, option in ipairs(timeOptions) do
  local radioButton = RadioButton(service)
  radioButton.setText(option[2])
  radioButton.setTextSize(16)
  radioButton.setPadding(0, 10, 0, 10)
  radioButton.setTag(tostring(option[1]))
  
  if option[1] == notificationMinutes then
   radioButton.setChecked(true)
  end
  
  radioGroup.addView(radioButton)
  radioButtons[i] = radioButton
 end
 
 layout.addView(radioGroup)
 
 local function updateTimeOptionsVisibility()
  if notificationSwitch.isChecked() then
   radioGroup.setVisibility(View.VISIBLE)
   timeLabel.setVisibility(View.VISIBLE)
  else
   radioGroup.setVisibility(View.GONE)
   timeLabel.setVisibility(View.GONE)
  end
 end
 
 updateTimeOptionsVisibility()
 
 notificationSwitch.setOnCheckedChangeListener({
  onCheckedChanged = function(button, isChecked)
   notificationEnabled = isChecked
   updateTimeOptionsVisibility()
   service.speak("Notification " .. (isChecked and "enabled" or "disabled"))
  end
 })
 
 local buttonLayout = LinearLayout(service)
 buttonLayout.setOrientation(0)
 buttonLayout.setGravity(17)
 buttonLayout.setPadding(0, 10, 0, 0)
 
 local saveButton = Button(service)
 saveButton.setText("Save Settings")
 saveButton.setLayoutParams(LinearLayout.LayoutParams(
  0,
  LinearLayout.LayoutParams.WRAP_CONTENT,
  1
 ))
 saveButton.setPadding(0, 0, 10, 0)
 
 local cancelButton = Button(service)
 cancelButton.setText("Cancel")
 cancelButton.setLayoutParams(LinearLayout.LayoutParams(
  0,
  LinearLayout.LayoutParams.WRAP_CONTENT,
  1
 ))
 cancelButton.setPadding(10, 0, 0, 0)
 
 buttonLayout.addView(saveButton)
 buttonLayout.addView(cancelButton)
 layout.addView(buttonLayout)
 
 saveButton.onClick = function()
  notificationEnabled = notificationSwitch.isChecked()
  
  for i, radioButton in ipairs(radioButtons) do
   if radioButton.isChecked() then
    notificationMinutes = tonumber(radioButton.getTag())
    break
   end
  end
  
  save_notification_settings()
  
  if notificationEnabled then
   for _, alarm in ipairs(alarm_data) do
    if alarm.active then
     schedule_notification_for_alarm(alarm)
    end
   end
  end
  
  settingsDlg.dismiss()
 end
 
 cancelButton.onClick = function()
  settingsDlg.dismiss()
 end
 
 settingsDlg.setView(layout)
 settingsDlg.show()
 notificationSwitch.requestFocus()
end

function showAboutDialog()
 local aboutDlg = LuaDialog(service)
 aboutDlg.setTitle("About Smart Alarm Clock Pro")
 
 local layout = LinearLayout(service)
 layout.setOrientation(1)
 layout.setPadding(40, 30, 40, 30)
 layout.setFocusable(true)
 layout.setFocusableInTouchMode(true)
 
 local titleText = TextView(service)
 titleText.setText("Smart Alarm Clock Pro")
 titleText.setTextSize(22)
 titleText.setGravity(17)
 titleText.setTextColor(0xFF2E7D32)
 titleText.setPadding(0, 0, 0, 20)
 layout.addView(titleText)
 
 local versionText = TextView(service)
 versionText.setText("Version " .. CURRENT_VERSION)
 versionText.setTextSize(16)
 versionText.setGravity(17)
 versionText.setPadding(0, 0, 0, 15)
 layout.addView(versionText)
 
 local featuresText = TextView(service)
 featuresText.setText("Features:\n• Custom Alarm Sounds\n• Vibration Settings\n• Snooze Functionality\n• Single Day Selection\n• Second Precision Timing\n• Auto Update System")
 featuresText.setTextSize(14)
 featuresText.setGravity(17)
 featuresText.setPadding(0, 0, 0, 20)
 layout.addView(featuresText)
 
 local closeButton = Button(service)
 closeButton.setText("Close")
 closeButton.setTextSize(16)
 closeButton.setOnClickListener({
  onClick = function()
   aboutDlg.dismiss()
  end
 })
 
 layout.addView(closeButton)
 aboutDlg.setView(layout)
 aboutDlg.show()
 closeButton.requestFocus()
end

function showMainDialog()
 load_alarms_from_storage()
 schedule_all_alarms()
 
 -- Auto check for updates on startup
 checkUpdate(false)
 
 local dlg = LuaDialog(service)
 dlg.setTitle("Smart Alarm Clock Pro")
 mainDialog = dlg

 local layout = ScrollView(service)
 local mainLayout = LinearLayout(service)
 mainLayout.setOrientation(1)
 mainLayout.setPadding(50, 30, 50, 30)
 mainLayout.setFocusable(true)
 mainLayout.setFocusableInTouchMode(true)

 local titleText = TextView(service)
 titleText.setText("Smart Alarm Clock Pro New")
 titleText.setTextSize(22)
 titleText.setGravity(17)
 titleText.setTextColor(0xFF2E7D32)
 titleText.setFocusable(true)
 mainLayout.addView(titleText)

 local nextAlarmText = TextView(service)
 nextAlarmText.setText(get_next_alarm_info())
 nextAlarmText.setTextSize(16)
 nextAlarmText.setGravity(17)
 nextAlarmText.setTextColor(0xFF1976D2)
 nextAlarmText.setPadding(0, 0, 0, 20)
 nextAlarmText.setTag("nextAlarmText")
 nextAlarmText.setFocusable(true)
 mainLayout.addView(nextAlarmText)

 local newAlarmButton = Button(service)
 newAlarmButton.setText("Set New Alarm")
 newAlarmButton.setTextSize(16)
 newAlarmButton.setPadding(0, 0, 0, 10)
 newAlarmButton.setFocusable(true)
 mainLayout.addView(newAlarmButton)

 local viewAlarmsButton = Button(service)
 viewAlarmsButton.setText("View Current Alarms")
 viewAlarmsButton.setTextSize(16)
 viewAlarmsButton.setPadding(0, 0, 0, 10)
 viewAlarmsButton.setFocusable(true)
 mainLayout.addView(viewAlarmsButton)

 local notificationButton = Button(service)
 notificationButton.setText("Upcoming Notification")
 notificationButton.setTextSize(16)
 notificationButton.setPadding(0, 0, 0, 10)
 notificationButton.setFocusable(true)
 mainLayout.addView(notificationButton)

 local stopAllAlarmsButton = Button(service)
 stopAllAlarmsButton.setText("Stop All Alarms")
 stopAllAlarmsButton.setTextSize(16)
 stopAllAlarmsButton.setPadding(0, 0, 0, 10)
 stopAllAlarmsButton.setFocusable(true)
 mainLayout.addView(stopAllAlarmsButton)

 local alarmDurationButton = Button(service)
 alarmDurationButton.setText("Alarm Sound Duration: " .. (alarmDuration / 1000) .. " seconds")
 alarmDurationButton.setTextSize(16)
 alarmDurationButton.setPadding(0, 0, 0, 10)
 alarmDurationButton.setFocusable(true)
 alarmDurationButton.setTag("alarmDurationButton")
 mainLayout.addView(alarmDurationButton)

 local testAlarmButton = Button(service)
 testAlarmButton.setText("Test Alarm (3 seconds)")
 testAlarmButton.setTextSize(16)
 testAlarmButton.setPadding(0, 0, 0, 10)
 testAlarmButton.setFocusable(true)
 mainLayout.addView(testAlarmButton)

local checkUpdateButton = Button(service) if updateAvailable then   checkUpdateButton.setText("New Update Available") else   checkUpdateButton.setText("Check Update") end checkUpdateButton.setTextSize(16) checkUpdateButton.setPadding(0, 0, 0, 10) checkUpdateButton.setFocusable(true) check