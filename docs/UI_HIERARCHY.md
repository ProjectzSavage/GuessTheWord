# GameUI — Instance Hierarchy & Naming Convention

> Create this `ScreenGui` **manually** in `StarterGui`. The scripts locate every
> element by the exact **Name** shown below. Do **not** rename anything or the
> scripts will error loudly on `WaitForChild` (which is intentional — it makes
> mistakes obvious).

## Top-level tree

```
StarterGui
└── GameUI  (ScreenGui)          IgnoreGuiInset = true
    ├── TopBar  (Frame)          AnchorPoint(0.5,0) Position(0.5,0) Size(0,64 x 0,64) BackgroundColor3 dark
    │   ├── OpponentHeartContainer (Folder)
    │   │   ├── Heart1  (ImageLabel)
    │   │   ├── Heart2  (ImageLabel)
    │   │   └── Heart3  (ImageLabel)
    │   ├── TimerLabel (TextLabel)      centered, shows "15"
    │   └── PlayerHeartContainer (Folder)
    │       ├── Heart1  (ImageLabel)
    │       ├── Heart2  (ImageLabel)
    │       └── Heart3  (ImageLabel)
    │
    ├── PuzzleArea  (Frame)      center of screen
    │   ├── ImageGrid  (Frame)   UIGridLayout: 2x2, 4 ImageLabels (clue images)
    │   │   ├── Clue1 (ImageLabel)
    │   │   ├── Clue2 (ImageLabel)
    │   │   ├── Clue3 (ImageLabel)
    │   │   └── Clue4 (ImageLabel)
    │   ├── AnswerBox  (TextBox)     Font GothamBold, TextSize 36, TextEditable=false
    │   └── ScrambledBank  (Frame)   buttons are created here by InputHandler
    │
    └── InteractionFrame  (Frame)  lower area
        └── PlayVsBotButton  (TextButton)   "Play vs Bot", Visible = false initially
```

## Heart container details

Each heart `ImageLabel` is 24×24. You can space them with a `UIListLayout`
(FillDirection = Horizontal, Padding = 4), or hard-position them:
Heart1 x=0, Heart2 x=30, Heart3 x=60.

```
OpponentHeartContainer          PlayerHeartContainer
   ├─ Heart1                     ├─ Heart1
   ├─ Heart2                     ├─ Heart2
   └─ Heart3                     └─ Heart3
```

- **OpponentHeartContainer** — shows the enemy player's remaining hearts.
- **PlayerHeartContainer** — shows your own remaining hearts.
- `HeartN.Image` should be your heart texture (`rbxassetid://...`).

> **Important:** The scripts shipped in this repo drive the **hearts above the
> head** (`ServerStorage.HeartHUD` BillboardGui) via the `HeartUpdate`
> RemoteEvent. To also populate the two TopBar containers, add a small client
> listener (e.g. inside InputHandler or a UIController) that subscribes to
> `HeartUpdate` and toggles `Heart1/2/3` in the matching container. Everything
> you need is already in `ReplicatedStorage.Events`.

## ScrambledBank (dynamic)

Do **not** create buttons by hand. `InputHandler` creates `TextButton`s named
`Letter1..N` inside `ScrambledBank` on every `RoundStart`, lays them out with a
`UIListLayout`, and wires click handling automatically.

## HeartHUD (above-head BillboardGui) — in ServerStorage

This is the **template** the Hearts server script clones onto every character
Head (visible to all players):

```
ServerStorage
└── HeartHUD  (BillboardGui)   Size(0,150,0,40) StudsOffset(0,3,0) AlwaysOnTop=true MaxDistance=200
    └── HeartFrame  (Frame)    BackgroundTransparency=1
        ├── UIListLayout       FillDirection=Horizontal, Padding=6, VerticalAlignment=Center
        ├── Heart1  (ImageLabel)  24x24
        ├── Heart2  (ImageLabel)  24x24
        └── Heart3  (ImageLabel)  24x24
```

## Heart image resolution (256px vs 512px)

The on-screen size of a heart is **not** set by the asset's pixel dimensions — it
is set by the `ImageLabel.Size` (here in studs/scale) and the billboard's
`StudsOffset`. The asset resolution only affects how sharp the icon is.

- **512 × 512 px** — recommended. Crisp on high-DPI/4K displays and leaves
  headroom if you ever scale a heart up. Use a `.png`.
- **256 × 256 px** — fine for small icons like these and slightly lighter to
  upload. Perfectly acceptable for a 24×24 (or ~2 stud) heart.

Since your hearts are rendered above heads and fairly small, both work. Pick
**512** if you want the best edge quality; the trade-off is a marginally larger
texture size. Use the same heart asset for the top-bar containers too.
