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
    │                            -- script slides this in/out (down→up in, up→down out)
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
    ├── CountdownFrame  (Frame)     full-screen overlay for the 3-2-1-GO! pulse
    │   └── CountdownLabel (TextLabel)  big text; shown center-screen
    ├── PuzzleArea  (Frame)      center of screen
    │   ├── ImageGrid  (Frame)   UIGridLayout: 2x2, 4 ImageLabels (clue images)
    │   │   ├── Clue1 (ImageLabel)
    │   │   ├── Clue2 (ImageLabel)
    │   │   ├── Clue3 (ImageLabel)
    │   │   └── Clue4 (ImageLabel)
    │   ├── AnswerBox  (Frame)   -- letter slots are built here as ImageLabels
    │   └── ScrambledBank  (Frame)   letter tiles are created here as ImageButtons
    │
    └── InteractionFrame  (Frame)  lower area
        └── PlayVsBotButton  (TextButton)   "Play vs Bot", Visible = false initially
```

> **`AnswerBox` is now a `Frame`, not a `TextBox`.** The guessed letters are shown
> as letter IMAGES (from `ReplicatedStorage.LetterImages`). `InputHandler` clears
> `AnswerBox` and rebuilds one slot per letter on every change. Leave it empty;
> do not add children by hand.

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
- `HeartN.Image` must be your heart texture (`rbxassetid://...`). Set it once in
  Studio on each of the 6 ImageLabels; `InputHandler` only toggles their
  `Visible` to match the current count.

> **Important:** The TopBar hearts are now driven by the client script
> `InputHandler`. The server sends each player their own count via
> `HeartUpdate` and their opponent's via `OpponentHeartUpdate` (both in
> `ReplicatedStorage.Events`). `InputHandler` fills `PlayerHeartContainer` and
> `OpponentHeartContainer` accordingly. The above-head hearts
> (`ServerStorage.HeartHUD`) are still driven server-side.

## ScrambledBank (dynamic, template-based)

You may set up a **template tile** inside `ScrambledBank` and the script will
clone it once per letter (one tile per letter of the word):

```
PuzzleArea.ScrambledBank  (Frame)
    ├── UIGridLayout            (optional but recommended - set CellSize, e.g. 44x44)
    └── TileTemplate  (ImageButton)   Visible = false  (the script clones this)
```

On each `RoundStart`, `InputHandler`:
1. clears all tiles except `TileTemplate`,
2. ensures a `UIGridLayout` exists (yours is kept),
3. clones `TileTemplate` once per letter — the server sends a **12-letter bank**
   (the word's letters + 8 random fillers), so 12 tiles appear (`Tile1..12`),
4. sets each tile's `Image` to that letter's image (`ReplicatedStorage.LetterImages`),
5. wires click handling. Clicking a tile plays a **flying-letter animation**: a
   copy of the tile tweens from the bank into the answer slot, then the slot updates.

If you don't create a `TileTemplate`, the script builds plain `ImageButton` tiles
programmatically instead. With 12 tiles, make your `UIGridLayout` wide enough
(e.g. 4 columns × 3 rows, or a single row of 12).

## AnswerBox (centered letter stack)

`AnswerBox` is a **Frame** containing one `ImageLabel` slot per letter, arranged
by a **centered** `UIListLayout` (`HorizontalAlignment = Center`). That way the
whole typed word stays centered in the box. Empty slots show the underscore
image (`LetterImages.underscore`); filled slots show the letter image. As you
type, the newest letter fills the next slot left-to-right — like a centered
word stack. The script builds the slots itself; leave `AnswerBox` empty in
Studio (only set its background/position).

## LetterImages module (in ReplicatedStorage)

`InputHandler` reads `ReplicatedStorage.LetterImages` for the A-Z letter images
and the underscore image. Open that ModuleScript and replace the placeholder
`rbxassetid://...` values with **your** asset IDs.

## HoverFX (pop effect)

- `ReplicatedStorage.HoverFX` — reusable module. `HoverFX.applyTo(guiObject, {scale, duration})`
  animates a child `UIScale` so it pops/grows on hover without reflowing the layout.
- `StarterPlayerScripts.HoverController` — LocalScript that applies the pop
  effect to the 4 clue images (`ImageGrid.Clue1..Clue4`), every scrambled-bank
  tile (including ones created at runtime), and the PlayVsBot button. Tune the
  `scale`/`duration` there.

## UIFX (open/close + intro animations)

- `ReplicatedStorage.UIFX` — reusable module: `popIn`, `popOut`, `fadeIn`,
  `staggerIn`. Used by `InputHandler` to animate:
  - the scrambled-bank **round-start intro** (tiles cascade in),
  - the TopBar / PuzzleArea opening and closing,
  - the PlayVsBot button shrinking out when clicked,
  - the flying-letter landing.
  All use a child `UIScale`, so nothing reflows.

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
