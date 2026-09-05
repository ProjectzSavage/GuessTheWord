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
	"HeartUpdate",         -- Server -> Client : this player's heart count changed
	"OpponentHeartUpdate", -- Server -> Client : the opponent's heart count changed
	"RoundStart",       -- Server -> Client : new round data (bank, images, length)
	"RoundEnd",         -- Server -> Client : round finished (correct/timeout)
	"GameOver",         -- Server -> Client : match finished
	"OpponentState",    -- Server -> Client : waiting-for-opponent flag
	"WrongGuess",       -- Server -> Client : a full-length guess was wrong
	"PreloadClueImages", -- Server -> Client : all clue image IDs to preload
	"CashReroll",      -- Server -> Client : start a cash reward reroll animation
	"CashAwarded",     -- Server -> Client : tell client which cash value won
	"PowerupUse",      -- Client -> Server : use a powerup (Letter/Word)
	"PowerupGrant",    -- Server -> Client : server reveals the letter/word
	"PurchasePowerup", -- Client -> Server : buy a powerup with robux (prompts the 1-use dev product)
	"LeaveSeat",       -- Client -> Server : player leaves their chair (cancel)
	"RewardSync",      -- Server -> Client : rewards payload (categories/rows)
	"RewardClaim",     -- Client -> Server : claim a reward (category, id)
	"RewardRequestSync", -- Client -> Server : ask for a fresh sync
	"AddRobuxSpent",   -- Client -> Server : add to robux-spent total (on purchase)
	"NotifyPlayer",    -- Server -> Client : popup notification message
	"BuyChair",        -- Client -> Server : buy a chair (name)
	"EquipChair",      -- Client -> Server : equip a chair (name)
	"ChairSync",       -- Server -> Client : owned chairs + equipped chair
	"QuestSync",       -- Server -> Client : quests payload (progress + claimed)
	"QuestClaim",      -- Client -> Server : claim a completed quest
	"QuickPlayRequest", -- Client -> Server : quick play mode ("Bot" / "Player")
	"QuickPlayResult",  -- Server -> Client : (mode, success, note) after quick play
	"PurchaseSuccess",  -- Server -> Client : Robux purchase completed (confetti + sound)
	"RequestChairSync", -- Client -> Server : ask for a fresh chair sync
	"StealRequest",     -- Client -> Server : thief clicks a steal button (victimUserId)
	"MatchCancelled",   -- Server -> Client : countdown ended early (someone exited) -> full reset
	"ClaimFreeReward",  -- Client -> Server : claim the free gift (favorite + group check done)
	"FreeRewardResult", -- Server -> Client : (success, message) after a free gift claim
	"SpectatorData",    -- Server -> Client : match state of a table (bank, live guesses, hearts)
	"SpectatorGuess",   -- Client -> Server : a player's live in-progress guess (for spectators)
	"RestoreStreakPrompt", -- Server -> Client : (lostStreak, productId) buy-back prompt after a lost streak
	"RestoreStreakResult",  -- Server -> Client : (success, restoredStreak) after a restore purchase
	"GlobalLeaderboardsPush", -- Server -> Client : all-time world top lists (cash/wins/streak)
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


