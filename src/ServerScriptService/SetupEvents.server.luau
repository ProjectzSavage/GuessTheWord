--[[
	SetupEvents.server.luau
	----------------------------------------------------------------------------
	Run this as a regular **Script** (server) in ServerScriptService.

	PURPOSE
	It guarantees that the "Events" folder and every RemoteEvent the game uses
	exist inside ReplicatedStorage, regardless of whether they were also made by
	hand. This makes the project resilient: if you forget to create one, it is
	created automatically on server start.

	All other scripts (GameManager, Hearts, InputHandler) reference these events
	via ReplicatedStorage.Events.<Name>. Do NOT rename them.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Names of every RemoteEvent the game uses.
local EVENT_NAMES = {
	"PlayVsBotRequest", -- Client -> Server : player wants to play vs a bot
	"SubmitGuess",      -- Client -> Server : player submits a word
	"TimerUpdate",      -- Server -> Client : round countdown tick
	"Countdown",        -- Server -> Client : pre-match 3..2..1 countdown
	"HeartUpdate",      -- Server -> Client : this player's heart count changed
	"RoundStart",       -- Server -> Client : new round data (bank, images, length)
	"RoundEnd",         -- Server -> Client : round finished (correct/timeout)
	"GameOver",         -- Server -> Client : match finished
	"OpponentState",    -- Server -> Client : waiting-for-opponent flag
}

-- Idempotent: if the folder already exists, reuse it (don't wipe manual setup).
local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
if not eventsFolder then
	eventsFolder = Instance.new("Folder")
	eventsFolder.Name = "Events"
	eventsFolder.Parent = ReplicatedStorage
end

for _, eventName in EVENT_NAMES do
	if not eventsFolder:FindFirstChild(eventName) then
		local remote = Instance.new("RemoteEvent")
		remote.Name = eventName
		remote.Parent = eventsFolder
	end
end

print("[SetupEvents] All", #EVENT_NAMES, "RemoteEvents are ready in ReplicatedStorage.Events.")
