local dfpwm = require("cc.audio.dfpwm")
local speakers = { peripheral.find("speaker") }
local drive = peripheral.find("drive")
local decoder = dfpwm.make_decoder()

local menu = require "menu"

local uri = nil
local volume = settings.get("media_center.volume")
local selectedSong = nil
local songs = {}
local loop = false
local currentSongIndex = 1

if drive == nil or not drive.isDiskPresent() then
    songs = fs.list("songs/")

    if #songs == 0 then
        error("ERR - No disk was found in the drive, or no drive was found. No sound files were found saved to device.")
    else
        local entries = {
            [1] = {
                label = "[CANCEL]",
                callback = function()
                    error()
                end
            }
        }

        for i, fp in ipairs(songs) do
            table.insert(entries, {
                label = fp:match("^([^.]+)"),
                callback = function()
                    selectedSong = fp
                    currentSongIndex = i
                    menu.exit()
                end
            })
        end

        menu.init({
            main = {
                entries = entries
            }
        })

        menu.thread()

        if selectedSong ~= nil then
            local fp = "songs/" .. selectedSong

            if fs.exists(fp) then
                local file = fs.open(fp, "r")
                uri = file.readAll()
                file.close()
            else
                print("Song was not found on device!")
                return
            end
        else 
            error()
        end
    end
else
    local songFile = fs.open("disk/song.txt", "r")
    uri = songFile.readAll()
    songFile.close()
end

if uri == nil or not uri:find("^https") then
    print("ERR - Invalid URI!")
    return
end

function playChunk(chunk)
    local returnValue = nil
    local callbacks = {}

    for i, speaker in pairs(speakers) do
        if i > 1 then
            table.insert(callbacks, function()
                speaker.playAudio(chunk, volume or 1.0)
            end)
        else
            table.insert(callbacks, function()
                returnValue = speaker.playAudio(chunk, volume or 1.0)
            end)
        end
    end

    parallel.waitForAll(table.unpack(callbacks))

    return returnValue
end

print("Playing '" .. selectedSong or drive.getDiskLabel() .. "' at volume " .. (volume or 1.0))

local quit = false

function play()
    while not quit do
        local response = http.get(uri, nil, true)

        local chunkSize = 4 * 1024
        local chunk = response.read(chunkSize)
        while chunk ~= nil do
            local buffer = decoder(chunk)

            while not playChunk(buffer) do
                os.pullEvent("speaker_audio_empty")
            end

            chunk = response.read(chunkSize)
        end

        -- After song finishes, check if loop is enabled or move to next song
        if not loop then
            currentSongIndex = currentSongIndex + 1

            if currentSongIndex > #songs then
                currentSongIndex = 1
            end

            selectedSong = songs[currentSongIndex]
            local fp = "songs/" .. selectedSong

            if fs.exists(fp) then
                local file = fs.open(fp, "r")
                uri = file.readAll()
                file.close()
            else
                print("Next song was not found!")
                return
            end
        end
    end
end

function readUserInput()
    local commands = {
        ["stop"] = function()
            quit = true
        end,
        ["loop"] = function()
            loop = not loop
            print(loop and "Loop is ON" or "Loop is OFF")
        end,
        ["next"] = function()
            if not loop then
                currentSongIndex = currentSongIndex + 1

                if currentSongIndex > #songs then
                    currentSongIndex = 1
                end

                selectedSong = songs[currentSongIndex]
                local fp = "songs/" .. selectedSong

                if fs.exists(fp) then
                    local file = fs.open(fp, "r")
                    uri = file.readAll()
                    file.close()
                    print("Playing next song: " .. selectedSong)
                else
                    print("Next song was not found!")
                end
            else
                print("Cannot skip songs while in loop mode.")
            end
        end
    }

    while true do
        local input = string.lower(read())
        local commandName = ""
        local cmdargs = {}

        local i = 1
        for word in input:gmatch("%w+") do
            if i > 1 then
                table.insert(cmdargs, word)
            else
                commandName = word
            end
        end

        local command = commands[commandName]

        if command ~= nil then
            command(table.unpack(cmdargs))
        else 
            print('is not a valid command!')
        end
    end
end

function waitForQuit()
    while not quit do
        sleep(0.1)
    end
end

parallel.waitForAny(play, readUserInput, waitForQuit)
