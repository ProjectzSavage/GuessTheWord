# GuessTheWord - Luau Scripts & Controllers

This repository contains the complete, updated Luau codebase for **GuessTheWord** in Roblox.

---

## 🛠️ Summary of Changes & Fixes

### 1. Daily Quests (`GameUI.DailyQuestsF`)
- **Fix for Error**: `[Quest] DailyQuestsF not found in PlayerGui. - Client - QuestController:42`
- `QuestController.luau` now safely resolves `PlayerGui.GameUI` (with fallbacks to `GameGui` and automatic search across all ScreenGuis).
- Handles quest rows (`Quest1`..`Quest6` or dynamic row frames), live cycle countdown timers, and claim actions via `DailyQuestClaim`.

### 2. Money Formatting & Gain Animations
- **Money Formatting**: Added `NumberFormat` module in `ReplicatedStorage` to format cash with commas (`$1,250`) and compact notation (`$15.2k`, `$1M`).
- **Animated Money Gain**:
  - **Smooth Number Counter (Lerp)**: Cash label counts up smoothly over 0.4s when cash increases.
  - **Punch / Bounce Pop**: `UIScale` scales up to 1.28x with spring/elastic easing and bounces back to 1.0x.
  - **Color Flash**: Text color pulses with a bright gold / green glow.
  - **Floating Gain Indicator**: Spawns a floating `+$Amount` popup above the cash label that floats upwards and fades out.

### 3. Playtime Rewards in Hours (>= 60 Minutes)
- In both `RewardsService.luau` and `RewardsController.luau`:
  - Requirements of 60+ minutes display in hours (e.g. `60m` $\rightarrow$ `"1 hr"`, `90m` $\rightarrow$ `"1 hr 30 min"`, `120m` $\rightarrow$ `"2 hrs"`).
  - The playtime category subtitle (`"You played for ..."`) dynamically formats durations $\ge$ 60 minutes into `"X hr Y min Z sec"`.

### 4. StatsPanel Up/Down Motion on GUI Open/Close
- When any GUI window opens, `StatsPanel` smoothly tweens **UP** (out of the way / off-screen).
- When all GUI windows are closed, `StatsPanel` smoothly tweens **BACK DOWN** to its original base position.

### 5. Increased Camera FOV & Background Blur
- **Camera FOV**: Smoothly increases `workspace.CurrentCamera.FieldOfView` to `82` when opening any GUI, and restores it to `70` when closed.
- **Lighting Blur**: Uses a `BlurEffect` in `Lighting` (`GuiWindowBlur`) that tweens size to `18` when any GUI is open and fades back to `0` when closed.

### 6. Mutual Exclusivity for All 3 Windows (Shop, Rewards, Quests)
- Only 1 window is visible at any given moment across `ShopF`, `RewardsF`, and `DailyQuestsF` / `ChairInvPanel`.
- Opening a window immediately hides/closes the previous window so frames never overlap on top or behind each other.

### 7. Fixed Rewards Toggler Button
- Clicking `OpenRewardsBtn` when Rewards is closed opens it; clicking it again when Rewards is open closes it cleanly.
- Reverts FOV, blur, and `StatsPanel` seamlessly upon closing.

---

## 📂 Project Structure

```
├── default.project.json              # Rojo configuration
├── README.md
└── src/
    ├── ReplicatedStorage/
    │   └── NumberFormat.luau         # Number, currency, and time formatting module
    ├── ServerScriptService/
    │   ├── DailyQuestService.luau    # Server quest tracking & rollover logic
    │   ├── RewardsService.luau       # Server rewards & playtime persistence
    │   └── RobuxShopService.luau     # Server Robux shop & receipt processing
    └── StarterPlayerScripts/
        ├── QuestController.luau      # Client Daily Quests controller
        ├── RewardsBadgeController.luau# Ready badge indicators
        ├── RewardsController.luau    # Client Rewards controller
        ├── ShopController.luau       # Client Shop controller
        ├── StatsHudController.luau   # StatsPanel, money formatting & gain animations
        ├── StatsShopQuickAccess.luau # Quick shop buttons on StatsPanel
        └── UIWindowsController.luau  # Central window manager (Blur, FOV, StatsPanel)
```

---

## 🚀 Roblox Studio Placement

| File Path in Repo | Location in Roblox Studio | Script Type |
| :--- | :--- | :--- |
| `src/ReplicatedStorage/NumberFormat.luau` | `ReplicatedStorage > NumberFormat` | `ModuleScript` |
| `src/ServerScriptService/DailyQuestService.luau` | `ServerScriptService > DailyQuestService` | `Script` |
| `src/ServerScriptService/RewardsService.luau` | `ServerScriptService > RewardsService` | `Script` |
| `src/ServerScriptService/RobuxShopService.luau` | `ServerScriptService > RobuxShopService` | `Script` |
| `src/StarterPlayerScripts/UIWindowsController.luau` | `StarterPlayer > StarterPlayerScripts > UIWindowsController` | `LocalScript` |
| `src/StarterPlayerScripts/QuestController.luau` | `StarterPlayer > StarterPlayerScripts > QuestController` | `LocalScript` |
| `src/StarterPlayerScripts/RewardsController.luau` | `StarterPlayer > StarterPlayerScripts > RewardsController` | `LocalScript` |
| `src/StarterPlayerScripts/ShopController.luau` | `StarterPlayer > StarterPlayerScripts > ShopController` | `LocalScript` |
| `src/StarterPlayerScripts/StatsHudController.luau` | `StarterPlayer > StarterPlayerScripts > StatsHudController` | `LocalScript` |
| `src/StarterPlayerScripts/RewardsBadgeController.luau` | `StarterPlayer > StarterPlayerScripts > RewardsBadgeController` | `LocalScript` |
| `src/StarterPlayerScripts/StatsShopQuickAccess.luau` | `StarterPlayer > StarterPlayerScripts > StatsShopQuickAccess` | `LocalScript` |
