# Guess The Word — Roblox Studio Setup

This guide takes you from a fresh (or existing) place to a running 1v1 word
puzzle game. All scripts are already written in `src/` — you just paste them in
and build the UI.

---

## 🚀 ROJO (recommended — no more pasting)

Rojo keeps `src/` and Studio in sync automatically: every script below is
placed exactly where it should be (see the table at the bottom), and new files
appear in Studio on their own.

1. **Install the Rojo CLI** (pick one):
   - `npm install -g @rojo-rbx/rojo`
   - `brew install rojo`
   - or download a zip from https://github.com/rojo-rbx/rojo/releases
2. **Install the Rojo Studio plugin**: in Studio → *Plugins* tab → *Toolbox*
   → search **"Rojo"** (by Erik/Roblox Dev Tools) → Install.
3. **Connect** — the Rojo plugin in Studio asks for a **localhost address:
   that's normal, leave it as `localhost:3487`** (the default). Then:
   - Open a terminal **in this repo's folder** and run
     `rojo serve default.project.json` — **keep that terminal running**.
   - In Studio click the **Rojo** icon in the bottom bar → **Connect**
     (host `localhost:3487`, the pre-filled value). The icon turns green /
     says *Connected* and every script from `src/` appears in the Explorer
     automatically.
   - (Alternative without the CLI: in Studio *File → Open* → select
     **`default.project.json`** from this repo → the Rojo dock appears →
     click **Attach to Studio**.)
4. That's it — edit files in `src/` and Studio updates live (re-sync icon).
   Don't edit the synced scripts inside Studio; edit them in the repo.

> If Connect says *failed / not found*, the `rojo serve` terminal isn't
> running in the repo folder (or the server was closed). Start it, wait for
> "Serving ..." in the terminal, then Connect again.

> The project file (`default.project.json`) maps: `src/ReplicatedStorage` →
> ReplicatedStorage, `src/ServerScriptService` → ServerScriptService,
> `src/ServerStorage` → ServerStorage, `src/StarterPlayerScripts` →
> StarterPlayerScripts. `.server.luau` → Script, `.client.luau` → LocalScript,
> plain `.luau` → ModuleScript.

> **Gamepasses / products:** the scripts read their prices & ownership from the
> real Creator Hub ids already filled in — in Studio, enable
> *Game Settings → Security → Enable Studio Access to API Services* to test
> gamepass logic (VIP, chairs, starter pack) before publishing.

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
6. **SFX** — fill the `SFX.Sounds` table in `ReplicatedStorage.SFX` (a
   ModuleScript) with your sound IDs using the full `"rbxassetid://..."` format
   (optional; unused ones are skipped).
7. **Workspace** — `Workspace.GameArea.Table1` (Folder) containing your `Table`
   + 2 `Seat`/`VehicleSeat` instances.
8. **CameraAnchor (recommended for 2-player view)** — add a Part named
   `CameraAnchor` inside each `TableN` folder, positioned where the camera
   should sit (above/behind the table). When a match starts, both players'
   cameras focus there. If absent, the camera falls back to behind the `Table`
   model, then to the midpoint of the two seats.
9. **Cash reward models** — put the 6 models (`Cash100`…`Cash5000`) in
   `ReplicatedStorage.CashRewards` (NOT in the table folders), and add a single
   `CashAnchor` part in each `TableN` folder. `RerollController.client.luau`
   clones the models to the anchor and animates the reroll (winner sparkles +
   "+$X" flash). If missing, it skips (cash still awards).
10. **Nametag + streak (optional)** — `Nametag.server.luau` uses a **BillboardGui
   template named `Nametag`** as a child of the script (`PlayerName`, optional
   `Icons` frame with `Premium`/`Owner`/`Admin`, optional `StreakRow` with
   `StreakIcon` + `Streak`). If you don't build one, it auto-creates a scale-based
   name + streak tag. **Milestone icons**: fill in `StreakMilestones` at the top
   of the script (threshold → icon image) so the streak icon upgrades as the
   player reaches 5 / 10 / 25 / 50 etc. Add the script to
   `ServerScriptService > Scripts`. Use **Scale, not offset**, for any labels you
   build.
11. **RewardsService config** — add `RewardsService.server.luau` to
   `ServerScriptService > Scripts`. Set the config at the top: `GROUP_ID` (your
   group), `VIP_GAMEPASS_ID` (your VIP gamepass), `SOCIAL_OWNERS` (the owners to
   follow), and fill in the reward image IDs in `REWARD_IMAGES` (both server and
   client). The client `RewardsController` renders whatever the server sends.
12. **Chair system** — create `ReplicatedStorage.Chairs` (Folder) with the chair
    Models named like the `ChairsConfig` keys (Gamer, ProGamer, SuperFire,
    Diamond, Toxic, Thunder, Icey, Steel, Broken, Wooden, HackerChair,
    SpacialMist, PinkVortex). Keep your display chairs in `Workspace.DisplayChairs`
    (prompts are added automatically). Build
    the `InventoryF` UI (or let the controller auto-create it). Add
    `ChairService.server.luau` to `ServerScriptService > Scripts`.
    - **VIP chair (you build it):** make a Model named exactly **`VIPChair`**
      inside `ReplicatedStorage.Chairs` (it's the template used when a VIP
      player sits and the one shown in the inventory preview). Optionally drop
      a copy named `VIPChair` into `Workspace.DisplayChairs` too — it will get
      a **"Get VIP"** prompt that opens the VIP gamepass purchase instead of a
      cash price. VIP owners get it automatically (on join + on purchase);
      the 3 Robux-exclusive chairs (HackerChair/SpacialMist/PinkVortex) are
      NOT part of VIP anymore.

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
| `src/ServerScriptService/RewardsService.server.luau`            | `ServerScriptService > Scripts` | Script   |
| `src/ServerStorage/Modules/Dictionary.luau`                     | `ServerStorage > Modules`   | ModuleScript |
| `src/ServerStorage/Modules/HeartHUDManager.luau`                | `ServerStorage > Modules`   | ModuleScript |
| `src/ServerStorage/Modules/PlayerPerks.luau`                    | `ServerStorage > Modules`   | ModuleScript |
| `src/ReplicatedStorage/LetterImages.luau`                      | `ReplicatedStorage`         | ModuleScript |
| `src/ReplicatedStorage/HoverFX.luau`                          | `ReplicatedStorage`         | ModuleScript |
| `src/ReplicatedStorage/UIFX.luau`                            | `ReplicatedStorage`         | ModuleScript |
| `src/ReplicatedStorage/SFX.luau`                            | `ReplicatedStorage`         | ModuleScript |
| `src/StarterPlayerScripts/InputHandler.client.luau`             | `StarterPlayerScripts`      | LocalScript |
| `src/StarterPlayerScripts/HoverController.client.luau`          | `StarterPlayerScripts`      | LocalScript |
| `src/StarterPlayerScripts/Preloader.client.luau`                | `StarterPlayerScripts`      | LocalScript |
| `src/StarterPlayerScripts/CameraController.client.luau`         | `StarterPlayerScripts`      | LocalScript |
| `src/StarterPlayerScripts/RerollController.client.luau`         | `StarterPlayerScripts`      | LocalScript |
| `src/StarterPlayerScripts/StatsPanel.client.luau`               | `StarterPlayerScripts`      | LocalScript |
| `src/StarterPlayerScripts/RewardsController.client.luau`        | `StarterPlayerScripts`      | LocalScript |
| `src/StarterPlayerScripts/ButtonsController.client.luau`        | `StarterPlayerScripts`      | LocalScript |
| `src/StarterPlayerScripts/ShopController.client.luau`           | `StarterPlayerScripts`      | LocalScript |
| `src/ServerScriptService/ShopService.server.luau`               | `ServerScriptService > Scripts` | Script   |
| `src/ServerScriptService/QuestService.server.luau`              | `ServerScriptService > Scripts` | Script   |
| `src/StarterPlayerScripts/QuestController.client.luau`          | `StarterPlayerScripts`      | LocalScript |
| `src/ServerScriptService/ChairService.server.luau`              | `ServerScriptService > Scripts` | Script   |
| `src/ServerScriptService/StarterPack.server.luau`               | `ServerScriptService > Scripts` | Script   |
| `src/ReplicatedStorage/ChairsConfig.luau`                      | `ReplicatedStorage`         | ModuleScript |
| `src/StarterPlayerScripts/InventoryController.client.luau`      | `StarterPlayerScripts`      | LocalScript |
| `src/ServerStorage/Modules/ReceiptRouter.luau`                  | `ServerStorage > Modules`   | ModuleScript |
| `src/ServerStorage/Modules/CashRerollFX.luau`                   | `ServerStorage > Modules`   | ModuleScript |
| `src/ServerScriptService/TheftService.server.luau`              | `ServerScriptService > Scripts` | Script   |
| `src/StarterPlayerScripts/SpeechBubble.client.luau`             | `StarterPlayerScripts`      | LocalScript |
| `src/StarterPlayerScripts/StealPromptUI.client.luau`            | `StarterPlayerScripts`      | LocalScript |
| `src/StarterPlayerScripts/FreeRewards.client.luau`              | `StarterPlayerScripts`      | LocalScript |

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

**Cinematic effects** — when the countdown or puzzle is on screen, the match
automatically blurs the background and smoothly raises the camera FOV, easing
back when it ends. ALL environment FX (blur, FOV, StatsPanel slide, quest
collapse) are owned by ONE module: `ReplicatedStorage.UIFX` (a single derived
state machine fed by the match cinematic + open windows). Do not add your own
`BlurEffect` or camera FOV tweens elsewhere — that is exactly what used to
leave the screen stuck blurred/zoomed.
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
        ├── CameraAnchor (Part, optional)  -- where the match camera sits
        └── CashAnchor   (Part)            -- block where the cash reroll happens

Cash reward models do NOT go in the table folders. Put them in:
    ReplicatedStorage
    └── CashRewards  (Folder)
        ├── Cash100   (Model)
        ├── Cash350   (Model)
        ├── Cash750   (Model)
        ├── Cash1500  (Model)
        ├── Cash3500  (Model)
        └── Cash5000  (Model)
RerollController clones them and animates them at each table's `CashAnchor`.
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

**Bot difficulty:** clicking "Play vs Bot" (or "Play vs Bot again" after a
match) opens a **DifficultySelector** (Easy/Medium/Hard). Each difficulty caps
the cash-reward roll's max cash (Easy $100 / Medium $350 / Hard $750) and tunes
the bot's speed/consistency. The bot builds guesses from the word's own letters
so it can actually answer. The difficulty buttons can be nested inside a
`Difficulties` frame — the script finds them recursively.

**Correct-answer beat:** when the answer is found, the server hides the
`PuzzleArea`, waits 2s, makes the loser's heart disappear, waits another 2s, then
starts the next round (which reshores the puzzle). The heart fade is animated in
`InputHandler`.

**Filler letters:** the bank always contains 12 letters — the word's letters are
guaranteed present, the rest are random `a–z` fillers (`Dictionary.BANK_LETTERS`
= 12, adjustable).

**Leaderboard:** every player gets `leaderstats` with **Cash** (first) and
**Wins**. **Streak** (consecutive wins) is stored in a separate hidden `Stats`
folder — it is NOT shown on the Roblox leaderboard. A win +1 Wins/+1 Streak; a
loss or draw resets Streak.

**Cash rewards:** after the countdown, before the GUI pops, a **cash reroll
animation** plays on the table (100/350/750/1500/3500/5000 with weighted odds).
The chosen cash is added to the player's `leaderstats.Cash` (shown on the
leaderboard).

**Jump out of the chair:** before a match you can jump out (the Play vs Bot
toggle outros). During an active match your jump is **locked** so you can't leave
mid-game. After the match you can jump out again (the pause screen outros).

**Opponent leaves mid-match:** if your opponent disconnects/leaves during a
match, you **win it** exactly like a normal victory (Wins/Streak updated).

## 6. Sound effects

`ReplicatedStorage.SFX` is a ModuleScript with a `SFX.Sounds` table at the top.
Fill in your sound IDs using the **full format** `"rbxassetid://117751546358455"`
(prefix + digits), leaving unused ones as `""`. It plays them at the right
moments: **separate sounds for 3, 2, 1 and GO!** (`count3`/`count2`/`count1`/
`go`), GUI-pop after game start (`uiPop`), correct/timeout, wrong guess, heart
loss (plus a "about to lose" warning on your last heart), heart restore,
win/lose/draw (+ win jingle), and letter/hover/click/botSpawn/botDespawn
(letter/click/uiPop are wired into InputHandler; hover is wired into
HoverController).

> Sounds are preloaded automatically so they play instantly. Call
> `SFX.play("name")` from any client script for extra sounds.
> There is no built-in ragdoll - the Realism Mod handles that.

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
