# ==============================================================================
# 28 Bases Later — Clean Local DEV Mod
# ==============================================================================
# Removes the 28BasesLaterDev folder from Zomboid\mods whenever you want
# a completely pristine game environment.
# ==============================================================================

$ZomboidMods = Join-Path $env:USERPROFILE "Zomboid\mods"
$Target = Join-Path $ZomboidMods "28BasesLaterDev"

if (Test-Path $Target) {
    Remove-Item -Path $Target -Recurse -Force
    Write-Host ">>> [SUCCESS] Removed 28BasesLaterDev from $ZomboidMods." -ForegroundColor Green
} else {
    Write-Host ">>> Zomboid mods directory is already clean." -ForegroundColor Yellow
}
