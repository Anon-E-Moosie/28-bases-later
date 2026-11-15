# 28 Bases Later — Claim & Manage Multiple Safehouses
**Build 42 Multiplayer**

Why settle for one safehouse when Knox County is full of empty houses?

[**28 Bases Later**](https://steamcommunity.com/sharedfiles/filedetails/?id=3835106467) lets you claim and manage multiple safehouses at the same time in multiplayer. Claim a main base, a gas station outpost, or a backup cabin in the woods—just claim them like normal.

---

## Features

- **Multiple Safehouses:** Claim more than one base (default limit is 28, configurable by admins or set to 0 for unlimited).
- **28BL Management Dashboard:** Press **F7** to open the 28BL menu and view all your claimed and shared bases in a clean, resizable two-column window.
- **Safehouse Co-Ownership & Memberships:** Invite friends to your safehouses with a dedicated Online Player Picker dialog (`+ Add Member`). View whitelisted members, evict members (`- Kick Member`), or voluntarily depart shared safehouses (`Leave Base`).
- **Quota Isolation:** Joining friends' safehouses as a member never consumes your personal claim limit.
- **Rename Bases:** Give your bases custom names with 100% reconnect and server restart persistence.
- **Choose Your Respawn:** Pick which base you want to respawn at after you die. Co-owners and members can independently choose their own respawn locations.
- **Release Bases:** Easily release any base you don't need anymore with confirmation prompts.
- **Safehouse Loot Tracking:** Hover over items while looting to see if, how many, and where you have them stored across all your owned and shared bases.
- **Admin & Anti-Griefing Controls:** Server admins can restrict non-residential claims, protect spawn points, limit maximum building dimensions, set days-survived claim requirements, and toggle admin bypass in native Sandbox Options.

---

## How to Use

1. Walk into any unclaimed building.
2. Right-click inside and claim the safehouse like normal.
3. Press **F7** to open the 28BL menu.
4. Select a base from the list to rename it, set/unset it as your personal respawn location, invite members, or release it.

---

## Planned Features

- **"See on Map" Button:** A button in the 28BL menu that opens your map and centers it directly on the selected base.
- **Custom Keybind:** Option to change the menu keybind in settings if you don't want to use F7.
- **Activity Decay & Claim Cooldowns:** Optional automatic release for inactive safehouses and claim velocity rate-limiting for high-population servers.

---

## Compatibility

- Project Zomboid **Build 42+**
- Multiplayer (Dedicated Server & Co-Op) and Single-Player
- Safe to add to existing saves and active servers mid-game
- Synchronized with Build 42 native safehouses and compatible with other safehouse mods (e.g. Better Safehouse)

---

## Known Bugs & Issues

---

## Disclaimer

Made with assistance of Gemini and Claude via Antigravity.
I'm on a journey of self-improvement as I attempt to learn JavaScript for my career, I've decided to expand this into Lua by having a go at Project Zomboid modding.

Once I've ironed out my workflow I will release the code on GitHub so it can be reviewed publically by those that wish to see it without downloading the mod.

My process involves multiple code reviews before changes are made public, several by other AI agents and a final one by a human that is not myself. I am attempting to keep comments and notes on code relevant from a learning perspective as this mod is a result of learning in practice.

While some of the code is AI generated, on a separate branch from Main and as part of my learning process one of my agents will intentionally make mistakes for me to correct, introduce bugs for me to fix or leave lines blank for me to fill in the gaps, it then grades my progress. Any of these intentional mistakes, bugs and gaps introduced to guide my learning are kept out of the Main branch and do not reach production.

That is not to say this mod does not have other bugs, I intend to openly support this mod and as my skills and knowledge progress, less of the code itself will be AI generated and it will remain as a learning tool instead.

---

## Changelog

**v1.1.0**
- **Safehouse Co-Ownership & Member Whitelisting:**
  - Added safehouse member sharing! Safehouse owners can now invite friends and faction members to their bases.
  - Dedicated **Online Player Picker** modal dialog (`+ Add Member`) listing active online players, automatically filtering out invalid targets.
  - Interactive **Whitelisted Members Roster** displaying `[Owner]` (highlighted in gold) and `[Member]` (soft cyan).
  - Owners can evict members with `- Kick Member` (with confirmation dialog and native boundary eviction).
  - Members can voluntarily leave shared safehouses at any time with `Leave Base`.
  - **Quota Isolation:** Belonging to shared safehouses as a member never consumes or penalizes your personal safehouse claim quota (`MaxBasesPerPlayer`).
  - **Independent Respawn Points:** Members can set shared safehouses as their personal respawn without altering the owner's respawn.
  - **Loot Tracking Integration:** Items stored in co-owned safehouses you belong to are automatically indexed in your "At Your Bases" inventory tooltips.
- **Modern Two-Column Dashboard (F7):**
  - Completely redesigned management window (640x420) featuring proportional column resizing, centered item text, and aligned selection highlights.
  - Added optimistic UI reactivity across all action buttons (`Set Respawn`, `Rename`, `Release`, `Kick Member`, `Leave Base`, `+ Add Member`) for instant visual feedback.
  - Fully compliant with Build 42 native engine methods and immune to Java packet anti-cheat drops.

**v1.0.4**
- **Safehouse Claim Restrictions & Anti-Griefing Controls:**
  - Added `Allow Non-Residential Claims` sandbox option to toggle claiming of commercial, industrial, and military buildings.
  - Added `Allow Spawn Point Claims` sandbox option to protect server spawn buildings from being claimed.
  - Added `Days Survived to Claim` sandbox option to require character survival before safehouse claiming.
  - Added `Admins Bypass Claim Restrictions` sandbox option allowing server staff to bypass all claim rules.
  - Relocated all mod settings directly into native, admin-locked Sandbox Options under a dedicated "28 Bases Later" section, removing confusing mod menu clutter.

**v1.0.3**
- Added basic loot tracking for items within your safehouses: hover over any item while out looting to instantly see if you already have it stored at home, how many, and at which safehouse.
- Fixed tooltip translation tokens with native Build 42 UI.json localization.

**V1.0.2**
 - Saved base names now load automatically when joining a server and will no longer revert on rejoin
 - Linked name and respawn changes across all menus, this should improve compatability with other mods using the safehouse events such as Better Safehouse
 - Updated how the mod registers building locations, this should stop duplicate claims and phantom safehouse entries by claiming and unclaiming
 - Added a "Max Bases Per Player" setting to Sandbox Options and the Mod Menu (set to 0 for unlimited), this lets admins easily set safehouse limits
 - Added a "Max Building Dimension" setting to Sandbox Options (default 120, range 10–300); admins can use this to prevent players from claiming massive structures like malls
 - Cleaned up menu text and added hover tips

**V1.0.1**
 - Fixed issue with bases losing their saved names on server rejoin

**v1.0.0**
- Initial release for Build 42.
- Multiple safehouse claiming.
- 28BL base management window (F7).
- Base renaming, selectable respawns, and base releasing.

Workshop ID: 3835106467  
Mod ID: 28baseslater