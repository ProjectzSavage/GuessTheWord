--[[
	ChairsConfig.luau  (ModuleScript)  -- place in ReplicatedStorage
	----------------------------------------------------------------------------
	Shared config for the chair system. Both the server (ChairService) and the
	client (InventoryController) read this so prices and chair names match.

	CHAIR MODELS
	The actual chair models live in ReplicatedStorage.Chairs (a Folder). Each
	model must be named exactly like a key here (e.g. "Gamer", "ProGamer",
	"SuperFire", ...). The DISPLAY chairs are in Workspace.DisplayChairs (those
	are what players click to buy).

	PRICES (in Cash, the in-game leaderstats.Cash)
	Wooden is the default/basic chair (price 0, always owned).
]]

return {
	-- How high above a seat the chair model should spawn (studs).
	ChairHeight = 1.0,

	-- Which axis of a chair model is its "front" (points toward the table /
	-- the player facing the opponent). Standard Roblox furniture fronts are
	-- usually -Z. If a chair faces backward or sideways, change this to
	-- "+Z", "-X", or "+X" for that chair.
	FrontAxis = "-Z",

	-- Name -> price (cash). Model in ReplicatedStorage.Chairs must match Name.
	Chairs = {
		Gamer     = 15000,
		ProGamer  = 25000,
		SuperFire = 10000,
		Diamond   = 7500,
		Toxic     = 5000,
		Thunder   = 3750,
		Icey      = 2500,
		Steel     = 1250,
		Broken    = 500,
		Wooden    = 0, -- default/basic
	},
}
