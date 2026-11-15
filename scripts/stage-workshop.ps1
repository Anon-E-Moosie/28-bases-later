# ==============================================================================
# 28 Bases Later — Stage for Steam Workshop Upload
# ==============================================================================
# Stages clean, production-ready files into C:\Users\<User>\Zomboid\Workshop\28BasesLater.
# Run this ONLY when you are ready to publish an official Steam Workshop update!
# ==============================================================================

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Source = Join-Path $RepoRoot "Contents\mods\28BasesLater\common"
$WorkshopBase = Join-Path $env:USERPROFILE "Zomboid\Workshop\28BasesLater"
$Target = Join-Path $WorkshopBase "Contents\mods\28BasesLater\common"

# Ensure we are on main branch
try {
    $currentBranch = (git branch --show-current).Trim()
    if ($currentBranch -and $currentBranch -ne "main") {
        Write-Warning "Caution: You are staging from branch '$currentBranch' instead of 'main'!"
        $confirm = Read-Host "Proceed with workshop staging anyway? (y/N)"
        if ($confirm -ne "y" -and $confirm -ne "Y") {
            Write-Host "Staging aborted." -ForegroundColor Red
            exit
        }
    }
} catch {
    # Git command unavailable or not a repo
}

Write-Host ">>> Staging production release files to Workshop folder..." -ForegroundColor Cyan

if (-not (Test-Path $Target)) {
    New-Item -ItemType Directory -Path $Target -Force | Out-Null
}

robocopy $Source $Target /MIR /XD ".git" ".vscode" /NFL /NDL /NJH /NJS

# Copy workshop.txt and preview.png to Workshop root
$WorkshopTxt = Join-Path $RepoRoot "workshop.txt"
if (Test-Path $WorkshopTxt) {
    Copy-Item $WorkshopTxt (Join-Path $WorkshopBase "workshop.txt") -Force
}

$PreviewPng = Join-Path $RepoRoot "preview.png"
if (Test-Path $PreviewPng) {
    Copy-Item $PreviewPng (Join-Path $WorkshopBase "preview.png") -Force
}

Write-Host ">>> [SUCCESS] Workshop staging ready at: $WorkshopBase" -ForegroundColor Green
Write-Host ">>> Launch Project Zomboid -> Workshop -> Upload 28 Bases Later to publish to Steam!" -ForegroundColor Green
