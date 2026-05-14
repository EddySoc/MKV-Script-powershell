# Universeel PowerShell-script om snel te committen en pushen naar GitHub vanuit elke git-projectmap
# Gebruik: plaats dit script in een map met een .git directory en voer uit met: .\git_quickpush.ps1

# Controleer of we in een git-repository zitten
if (-not (Test-Path .git)) {
    Write-Host "Fout: Dit is geen git-repository. Voer het script uit in de hoofdmap van je project." -ForegroundColor Red
    exit 1
}

# Vraag om commit message
$commitMsg = Read-Host "Geef een korte omschrijving voor de wijziging (commit message)"

# Voeg alle wijzigingen toe
Write-Host "Bestanden toevoegen..."
git add .

# Commit met opgegeven boodschap
Write-Host "Committen..."
git commit -m "$commitMsg"

# Push naar GitHub
Write-Host "Pushen naar GitHub..."
git push

Write-Host "Klaar! Je wijzigingen staan nu op GitHub."
