# PowerShell script om snel te committen en pushen naar GitHub met omschrijving via prompt

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
