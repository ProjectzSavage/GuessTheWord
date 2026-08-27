--[[
	ChairsConfig.luau  (ModuleScript)  -- place in ReplicatedStorage
	----------------------------------------------------------------------------
	Shared config for the chair system. Both the server (ChairService) and the
	client (InventoryController) read this so prices and chair names match.

	CHAIR MODELS
	The actual chair models live in ReplicatedStorage.Chairs (a Folder). Each
	model must be named exactly like a key here (e.g. "Gamer", "ProGamer",
	"SuperFire", "HackerChair", "SpacialMist", "PinkVortex", ...).

	PRICES (in Cash for in-game chairs, Gamepass for exclusive chairs)
	Wooden is the default/basic chair (price 0, always owned).
]]

return {
	-- Name -> price (cash). Model in ReplicatedStorage.Chairs must match Name.
	Chairs = {
		Gamer        = 15000,
		ProGamer     = 25000,
		SuperFire    = 10000,
		Diamond      = 7500,
		Toxic        = 5000,
		Thunder      = 3750,
		Icey         = 2500,
		Steel        = 1250,
		Broken       = 500,
		Wooden       = 0, -- default/basic

		-- Robux Exclusive Gamepass Chairs
		HackerChair  = "Gamepass",
		SpacialMist  = "Gamepass",
		PinkVortex   = "Gamepass",

		-- VIP Exclusive: granted only to VIP gamepass owners (not buyable)
		VIPChair     = "VIP",
	},

	-- Gamepass IDs for exclusive chairs (from Creator Hub)
	GamepassChairs = {
		HackerChair  = 1951965706,
		SpacialMist  = 1952367447,
		PinkVortex   = 1954710922,
	},

	-- Chairs granted to VIP gamepass owners (the VIP pass includes ONE
	-- special VIP chair - ChairService grants it automatically on join and
	-- the moment VIP is purchased).
	VIPChairs = {
		"VIPChair",
	},
}
