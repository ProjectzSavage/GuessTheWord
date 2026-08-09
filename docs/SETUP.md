# Guess The Word — Roblox Studio Setup

This guide takes you from a fresh (or existing) place to a running 1v1 word
puzzle game. All scripts are already written in `src/` — you just paste them in
and build the UI.

---

## 1. File-to-Studio mapping

You may (and should, for organization) put the server scripts in a folder named
`Scripts` inside `ServerScriptService`. Scripts run from any descendant location
in `ServerScriptService`, so a `ServerScriptService > Scripts > ...` folder
works exactly the same. Suggested layout:

```
ServerScriptService
└── Scripts  (Folder)
    ├── SetupEvents.server.luau     # Script
    ├── GameManager.server.luau     # Script
    └── Hearts.server.luau          # Script
```

| Repo file                                                        | Studio location             | Script type |
| ---------------------------------------------------------------- | --------------------------- | ----------- |
| `src/ServerScriptService/SetupEvents.server.luau`               | `ServerScriptService > Scripts` | Script   |
| `src/ServerScriptService/GameManager.server.luau`               | `ServerScriptService > Scripts` | Script   |
| `src/ServerScriptService/Hearts.server.luau`                    | `ServerScriptService > Scripts` | Script   |
| `src/ServerStorage/Modules/Dictionary.luau`                     | `ServerStorage > Modules`   | ModuleScript |
| `src/StarterPlayerScripts/InputHandler.client.luau`             | `StarterPlayerScripts`      | LocalScript |

> **Tip:** For each file, right-click the target container in Studio →
> **Insert Object** → choose the right type, name it, then paste the file's
> contents into the script editor.

---

## 2. Create the UI

Build the exact tree in `docs/UI_HIERARCHY.md` **manually** in `StarterGui`:

- `GameUI` ScreenGui with `TopBar`, `PuzzleArea`, `InteractionFrame`.
- Heart `Folder`s with `ImageLabel`s named exactly `Heart1/2/3`.
- `AnswerBox` (TextBox), `ScrambledBank` (Frame), `PlayVsBotButton` (TextButton).
- Put your own heart textures and clue image asset IDs where the docs say.

The `ScrambledBank` buttons and the above-head `HeartHUD` are handled by code —
do not build those by hand (the billboard template in `ServerStorage` is the one
exception; see `UI_HIERARCHY.md`).

---

## 3. Workspace layout (already in your place)

```
Workspace
└── GameArea  (Folder)
    └── Table1  (Folder)
        ├── Table        (existing part/model)
        ├── Seat1        (existing Seat)
        └── Seat2        (existing Seat)
```

- `GameManager` auto-detects any `GameArea` child folder whose name starts with
  `Table` (`Table1`, `Table2`, …) and needs **at least 2 Seats** in it.
- Seats are referenced — never created. Add more tables by duplicating `Table1`.
- The word images come from the `Dictionary` module in `ServerStorage.Modules`.

---

## 4. Game flow (what to expect)

1. A player sits in `Seat1`.
2. Server fires `OpponentState(waiting=true)` → the `PlayVsBotButton` appears.
3. Either a second player sits in `Seat2` (normal 1v1), or the first player
   clicks **Play vs Bot** (a bot rig spawns in the empty seat immediately).
4. `GameManager` picks a word, scrambles its letters, and sends
   `RoundStart(wordLength, letterBank, images)`.
5. Players click / type letters. On full length, `SubmitGuess` is fired.
6. Server validates: correct → opponent −1 heart; timeout (15s) → both −1 heart.
7. First to 0 hearts loses. Survivor (or draw) is announced, then auto-rematch.

---

## 5. Adding your own words

Open `Dictionary.luau` and add entries like:

```lua
{
    word = "lamp",
    images = {
        "rbxassetid://LAMP_1",
        "rbxassetid://LAMP_2",
        "rbxassetid://LAMP_3",
        "rbxassetid://LAMP_4",
    },
},
```

> Keep `word` lowercase. The server compares the normalized guess to it, so the
> client can never fake a correct answer.

---

## 6. Tuning

Everything is configurable at the top of `GameManager.server.luau`:

```lua
local HEARTS_PER_PLAYER = 3
local ROUND_TIME = 15
local BOT_THINK_TIME = 0.45
local REMATCH_DELAY = 5
```

---

## 7. Troubleshooting

- **"No 'Table*' folders found…"** — make sure the Table folder is directly
  under `GameArea` and named `Table1` (etc.), with two Seats inside.
- **`HeartUpdate` / billboard not appearing** — check `ServerStorage.HeartHUD`
  exists and has a `HeartFrame` with `Heart1/2/3`.
- **Client errors on `WaitForChild`** — your `GameUI` hierarchy doesn't match
  `docs/UI_HIERARCHY.md` exactly. Match the names.
- **Bots don't move** — expected; the bot is a placeholder random-guessing AI
  (difficulty selection is a future update).
- Run `SetupEvents.server.luau` first on server start so all RemoteEvents exist.
