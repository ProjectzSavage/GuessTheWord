# GuessTheWord

A fast-paced, 1v1 word guessing game in Roblox. Two players take turns picking letters and guessing words, with chairs, rewards, daily quests, gamepasses, and special offers.

---

## 🛠️ Summary of Features & Fixes

### 1. Daily Quests (`GameUI.DailyQuestsF`)
- **Fix for Error**: `[Quest] DailyQuestsF not found in PlayerGui. - Client - QuestController:42`
- **Active Quests Available**: Fixed `QuestService.server.luau` payload generator and `QuestController.client.luau` row rendering so active quests immediately show upon joining before the 7h timer resets.
- Connects quest rows, live cycle countdown timer, and claim actions via `QuestClaim`.

### 2. Money Formatting & Gain Animations
- **Money Formatting**: Added `NumberFormat` module in `ReplicatedStorage` to format cash with commas (`$1,250`) and compact notation (`$15.2k`, `$1M`).
- **Animated Money Gain** (in `StatsPanel.client.luau`):
  - **Smooth Number Counter (Lerp)**: Cash label counts up smoothly over 0.4s when cash increases.
  - **Punch / Bounce Pop**: `UIScale` scales up to 1.28x with spring/elastic easing and bounces back to 1.0x.
  - **Color Glow**: Text color pulses with a bright gold / green glow (`Color3.fromRGB(255, 230, 80)`).
  - **Floating Gain Indicator**: Spawns a floating `+$Amount` popup above the cash label that floats upwards and fades out.

### 3. Playtime Rewards in Hours (>= 60 Minutes)
- In both `RewardsService.server.luau` and `RewardsController.client.luau`:
  - Requirements of 60+ minutes display in hours (e.g. `60m` $\rightarrow$ `"1 hr"`, `90m` $\rightarrow$ `"1 hr 30 min"`, `300m` $\rightarrow$ `"5 hrs"`, `1440m` $\rightarrow$ `"24 hrs"`).
  - The playtime category subtitle (`"You played for ..."`) dynamically formats durations $\ge$ 60 minutes into `"Played for X hr Y min Z sec"`.

### 4. StatsPanel Up/Down Motion on GUI Open/Close
- When any GUI window opens (Rewards, Shop, Inventory), `StatsPanel` smoothly tweens **UP** (out of the way / off-screen).
- When all GUI windows are closed, `StatsPanel` smoothly tweens **BACK DOWN** to its original base position.

### 5. Increased Camera FOV & Background Blur
- **Camera FOV**: Smoothly increases `workspace.CurrentCamera.FieldOfView` to `82` when opening any GUI, and restores it to `70` when closed.
- **Lighting Blur**: Uses a `BlurEffect` in `Lighting` (`GuiWindowBlur`) that tweens size to `18` when any GUI is open and fades back to `0` when closed.

### 6. Mutual Exclusivity for All 3 Windows (Shop, Rewards, Inventory)
- Only 1 window is visible at any given moment across `ShopF`, `RewardsF`, and `ChairInvPanel`.
- Opening a window immediately hides/closes the previous window so frames never overlap on top or behind each other.

### 7. Fixed Rewards Toggler Button
- Added the missing `RewardsAPI.close` implementation in `RewardsController.client.luau`.
- Clicking `Buttons.Features.Rewards` when Rewards is closed opens it; clicking it again when Rewards is open closes it cleanly.

### 8. Friend Online Popup (`FriendOnlinePopupController.client.luau`)
- Positioned compactly directly **UNDER the StatsPanel** in top-left.
- Includes friend avatar thumbnail with online status indicator, `+$50 CASH` reward text, **INVITE** button (`SocialService:PromptGameInvite`), and auto-closing countdown bar.

### 9. Offers UI & Gamepass Cycler (`OffersController.client.luau`)
- **`CycleGpBtn`**: Automatically cycles through all gamepasses (VIP, 2x Streak, 2x Cash, 2x Wins) every 3.8s with smooth text/icon fade and scale pulse. Clicking prompts the gamepass purchase.
- **`StarterPackBtn`**: Opens the `StarterPopup` displaying the 3 reward cards (`+1 Reveal Letter`, `Random Chair`, `+$500 CASH`) and prompts the Starter Pack purchase upon clicking `BuyBtn`.

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
        ├── FriendOnlinePopupController.client.luau
        ├── HoverController.client.luau
        ├── InputHandler.client.luau
        ├── InventoryController.client.luau
        ├── OffersController.client.luau
        ├── Preloader.client.luau
        ├── QuestController.client.luau
        ├── RerollController.client.luau
        ├── RewardsController.client.luau
        ├── ShopController.client.luau
        └── StatsPanel.client.luau
```
