# 28 Bases Later - Development Journal

**Session Date:** November 10, 2026  
**Target Environment:** Project Zomboid Build 42.22.1 Multiplayer (Co-op / Dedicated Server)  
**Authors:** User (Mod Architect / Project Owner) & Antigravity (AI Pair Programmer)  
**Session Goal:** Resolve core multiplayer persistence, safehouse lifecycle synchronization, Build 42 options menus, and third-party mod interoperability ("Better Safehouse").

---

## 1. Executive Summary

During this session, we investigated, debugged, implemented, and verified three core architectural epics for **28 Bases Later (v1.1.0)**:
1. **Multiplayer Reconnect Naming Persistence (`PLN-BUG-001`)**: Eliminated cache poisoning and missing hydration packets that previously caused claimed bases to revert to `"Base #1"` upon reconnecting.
2. **Admin Claim Cap & Sandbox Options (`PLN-ADM-001`)**: Implemented numeric text entry support (`0 = unlimited`, `1 - 100`) via native Build 42 Sandbox Options, server settings, and the in-game pause menu (**Escape -> Options -> Mods**).
3. **Metadata, Title & Lifecycle Synchronization (`PLN-SYNC-002`)**: Achieved bidirectional title and respawn synchronization between 28 Bases Later, Vanilla `ISSafehouseUI`, and "Better Safehouse", while eliminating duplicate safehouse claims and phantom bases.

All planned test cases (`TC-REC-01` through `TC-REC-05`, `TC-ADM-01` through `TC-ADM-06`, and `TC-SYNC-01` through `TC-SYNC-07`) have officially **PASSED** in live multiplayer gameplay on Build 42.22.1.

---

## 2. Key Technical Discoveries & Bug Post-Mortems

During our testing on Build 42.22.1, we encountered several game-engine constraints and syntax peculiarities. Disassembling `projectzomboid.jar` and analyzing the game's Lua runtime yielded the following critical findings:

### 2.1 The Java `SafeHouse.getSafeHouse(Double, Double)` Signature Crash
- **Symptom:** Safehouse claiming failed overhead with `"Claiming base..."`, but the safehouse was never created, an error alert appeared, and all menus broke.
- **Root Cause:** Decompiling `zombie.iso.areas.SafeHouse` revealed that `SafeHouse.getSafeHouse` only accepts an `IsoGridSquare` object (`(Lzombie/iso/IsoGridSquare;)Lzombie/iso/areas/SafeHouse;`). Invoking `SafeHouse.getSafeHouse(x, y)` in Lua passed two Java `Double` arguments, throwing `java.lang.RuntimeException: No implementation found for function: getSafeHouse(Double, Double)`.
- **Solution:** Replaced all coordinate lookups in `MultiSafehouse_ServerHandler.lua` and `MultiSafehouse_UI.lua` with safe iterations over `SafeHouse.getSafehouseList()`, matching `sh:getX() == x and sh:getY() == y`.

### 2.2 The `28BasesLater` Lua Identifier Crash in `SandboxVars.lua`
- **Symptom:** Host server failed during startup with `Server has stopped during launch (NormalTermination)`.
- **Root Cause:** In Project Zomboid, applying sandbox options serializes settings to `<Server>_SandboxVars.lua`. Because our option prefix started with a digit (`option 28BasesLater.MaxBasesPerPlayer`), the Java engine wrote `28BasesLater = { ... }`. In Lua syntax, identifiers cannot begin with numbers. The Kahlua parser threw `se.krka.kahlua.vm.KahluaException: malformed number near '28BasesLater'` and terminated the server.
- **Solution:** Renamed the option prefix to `MultiSafehouse.*` (e.g. `option MultiSafehouse.MaxBasesPerPlayer`), producing valid Lua (`MultiSafehouse = { ... }`). Corrected existing server files and updated `MultiSafehouse_Core.lua` to resolve settings cleanly.

### 2.3 Build 42 Translation Format Shift (`.txt` -> `.json`) & Double Prefixing
- **Symptom:** Admin sandbox options displayed raw untranslated keys with double prefixes: `Sandbox_Sandbox_28BasesLater_MaxBasesPerPlayer`.
- **Root Cause:**
  1. Build 42 deprecated legacy `Sandbox_EN.txt` files in favor of `Translate/EN/Sandbox.json`.
  2. Project Zomboid automatically prepends `Sandbox_` to whatever string is passed to `translation = `. Supplying `translation = Sandbox_...` resulted in double prefixing.
- **Solution:** Created `media/lua/shared/Translate/EN/Sandbox.json` and assigned clean identifiers without `Sandbox_` in `sandbox-options.txt`.

### 2.4 Pause Menu `PZAPI.ModOptions` Hook Timing
- **Symptom:** Escape -> Options did not show the "Mods" tab.
- **Root Cause:** In Build 42, `MainOptions.lua` evaluates `#PZAPI.ModOptions.Data ~= 0` when constructing options tabs during game boot. Calling `PZAPI.ModOptions:create(...)` inside `Events.OnGameStart` ran after `MainOptions` had already finished its creation.
- **Solution:** Executed `PZAPI.ModOptions:create(...)` immediately at file load time so that `#PZAPI.ModOptions.Data` is populated prior to `MainOptions:create()`.

### 2.5 Safehouse Lifecycle & "Better Safehouse" Coexistence
- **Symptom:** Better Safehouse UI options weren't visible, and releasing a safehouse in vanilla caused phantom safehouses and duplicate claims in 28BL.
- **Root Cause:**
  1. Better Safehouse attaches a side panel (`BSBetterSafehousePanel`) to the vanilla `ISSafehouseUI` window, which requires a valid native safehouse. Because claiming crashed earlier, no safehouse existed.
  2. 28BL previously had no listener for `Events.OnSafehousesChanged`. When a base was released in vanilla, 28BL was never notified.
- **Solution:** Subscribed to `Events.OnSafehousesChanged` in `MultiSafehouse_UI.lua`, instantly updating the UI on claims, releases, and renames. Added deduplication guards to `claimBase` to prevent duplicate rows.

---

## 3. Inventory of Changes Made

| File Path | Nature of Change | Summary of Modifications |
| :--- | :--- | :--- |
| `media/sandbox-options.txt` | Configuration | Added `VERSION = 1,`, renamed prefix to `MultiSafehouse.*`, and cleaned `translation` keys. |
| `media/lua/shared/Translate/EN/Sandbox.json` | Localization | Added Build 42 JSON translations for page and option labels/tooltips. |
| `media/lua/shared/Translate/EN/Sandbox_EN.txt` | Localization | Updated legacy fallback translation file. |
| `media/lua/shared/MultiSafehouse_Core.lua` | Shared Logic | Added dynamic resolver `getMaxBasesPerPlayer()` supporting `0 = unlimited` and `getMaxDimension()`. |
| `media/lua/server/MultiSafehouse_ServerHandler.lua` | Server Logic | Fixed `findNativeSafehouse` list iteration, `claimBase` title setting and deduplication, `setRespawn` via native `sh:setRespawnInSafehouse(boolean, username)`, `setAdminConfig`, and `reconcilePlayerSafehouses`. |
| `media/lua/client/MultiSafehouse_UI.lua` | Client UI | Fixed list refresh without `(Double, Double)` crash, hooked `Events.OnSafehousesChanged`, added instant discovery of vanilla/Better Safehouse claims, and synced respawns natively. |
| `media/lua/client/MultiSafehouse_ClaimOverride.lua` | Client Context | Fixed safehouse naming on client network replication and protected context menu. |
| `media/lua/client/MultiSafehouse_ModOptions.lua` | Client Options | Top-level execution of `PZAPI.ModOptions`, admin permission check, and cleaned title label to `Max Bases Per Player`. |
| `media/lua/client/MultiSafehouse_Respawn.lua` | Client Respawn | Separated 30-tick reconnect hydration from 120-tick character respawn teleportation. |
| `plans/plan_fix_reconnect_naming_bug.md` | Documentation | Marked as `COMPLETED & VERIFIED (SOLVED)`, recorded test matrix results. |
| `plans/plan_admin_config_claim_cap.md` | Documentation | Marked as `COMPLETED & VERIFIED (SOLVED)`, recorded test matrix results. |
| `plans/plan_safehouse_title_sync.md` | Documentation | Marked as `COMPLETED & VERIFIED (SOLVED)`, recorded test matrix results. |

---

## 4. Verification & Testing Matrix

| Test ID | Area | Scenario | Outcome |
| :--- | :--- | :--- | :--- |
| **TC-REC-01** | Reconnect | Standard reconnect retains custom safehouse names | **PASSED** |
| **TC-REC-02** | Reconnect | Reconnecting without opening UI first preserves cache | **PASSED** |
| **TC-REC-03** | Reconnect | Server restart preserves custom names in ModData | **PASSED** |
| **TC-REC-04** | Respawn | Fresh character respawn teleports to designated base | **PASSED** |
| **TC-REC-05** | Reconnect | High-latency hydration guard prevents cache poisoning | **PASSED** |
| **TC-ADM-01** | Admin Config | Setting cap to `0` enables unlimited safehouse claims | **PASSED** |
| **TC-ADM-02** | Admin Config | Setting custom cap (e.g. `3`) strictly blocks claims at ceiling | **PASSED** |
| **TC-ADM-03** | Admin Config | Text input bounds clamping (`-5` -> `0`, `500` -> `100`, `"abc"` -> `28`) | **PASSED** |
| **TC-ADM-04** | Admin Config | Non-admin permission lockout for configuration changes | **PASSED** |
| **TC-ADM-05** | Admin Config | Server restart retains custom sandbox cap | **PASSED** |
| **TC-ADM-06** | Admin Config | Escape -> Options -> Mods text field updates server | **PASSED** |
| **TC-SYNC-01** | Metadata Sync | Safehouse claiming succeeds without error alerts | **PASSED** |
| **TC-SYNC-02** | Interop | Better Safehouse side panel displays properly on safehouse menu | **PASSED** |
| **TC-SYNC-03** | Lifecycle | Releasing in vanilla removes from 28BL; reclaim creates no duplicate | **PASSED** |
| **TC-SYNC-04** | Metadata Sync | Vanilla rename (`[Change]`) immediately reflects in 28BL | **PASSED** |
| **TC-SYNC-05** | Metadata Sync | 28BL rename immediately reflects in Vanilla and Better Safehouse | **PASSED** |
| **TC-SYNC-06** | Metadata Sync | Respawn checkbox in vanilla mirrors 28BL respawn designation | **PASSED** |
| **TC-SYNC-07** | Lifecycle | Reconnect retains both titles and respawn statuses accurately | **PASSED** |

---

## 5. Ongoing Status & Staging Directories

- **Source Code Repository:** `C:\Users\logic\Git\28-bases-later\`
- **Active Test Staging Folder (Loaded by Project Zomboid):**  
  `C:\Users\logic\Zomboid\Workshop\28BasesLater\Contents\mods\28BasesLater\`
- **Server Save Config:**  
  `C:\Users\logic\Zomboid\Server\28baseslater_SandboxVars.lua`

All active plan documents in `plans/` are marked as **COMPLETED & VERIFIED (SOLVED)**. Future work will track from this baseline.
