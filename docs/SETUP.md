# Guess The Word — Roblox Studio Setup

This guide takes you from a fresh (or existing) place to a running 1v1 word
puzzle game. All scripts are already written in `src/` — you just paste them in
and build the UI.

---

## ⚡ QUICK SETUP CHECKLIST (what YOU must do in Studio)

Everything below is something the scripts **do not** auto-create — you have to
build it once. The full details are further down.

1. **UI (`StarterGui`)** — build the `GameUI` ScreenGui from `docs/UI_HIERARCHY.md`:
   `TopBar`, `CountdownFrame` (+`CountdownLabel`), `PuzzleArea`
   (`ImageGrid` with `Clue1..4`, `AnswerBox` Frame, `ScrambledBank`), and
   `InteractionFrame` (+`PlayVsBotButton`).
   - **Set top-level frame positions in Scale, not offset**, with AnchorPoints.
   - Set the 6 TopBar `HeartN.Image`s to your heart texture.
   - `AnswerBox` must be a **Frame** (not a TextBox).
2. **Letter images** — in `ReplicatedStorage.LetterImages`, replace every
   `rbxassetid://...` with your A–Z + underscore image IDs.
3. **Word/clue images** — in `ServerStorage.Modules.Dictionary`, replace the
   placeholder `rbxassetid://...` clue images (they feed `Clue1..4`).
4. **Above-head hearts** — `ServerStorage.HeartHUD` (BillboardGui with
   `HeartFrame` + `Heart1/2/3`). Auto-created if missing (text ♥ default).
5. **Bot rig (recommended)** — `ServerStorage.BotRig` (a Model with a `Humanoid`
   + `Head`) if you want a visible bot body.
6. **SFX** — fill the `SFX` table in `StarterPlayerScripts.SFX.client.luau`
   with your sound IDs (optional; unused ones are skipped).
7. **Workspace** — `Workspace.GameArea.Table1` (Folder) containing your `Table`
   + 2 `Seat`/`VehicleSeat` instances.
8. **CameraAnchor (recommended for 2-player view)** — add a Part named
   `CameraAnchor` inside each `TableN` folder, positioned where the camera
   should sit (above/behind the table). When a match starts, both players'
   cameras focus there. If absent, the camera falls back to behind the `Table`
   model, then to the midpoint of the two seats.
9. **Nametag (optional, automatic)** — `Nametag.server.luau` builds its own
   BillboardGui in code (name + "🔥N" streak). No Studio setup needed. Just add
   the script to `ServerScriptService > Scripts`.

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
| `src/ServerScriptService/Nametag.server.luau`                   | `ServerScriptService > Scripts` | Script   |
| `src/ServerStorage/Modules/Dictionary.luau`                     | `ServerStorage > Modules`   | ModuleScript |
| `src/ServerStorage/Modules/HeartHUDManager.luau`                | `ServerStorage > Modules`   | ModuleScript |
| `src/ReplicatedStorage/LetterImages.luau`                      | `ReplicatedStorage`         | ModuleScript |
| `src/ReplicatedStorage/HoverFX.luau`                          | `ReplicatedStorage`         | ModuleScript |
| `src/ReplicatedStorage/UIFX.luau`                            | `ReplicatedStorage`         | ModuleScript |
| `src/StarterPlayerScripts/InputHandler.client.luau`             | `StarterPlayerScripts`      | LocalScript |
| `src/StarterPlayerScripts/HoverController.client.luau`          | `StarterPlayerScripts`      | LocalScript |
| `src/StarterPlayerScripts/Preloader.client.luau`                | `StarterPlayerScripts`      | LocalScript |
| `src/StarterPlayerScripts/SFX.client.luau`                      | `StarterPlayerScripts`      | LocalScript |
| `src/StarterPlayerScripts/CameraController.client.luau`         | `StarterPlayerScripts`      | LocalScript |

> **Tip:** For each file, right-click the target container in Studio →
> **Insert Object** → choose the right type, name it, then paste the file's
> contents into the script editor.

---

## 2. Create the UI

Build the exact tree in `docs/UI_HIERARCHY.md` **manually** in `StarterGui`:

- `GameUI` ScreenGui with `TopBar`, `CountdownFrame`, `PuzzleArea`,
  `InteractionFrame`.
- `CountdownFrame` (Frame) + `CountdownLabel` (TextLabel) — the 3-2-1-GO! pulse
  overlay.
- Heart `Folder`s with `ImageLabel`s named exactly `Heart1/2/3` (set each
  `HeartN.Image` to your heart texture).
- `AnswerBox` (**Frame** — not a TextBox anymore), `ScrambledBank` (Frame),
  `PlayVsBotButton` (TextButton).
- Set `TopBar.AnchorPoint = {0.5, 0}` and its resting `Position` where you want
  it (e.g. top-center). The script slides it down→up when the round starts and
  up→down when it leaves.

**Use SCALE, not offset, for all top-level frame positions.** Set each frame's
`Position` with `{X, 0},{Y, 0}` (Scale) so the layout looks right on every
screen size. Example for a top-center TopBar: `Position = {0.5, 0},{0, 0}`
with `AnchorPoint = {0.5, 0}`. The in-script slide animation already uses Scale.

**Raise the GUI** — the `PuzzleArea` is positioned in Studio; give it a slightly
higher `Position` (e.g. `{0.5, 0},{0.42, 0}` with `AnchorPoint {0.5, 0.5}`) so it
sits a touch above center.

**Cinematic effects** — when the countdown or puzzle is on screen, the script
automatically blurs the background (a `BlurEffect` in `Lighting`) and smoothly
raises the camera FOV, easing back when they close.
- Put your own heart textures and clue image asset IDs where the docs say.

The `ScrambledBank` tiles, the `AnswerBox` slots, and the above-head `HeartHUD`
are handled by code — do not build those by hand (the `HeartHUD` billboard
template in `ServerStorage` is the one exception; see `UI_HIERARCHY.md`).

### Letter images (A-Z)

In `ReplicatedStorage.LetterImages`, replace the placeholder `rbxassetid://...`
values with your letter A–Z image IDs. These images are used for the scrambled
bank tiles and the answer-box slots.

> **Frame visibility is managed by the script.** A Frame with `Visible = false`
> hides all its children, so `InputHandler` sets the top-level frames'
> `Visible` itself based on game state (timer/puzzle during play, the
> `InteractionFrame` only while waiting for an opponent). You can leave them
> `Visible = false` in Studio — the script forces the correct state at runtime.

---

## 3. Optional bot rig (recommended)

If you provide a rig in `ServerStorage` named **`BotRig`** (a Model with a
`Humanoid` and a `Head`), the game clones it onto the empty seat when a player
clicks **Play vs Bot**. The bot then has a visible body **and** hearts above its
head. If no `BotRig` exists, a minimal transparent placeholder rig is used
(no body, no hearts).

```
ServerStorage
└── BotRig  (Model)   -- Humanoid + Head + HumanoidRootPart + visual parts
```

> Make sure the rig's PrimaryPart / HumanoidRootPart is set so it can `PivotTo`
> the seat. The `Seat`/`VehicleSeat` must be reachable.

## 4. Workspace layout (already in your place)

```
Workspace
└── GameArea  (Folder)
    └── Table1  (Folder)
        ├── Table        (existing part/model)
        ├── Seat1        (existing Seat)
        ├── Seat2        (existing Seat)
        └── CameraAnchor (Part, optional)  -- where the match camera sits
```

- `GameManager` auto-detects any `GameArea` child folder whose name starts with
  `Table` (`Table1`, `Table2`, …) and needs **at least 2 Seats** in it.
- Seats are referenced — never created. Add more tables by duplicating `Table1`.
- The word images come from the `Dictionary` module in `ServerStorage.Modules`.

---

## 5. Game flow (what to expect)

1. A player sits in `Seat1`.
2. Server fires `OpponentState(waiting=true)` → the `PlayVsBotButton` appears.
   (Hearts above the head stay **hidden** until the match actually starts.)
3. Either a second player sits in `Seat2` (normal 1v1), or the first player
   clicks **Play vs Bot** (a bot rig spawns in the empty seat immediately).
4. A **3-second countdown** (3…2…1) plays in the timer label, and the hearts
   above the players' heads appear.
5. `GameManager` picks a word, builds a **12-letter bank** (the word's letters
   plus random fillers), and sends `RoundStart(wordLength, letterBank, images)`.
   The 15s round timer starts.
6. Players click / type letters. On full length, `SubmitGuess` is fired.
7. Server validates: correct → opponent −1 heart; timeout (15s) → both −1 heart.
8. First to 0 hearts loses. Survivor (or draw) is announced, and a win/lose
   celebration plays. In a bot match a **Pause screen** ("Play vs Bot again")
   appears so you can rematch from your chair.

**Correct-answer beat:** when the answer is found, the server hides the
`PuzzleArea`, waits 2s, makes the loser's heart disappear, waits another 2s, then
starts the next round (which reshores the puzzle). The heart fade is animated in
`InputHandler`.

**Filler letters:** the bank always contains 12 letters — the word's letters are
guaranteed present, the rest are random `a–z` fillers (`Dictionary.BANK_LETTERS`
= 12, adjustable).

**Leaderboard:** every player gets `leaderstats` with **Wins** and **Streak**
(consecutive wins). A win +1 Wins/+1 Streak; a loss or draw resets Streak.

**Jump out of the chair:** before a match you can jump out (the Play vs Bot
toggle outros). During an active match your jump is **locked** so you can't leave
mid-game. After the match you can jump out again (the pause screen outros).

**Opponent leaves mid-match:** if your opponent disconnects/leaves during a
match, you **win it** exactly like a normal victory (Wins/Streak updated).

## 6. Sound effects

`StarterPlayerScripts.SFX` is a LocalScript with a `SFX` table at the top. Fill
in your `rbxassetid://...` sound IDs (leave unused ones as `""`), and it plays
them at the right moments: countdown tick, GO!, correct/timeout, wrong guess,
heart loss (plus a "about to lose" warning on your last heart), heart restore,
win/lose/draw (+ win jingle), bot spawn/despawn, and letter/hover/click/standUp/
ragdoll placeholders.

## 7. Asset preloading

`Preloader.client.luau` preloads the letter images (A–Z + underscore), the TopBar
heart images, and the clue images so they don't pop in mid-round. It uses
`ContentProvider:PreloadAsync` in a background task. Add more assets to its
`content`/`instances` lists as needed.

---

## 8. Adding your own words

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

**Yes — that's all you need to do.** Adding a word is just copying this table
entry (word + 4 clue image IDs) into the `Dictionary.Entries` array. No other
code needs editing: `randomEntry`, `buildBank` (12-letter scramble), the clue
feed to `Clue1..4`, and server validation all read from this same array
automatically. Just make sure each entry has a unique `word` and 4 image IDs.

---

## 9. Tuning

Everything is configurable at the top of `GameManager.server.luau`:

```lua
local HEARTS_PER_PLAYER = 3
local ROUND_TIME = 15
local BOT_THINK_TIME = 0.45
local REMATCH_DELAY = 5
```

---

## 10. Troubleshooting

- **"No 'Table*' folders found…"** — make sure the Table folder is directly
  under `GameArea` and named `Table1` (etc.), with two Seats inside.
- **`HeartUpdate` / billboard not appearing** — check `ServerStorage.HeartHUD`
  exists and has a `HeartFrame` with `Heart1/2/3`.
- **Client errors on `WaitForChild`** — your `GameUI` hierarchy doesn't match
  `docs/UI_HIERARCHY.md` exactly. Match the names.
- **Bots don't move** — expected; the bot is a placeholder random-guessing AI
  (difficulty selection is a future update).
- Run `SetupEvents.server.luau` first on server start so all RemoteEvents exist.
