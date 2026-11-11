# Development Journal

This directory tracks the ongoing development history, architecture decisions, bug post-mortems, and test results for **28 Bases Later**.

## Session Entries

- [**2026-11-10 - Session 1: Reconnect Persistence, Admin Configuration & Build 42 Sync**](2026-11-10_development_journal.md)
  - Resolved reconnect naming persistence bug (`PLN-BUG-001`).
  - Added Admin Claim Cap & Sandbox Options with `0 = Unlimited` support (`PLN-ADM-001`).
  - Two-way title, respawn, and lifecycle synchronization with Vanilla and "Better Safehouse" (`PLN-SYNC-002`).
  - Investigated and resolved Build 42.22.1 Java engine quirks (`SafeHouse.getSafeHouse(Double, Double)` crash, `SandboxVars.lua` identifier crash, and `.json` translation format).
