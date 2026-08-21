# Guess The Word

A 1v1 word-puzzle game for Roblox. Two players (or a player vs a bot) race to
guess a word hidden behind 4 images within 15 seconds. Each player has 3 hearts;
guess correctly to make your opponent lose one. First to 0 hearts loses.

Built with a **server-authoritative** design — all word guesses are validated on
the server against a server-side dictionary, never trusted from the client.

## Getting started

Follow **[`docs/SETUP.md`](docs/SETUP.md)** for step-by-step Studio setup.

- **[`docs/UI_HIERARCHY.md`](docs/UI_HIERARCHY.md)** — the exact Instance
  hierarchy and naming convention for `GameUI` and the `HeartHUD` billboard.

## Project structure

```
src/
├── ServerScriptService/
│   ├── SetupEvents.server.luau     # auto-creates ReplicatedStorage.Events
│   ├── GameManager.server.luau     # seats, matches, rounds, bot, validation
│   ├── Hearts.server.luau          # above-head hearts BillboardGui
│   ├── Nametag.server.luau         # name + 🔥win-streak BillboardGui
│   ├── RewardsService.server.luau  # server-authoritative rewards
│   ├── ShopService.server.luau     # Robux dev-product purchases + grants
│   ├── ChairService.server.luau    # buy/equip chairs + swap on sit
│   └── QuestService.server.luau    # daily quests (win friend/hard bot, etc.)
├── ServerStorage/
│   └── Modules/
│       ├── Dictionary.luau         # server-only word/image dictionary
│       └── HeartHUDManager.luau    # server-side hearts for players + bot
├── ReplicatedStorage/
│   ├── LetterImages.luau           # A-Z letter images for the UI
│   ├── HoverFX.luau                # reusable hover/pop effect
│   └── ChairsConfig.luau           # chair names + cash prices
└── StarterPlayerScripts/
    ├── InputHandler.client.luau    # hybrid click + keyboard input + UI
    ├── HoverController.client.luau # applies HoverFX to clues + letter tiles
    ├── Preloader.client.luau       # preloads image assets
    ├── CameraController.client.luau# focuses the table between two players
    ├── RerollController.client.luau# cash-reward reroll animation on the table
    ├── StatsPanel.client.luau      # Cash & Wins HUD + "+" buttons
    ├── RewardsController.client.luau# renders server payload in RewardsF
    ├── ButtonsController.client.luau# Features buttons (Rewards/Shop/Inventory)
    ├── ShopController.client.luau   # ShopF window + Robux buy prompts
    ├── InventoryController.client.luau# chair inventory (equip owned chairs)
    └── QuestController.client.luau   # daily quests gui (toggle + timer + claim)

## Cash & streak
- `leaderstats.Cash` (first) + `leaderstats.Wins` show on the leaderboard.
- `Stats.Streak` is hidden from the leaderboard (nametag + celebration read it).
- After the countdown a cash reroll (100–5000, weighted) awards `Cash`.
```

## Feature checklist

- [x] Seat detection via `Humanoid.Seated` / `Seat.Occupant`
- [x] Immediate "Play vs Bot" (no timer wait) with a random-guessing bot
- [x] 3 hearts, 15s rounds, correct→opponent −1, timeout→both −1
- [x] Server-side guess validation against the dictionary
- [x] Hearts above the head (BillboardGui) visible to all players
- [x] Hybrid input: click scrambled letters, type on keyboard, backspace, auto-submit
- [x] Multiple tables (`Table1`, `Table2`, …) auto-detected under `GameArea`
