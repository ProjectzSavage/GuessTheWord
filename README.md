# GuessTheWord

A fast-paced, 1v1 word guessing game in Roblox. Two players take turns picking letters and guessing words, with chairs, rewards, daily quests, exclusive gamepass chairs, notifications, dynamic effects, and special offers.

---

## 🛠️ Summary of Features & Fixes

### 1. Centered Friend Online Popup (`FriendOnlinePopupController.client.luau`)
- **Centered on Screen**: Centered cleanly at `(0.5, 0.5)` on screen.
- **Upward Animation**:
  - **Intro**: Starts below center and slides **UP** into view with smooth spring easing.
  - **Outro / Dismiss**: Slides **UP** towards the top of the screen (`-0.3`) as it fades out.
- Features friend avatar thumbnail with online indicator dot, `+$50 CASH` reward, **INVITE** button (`SocialService:PromptGameInvite`), and auto-closing countdown bar.

### 2. Auto-Closing Mutual Exclusivity (Shop, Rewards, Inventory)
- Opening **Shop** automatically closes the **Rewards** and **Inventory** windows, exactly matching the toggle button behavior.
- Opening any panel always closes all other active panels so frames never overlap on top or behind each other.

### 3. Continuous Icon Sway & Upward Animated UIGradient (`DynamicEffectsController.client.luau`)
- **Continuous Left/Right Rotation (Sway)**:
  - Add tag `"RotateWiggle"`, `"IconSway"`, `"Sway"`, or attribute `RotateWiggle = true` to any GuiObject.
  - Automatically rotates the icon left and right continuously in a smooth sine wave.
  - Optional attributes: `SwaySpeed` (default 2.5), `SwayAngle` (default 8 degrees).
- **Animated UIGradient (Slow Upward Motion)**:
  - Add tag `"AnimatedGradient"`, `"GradientScroll"`, or attribute `AnimatedGradient = true` to any `UIGradient` (e.g. on VIP, PinkVortex, buttons).
  - Slowly animates `UIGradient.Offset` moving upward continuously, bringing gradient cards to life with a shimmering effect.
  - Optional attributes: `GradientSpeed` (default 0.6), `GradientDirection` (`"Up"`, `"Down"`, `"Diagonal"`).

### 4. Daily Quests (`GameUI.DailyQuestsF`)
- **Display Limit**: Strictly displays **2 active quests** per cycle.
- **State-Memory Collapse**:
  - When opening a GUI (Shop, Rewards, Inventory), `DailyQuestsF` slides closed to avoid screen clutter.
  - When closing the GUI, `DailyQuestsF` restores/slides back open **only if** the user had not manually collapsed it. If already collapsed by the user, it stays collapsed.

### 5. Robux Exclusive Gamepass Chairs
- Added support for the 3 exclusive Robux chairs: **`HackerChair`**, **`SpacialMist`**, and **`PinkVortex`**.
- Integrated into `ChairsConfig.luau`, `ChairService.server.luau`, and `ShopController.client.luau`.
- In `ShopF.Scroll`, duplicate the `VIPPack` frame and rename the duplicated frames to `HackerChair`, `SpacialMist`, and `PinkVortex` to prompt their purchases.

### 6. Floating & Rotating 3D Display Chairs
- In `InventoryController.client.luau`:
  - 3D chairs in ViewportFrame previews float **UP and DOWN** with a gentle sine-wave bobbing effect while **ROTATING**.
  - In-world display chairs (`Workspace.DisplayChairs`) also smoothly float and spin.

### 7. Event Notification System (`NotificationController.client.luau`)
- Drives `NotificationGUI.Holder` using `NotificationTemplate`.
- Plays animated popups for game events:
  - Purchases (successful buys, insufficient funds)
  - Match victories (`GameOver`)
  - Cash gains (`CashAwarded`)
  - Quest completions & claim rewards
  - Global `_G.Notify({ title = "...", message = "...", kind = "success", duration = 3.5 })`

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
    │       └── HeartHUDManager.luau
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
