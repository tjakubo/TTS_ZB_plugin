local socket = require 'socket'
-- "Get TTS scripts" menu item
local getScriptsID = ID('TTS.GetScripts')
-- "Send TTS scripts" menu item
local sendScriptsID = ID('TTS.SendScripts')
-- Temporary IDE restart toolbar item
local restartID = ID('TTS.RestartIDE')

local json = require 'json'
local lfs = require 'lfs'

local TTS = {}

-- Send a string to TTS server
-- If skipResponse if not true, wait for TTS client to respond and return decoded JSON of it
function TTS.Communicate(stringToSend, skipResponse)
    local host, clientPort, serverPort = 'localhost', 39999, 39998
    
    -- Connect as a client and send the string
    local tcp = assert(socket.tcp(), 'Could not open a TCP connection')
    assert(tcp:connect(host, clientPort), 'Could not connect to Tabletop Simulator server')
    assert(tcp:send(stringToSend), 'Could not send data to Tabletop Simulator')
    
    if skipResponse then
        tcp:close()
        return true
    end

    -- Create a server and wait for response
    local server = assert(socket.bind('*', serverPort), 'Could not create a TCP server')
    local client = server:accept()
    client:settimeout(5)
    local response, err = client:receive('*a')
    
    client:close()
    tcp:close()
    return json.decode((response or '{}'):gsub('\r\n', '\n'))
end

-- Request scripts from TTS, write them to 'scripts' dir in current project dir
-- Moves everything from 'scripts' dir to 'backup' subdir (cleared beforehand)
function TTS.GetLuaScripts()
    -- Get the TTS scripts table
    local scriptTable = TTS.Communicate('{ messageID: 0 }')
    
    -- Scripts and last load backup dir
    local scriptDir = ide:GetProject() .. '/scripts'
    -- Make sure they exist
    lfs.mkdir(scriptDir)
    lfs.mkdir(scriptDir .. '/backup')
    
    -- Delete stuff from backup dir
    for file in lfs.dir(scriptDir .. '/backup') do
        if file:find('%.lua') then
            os.remove(scriptDir .. '/backup/' .. file)
        end
    end
    -- Move stuff from scripts dir to backup dir
    for file in lfs.dir(scriptDir) do
        if file:find('%.lua') then
            os.rename(scriptDir .. '/' .. file, scriptDir .. '/backup/' .. file)
        end
    end
    -- Create files with loaded scripts
    for _,data in ipairs(scriptTable.scriptStates) do
        -- Change spaces to underscores and cut out slashes from object name
        local filename = data.name:gsub(' ', '_'):gsub('/', '') .. '.' .. data.guid .. '.lua'
        local file = io.open(scriptDir .. '/' .. filename, 'w')
        file:write(data.script)
        file:close()
    end
end

-- Send stuff from 'scripts' dir in current project dir to TTS
-- GUIDs take from filenames ('filename.GUID.lua')
function TTS.SendLuaScripts()
    local data = { messageID = 1, scriptStates = {}}
    for filename in lfs.dir(ide:GetProject() .. '/scripts') do
        ide:Print(filename)
        local guid = filename:match('%.(.-)%.lua')
        if guid then
            local newScript = {}
            newScript.guid = guid
            local file = io.open(ide:GetProject() .. '/scripts/' .. filename)
            newScript.script = file:read('*a')
            data.scriptStates[#data.scriptStates + 1] = newScript
            file:close()
        end
    end
    TTS.Communicate(json.encode(data), true)
end

-- Custom interpreter option
local interpreter = {
    name = 'Tabletop Simulator',
    description = 'TTS scripting server/client',
    -- Action for the green arrow "run" icon on the top toolbar
    frun = function(self, wfilename, rundebug)
        TTS.SendLuaScripts()
    end,
    hasdebugger = false,
}

return {
    name = 'TTS scripting server/client',
    description = 'Allows for easy script file exchange with running Tabletop Simulator instance',
    author = 'dzikakulka',
    version = 0.1,
    dependencies = {1.6, osname = 'Windows'},

    onRegister = function(self)
        -- Add the intepreter option
        ide:AddInterpreter('TTS', interpreter)
        -- Add the menu item for getting TTS scripts
        ide:FindTopMenu("&Project"):Append(getScriptsID, "Get TTS scripts")
        ide:GetMainFrame():Connect(getScriptsID, wx.wxEVT_COMMAND_MENU_SELECTED, function()
            TTS.GetLuaScripts()
        end)
        -- Add the menu item for sending TTS scripts
        ide:FindTopMenu("&Project"):Append(sendScriptsID, "Save and Play")
        ide:GetMainFrame():Connect(sendScriptsID, wx.wxEVT_COMMAND_MENU_SELECTED, function()
            TTS.SendLuaScripts()
        end)
        -- Add the menu item for quick IDE restart
        ide:FindTopMenu("&Project"):Append(restartID, "Restart")
        ide:GetMainFrame():Connect(restartID, wx.wxEVT_COMMAND_MENU_SELECTED, function()
            ide:Restart()
        end)
        ide:Print('TTS scripting plugin loaded')
    end,

    onUnRegister = function(self)
        ide:RemoveInterpreter('TTS')
    end,
}
