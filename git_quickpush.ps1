# Universeel PowerShell-script om snel en veilig te committen en pushen naar GitHub
# Gebruik: voer uit in de hoofdmap van je git-project met: .\git_quickpush.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Fail {
    param([string]$Message)
    Write-Host "Fout: $Message" -ForegroundColor Red
    exit 1
}

# Controleer of we in een git-repository zitten
if (-not (Test-Path .git)) {
    Fail "Dit is geen git-repository. Voer het script uit in de hoofdmap van je project."
}

# Verplicht Save All in VS Code
$codeCmd = Get-Command code -ErrorAction SilentlyContinue
if ($codeCmd) {
    Write-Host "VS Code Save All triggeren..." -ForegroundColor Cyan
    try {
        & $codeCmd.Source --reuse-window --command workbench.action.files.saveAll | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Fail "Save All is mislukt (code exit $LASTEXITCODE). Stop voor veiligheid."
        }
    } catch {
        Fail "Save All kon niet automatisch gestart worden. Sla eerst manueel op en probeer opnieuw."
    }
} else {
    Fail "'code' CLI niet gevonden. Installeer 'code' in PATH of sla eerst alles manueel op."
}

# Overzicht van huidige wijzigingen op schijf
Write-Host "\nHuidige git status:" -ForegroundColor Cyan
git status --short

# Vraag commit message
$commitMsg = Read-Host "\nGeef een korte omschrijving voor de wijziging (commit message)"
if ([string]::IsNullOrWhiteSpace($commitMsg)) {
    Fail "Commit message mag niet leeg zijn."
}

# Voeg alle wijzigingen toe
Write-Host "\nBestanden toevoegen..." -ForegroundColor Cyan
git add -A

# Stop als er toch niets te committen is
$stagedDiff = git diff --cached --name-only
if (-not $stagedDiff) {
    Write-Host "Geen wijzigingen om te committen. Klaar." -ForegroundColor Yellow
    exit 0
}

Write-Host "\nTe committen bestanden:" -ForegroundColor Cyan
git diff --cached --name-status

# Extra veiligheidsstop voor commit
$confirm = Read-Host "\nDoorgaan met commit en push? (Y/N)"
if ($confirm -notmatch '^(?i)y(?:es)?$') {
    Write-Host "Actie geannuleerd. Er is niets gecommit of gepusht." -ForegroundColor Yellow
    exit 0
}

# Commit
Write-Host "\nCommitten..." -ForegroundColor Cyan
git commit -m "$commitMsg"

# Push naar huidige branch/upstream
Write-Host "\nPushen naar GitHub..." -ForegroundColor Cyan
git push

Write-Host "\nKlaar! Je wijzigingen staan nu op GitHub." -ForegroundColor Green
