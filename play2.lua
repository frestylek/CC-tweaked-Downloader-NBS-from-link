local dfpwm = require("cc.audio.dfpwm")
local speakers = { peripheral.find("speaker") }
local decoder = dfpwm.make_decoder()
local http = require("http")
local json = require("dkjson") -- Upewnij się, że masz zainstalowany ten moduł

local uri = nil
local volume = settings.get("media_center.volume")
local selectedSong = nil
local songs = {}
local loop = false
local currentSongIndex = 1

-- Funkcja do pobierania listy utworów z serwera
local function fetchSongs()
    local response = http.get("http://fstandsproject.pl/songs") -- Upewnij się, że endpoint jest poprawny
    if response then
        local responseBody = response.readAll()
        local data, _, err = json.decode(responseBody)
        if data and data.files then
            return data.files
        else
            error("Błąd parsowania odpowiedzi: " .. (err or "nieznany błąd"))
        end
    else
        error("Błąd w żądaniu do serwera")
    end
end

-- Pobierz listę utworów
songs = fetchSongs()

if #songs == 0 then
    error("ERR - Brak utworów na serwerze.")
else
    local entries = {
        [1] = {
            label = "[CANCEL]",
            callback = function()
                error()
            end
        }
    }

    for i, song in ipairs(songs) do
        table.insert(entries, {
            label = song:match("^([^.]+)"), -- Usuwa rozszerzenie z nazwy pliku
            callback = function()
                selectedSong = song
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
        uri = "http://fstandsproject.pl/songs/" .. selectedSong
    else 
        error()
    end
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

print("Playing '" .. selectedSong or "unknown" .. "' at volume " .. (volume or 100.0))

local quit = false

function play()
    while not quit do
        local response = http.get(uri, nil, true)

        if response then
            local chunkSize = 4 * 1024
            local chunk = response.read(chunkSize)
            while chunk ~= nil do
                local buffer = decoder(chunk)

                while not playChunk(buffer) do
                    os.pullEvent("speaker_audio_empty")
                end

                chunk = response.read(chunkSize)
            end
        else
            print("Błąd podczas odtwarzania utworu!")
            return
        end

        -- Po zakończeniu utworu, sprawdź, czy włączono pętlę, lub przejdź do następnego utworu
        if not loop then
            currentSongIndex = currentSongIndex + 1

            if currentSongIndex > #songs then
                currentSongIndex = 1
            end

            selectedSong = songs[currentSongIndex]
            uri = "http://fstandsproject.pl/songs/" .. selectedSong

            if uri then
                print("Odtwarzanie następnego utworu: " .. selectedSong)
            else
                print("Następny utwór nie został znaleziony!")
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
            print(loop and "Pętla jest WŁĄCZONA" or "Pętla jest WYŁĄCZONA")
        end,
        ["next"] = function()
            if not loop then
                currentSongIndex = currentSongIndex + 1

                if currentSongIndex > #songs then
                    currentSongIndex = 1
                end

                selectedSong = songs[currentSongIndex]
                uri = "http://fstandsproject.pl/songs/" .. selectedSong

                if uri then
                    print("Odtwarzanie następnego utworu: " .. selectedSong)
                else
                    print("Następny utwór nie został znaleziony!")
                end
            else
                print("Nie można przeskakiwać utworów w trybie pętli.")
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
            i = i + 1
        end

        local command = commands[commandName]

        if command ~= nil then
            command(table.unpack(cmdargs))
        else 
            print('to nie jest prawidłowe polecenie!')
        end
    end
end

function waitForQuit()
    while not quit do
        sleep(0.1)
    end
end

parallel.waitForAny(play, readUserInput, waitForQuit)
