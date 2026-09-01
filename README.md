# GuessTheWord

A fast-paced, 1v1 word guessing game in Roblox. Two players take turns picking letters and guessing words, with chairs, rewards, daily quests, exclusive gamepass chairs, notifications, dynamic effects, and special offers.

## 📝 Game Description (paste into your Roblox game page)

```
Welcome to Guess The Word
Can you guess the secret word?

 Look at the clues
 Unscramble the letters
 First to guess it wins the cash!
```

---

## 🛠️ Summary of Features & Fixes

### 1. Friend Online Popup (`FriendOnlinePopupController.client.luau`)
- **Layout**:
  - `AnchorPoint = 0.5, 0.5`
  - `Position = {0.5, 0}, {0.242, 0}`
  - `Size = {0.238, 0}, {0.183, 0}`
  - `AvatarImage.ScaleType = Fit`
- Smooth pop-in and dismiss scale animation at position without upward screen-slide.

### 2. Notifications with Upward Animation (`NotificationController.client.luau`)
- Drives `NotificationInteractionGUI.Frame.Holder` with smooth **UPWARD** intro & dismissal animations.
- Automatically handles game event alerts (victories, cash gains, purchases, quest completions).

### 3. Mutual Exclusivity: Opening Shop Automatically Closes Rewards
- In `ShopController.client.luau`, `RewardsController.client.luau`, and `InventoryController.client.luau`:
  - Opening **Shop** automatically calls `_G.RewardsAPI.close()` and `_G.InventoryAPI.close()`.
  - Guaranteed single-active window behavior across all frames.

### 4. Continuous Icon Sway & Live UIGradient (`DynamicEffectsController.client.luau`)
- **Continuous Left/Right Rotation (Sway)**:
  - Add tag `"RotateWiggle"`, `"IconSway"`, `"Sway"`, or attribute `RotateWiggle = true` to any GuiObject to rotate left and right continuously in a smooth sine wave.
- **Continuous Animated UIGradient (No Snap/Reset)**:
  - Add tag `"AnimatedGradient"`, `"GradientScroll"`, or `"LiveGradient"`, or attribute `AnimatedGradient = true` to any `UIGradient`.
  - Smoothly oscillates the gradient `Offset` back and forth continuously without sudden jumps or resets.

### 5. Daily Quests (Strictly 2 Active Quests + State-Memory)
- **2 Quests Max**: Configured `QuestService.server.luau` and `QuestController.client.luau` to only display 2 active quests.
- **State-Memory**:
  - When opening a GUI, `DailyQuestsF` slides closed.
  - When closing all GUIs, `DailyQuestsF` restores **only if** the user had not manually collapsed it.

### 6. Robux Exclusive Gamepass Chairs
- Added support for the 3 exclusive Robux chairs: **`HackerChair`**, **`SpacialMist`**, and **`PinkVortex`**.
- In `ShopF.Scroll`, duplicate the `VIPPack` frame and rename the duplicated frames to `HackerChair`, `SpacialMist`, and `PinkVortex` to prompt their purchases.

### 7. Floating & Rotating 3D Display Chairs
- In `InventoryController.client.luau`, 3D chair models float **UP and DOWN** with a gentle sine-wave bobbing effect while **ROTATING**.

### 8. Progress Persistence (DataStore)
- `ServerStorage.Modules.ProfileStore` is the single DataStore owner (store
  `GuessTheWordProfile_v1`, one profile per player, written with
  `UpdateAsync`). It persists:
  - **Chairs** — owned + equipped chair (`ChairService`),
  - **Rewards** — claimed rewards, daily state, total Robux spent
    (`RewardsService`),
  - **Quests** — active pair, progress, claims for the 7h cycle
    (`QuestService`),
  - **Hidden Stats** — Streak + Reveal Letter/Word uses (`GameManager`).
- Each system registers a "section getter" so all progress is merged into ONE
  profile write per save (no key fights). Saves happen on important changes,
  on player leave, and every 30s (autosave).
- Cash/Wins live in `leaderstats`, which Roblox auto-persists - the profile
  doesn't duplicate them.
- **Studio:** enable *Game Settings → Security → Enable Studio Access to API
  Services* or DataStores won't work in Studio (the game falls back to
  in-memory with a warning). In a published game it works automatically.

---

## 📂 Project Structure

```
├── default.project.json
├── README.md
├── docs/
│   ├── SETUP.md
│   └── UI_HIERARCHY.md
└── src/
    ├── ReplicatedStorage/
    │   ├── ChairsConfig.luau
    │   ├── HoverFX.luau
    │   ├── LetterImages.luau
    │   ├── NumberFormat.luau
    │   ├── SFX.luau
    │   └── UIFX.luau
    ├── ServerScriptService/
    │   ├── ChairService.server.luau
    │   ├── GameManager.server.luau
    │   ├── Hearts.server.luau
    │   ├── Nametag.server.luau
    │   ├── QuestService.server.luau
    │   ├── RewardsService.server.luau
    │   ├── SetupEvents.server.luau
    │   └── ShopService.server.luau
    ├── ServerStorage/
    │   └── Modules/
    │       ├── Dictionary.luau
    │       ├── HeartHUDManager.luau
    │       └── ProfileStore.luau
    └── StarterPlayerScripts/
        ├── ButtonsController.client.luau
        ├── CameraController.client.luau
        ├── DynamicEffectsController.client.luau
        ├── FriendOnlinePopupController.client.luau
        ├── HoverController.client.luau
        ├── InputHandler.client.luau
        ├── InventoryController.client.luau
        ├── NotificationController.client.luau
        ├── OffersController.client.luau
        ├── Preloader.client.luau
        ├── QuestController.client.luau
        ├── RerollController.client.luau
        ├── RewardsController.client.luau
        ├── ShopController.client.luau
        └── StatsPanel.client.luau
```
