--[[
	LetterImages.luau  (ModuleScript)
	----------------------------------------------------------------------------
	Place in: ReplicatedStorage.LetterImages

	PURPOSE
	Maps each letter A-Z to an image asset so the game can display letters as
	images in the scrambled letter bank and the answer box (instead of text).

	HOW TO FILL IN
	Replace the placeholder "rbxassetid://..." values with YOUR image asset IDs.
	They must all be lowercase keys (the code uses lowercase). Example:
		a = "rbxassetid://1234567890",

	The "underscore" entry is optional: it is shown in the answer box for
	letter slots that have not been guessed yet. If you leave it empty/removed,
	unfilled slots just show an empty box.
]]

return {
	a = "rbxassetid://LETTER_A",
	b = "rbxassetid://LETTER_B",
	c = "rbxassetid://LETTER_C",
	d = "rbxassetid://LETTER_D",
	e = "rbxassetid://LETTER_E",
	f = "rbxassetid://LETTER_F",
	g = "rbxassetid://LETTER_G",
	h = "rbxassetid://LETTER_H",
	i = "rbxassetid://LETTER_I",
	j = "rbxassetid://LETTER_J",
	k = "rbxassetid://LETTER_K",
	l = "rbxassetid://LETTER_L",
	m = "rbxassetid://LETTER_M",
	n = "rbxassetid://LETTER_N",
	o = "rbxassetid://LETTER_O",
	p = "rbxassetid://LETTER_P",
	q = "rbxassetid://LETTER_Q",
	r = "rbxassetid://LETTER_R",
	s = "rbxassetid://LETTER_S",
	t = "rbxassetid://LETTER_T",
	u = "rbxassetid://LETTER_U",
	v = "rbxassetid://LETTER_V",
	w = "rbxassetid://LETTER_W",
	x = "rbxassetid://LETTER_X",
	y = "rbxassetid://LETTER_Y",
	z = "rbxassetid://LETTER_Z",

	-- Optional: image for an empty (un-guessed) slot in the answer box.
	underscore = "rbxassetid://UNDERSCORE",
}
