# ==============================================================================
# 28 Bases Later — Deploy to Local DEV Mod
# ==============================================================================
# Deploys your Git files to C:\Users\<User>\Zomboid\mods\28BasesLaterDev with
# an isolated mod ID (28baseslater_dev).
# This guarantees you NEVER fail Lua checksums (DoLuaChecksum) when joining
# external multiplayer servers running the official Steam Workshop mod.
# ==============================================================================

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Source = Join-Path $RepoRoot "Contents\mods\28BasesLater\common"
$ZomboidMods = Join-Path $env:USERPROFILE "Zomboid\mods"
$Target = Join-Path $ZomboidMods "28BasesLaterDev"

Write-Host ">>> Deploying 28 Bases Later to Local DEV Mod..." -ForegroundColor Cyan

if (-not (Test-Path $Target)) {
    New-Item -ItemType Directory -Path $Target -Force | Out-Null
}

# Mirror files from Git directory to Zomboid mods
robocopy $Source $Target /MIR /XD ".git" ".vscode" /NFL /NDL /NJH /NJS

# Override mod.info with the isolated development ID
$DevModInfo = @"
name=28 Bases Later [DEV]
id=28baseslater_dev
description=[LOCAL DEV BUILD] Claim and manage multiple safehouses simultaneously.
poster=preview.png
author=Anon. E. Moose
"@
Set-Content -Path (Join-Path $Target "mod.info") -Value $DevModInfo -Force

Write-Host ">>> [SUCCESS] Deployed to: $Target" -ForegroundColor Green
Write-Host ">>> Mod ID: '28baseslater_dev' is active for local testing." -ForegroundColor Yellow
Write-Host ">>> You can safely join external servers; your game will load clean Workshop files for them." -ForegroundColor Green
