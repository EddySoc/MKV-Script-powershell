# GUI versie van git_quickpush - kies een git-projectmap en push naar GitHub
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ─── Hulpfunctie: tekst toevoegen aan logvenster ───────────────────────────
function Write-Log {
    param([string]$Text, [System.Drawing.Color]$Color = [System.Drawing.Color]::White)
    $txtLog.SelectionStart = $txtLog.TextLength
    $txtLog.SelectionLength = 0
    $txtLog.SelectionColor = $Color
    $txtLog.AppendText("$Text`r`n")
    $txtLog.ScrollToCaret()
    $form.Refresh()
}

# ─── Hulpfunctie: git-commando uitvoeren en output loggen ──────────────────
function Invoke-Git {
    param([string[]]$GitArgs)
    $result = & git @GitArgs 2>&1
    foreach ($line in $result) {
        $color = if ($line -match '^error:|^fatal:') { [System.Drawing.Color]::Salmon }
                 elseif ($line -match '^hint:') { [System.Drawing.Color]::SkyBlue }
                 else { [System.Drawing.Color]::LightGray }
        Write-Log "  $line" $color
    }
    return $LASTEXITCODE
}

# ─── Formulier bouwen ──────────────────────────────────────────────────────
$form = New-Object System.Windows.Forms.Form
$form.Text = "Git Quick Push"
$form.Size = New-Object System.Drawing.Size(660, 560)
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$form.ForeColor = [System.Drawing.Color]::White
$form.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

# Label: Projectmap
$lblFolder = New-Object System.Windows.Forms.Label
$lblFolder.Text = "Git-projectmap:"
$lblFolder.Location = New-Object System.Drawing.Point(15, 15)
$lblFolder.Size = New-Object System.Drawing.Size(120, 22)
$form.Controls.Add($lblFolder)

# Tekstveld: pad naar map
$txtFolder = New-Object System.Windows.Forms.TextBox
$txtFolder.Location = New-Object System.Drawing.Point(140, 13)
$txtFolder.Size = New-Object System.Drawing.Size(390, 24)
$txtFolder.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 48)
$txtFolder.ForeColor = [System.Drawing.Color]::White
$txtFolder.BorderStyle = "FixedSingle"
$form.Controls.Add($txtFolder)

# Knop: map kiezen
$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = "Bladeren..."
$btnBrowse.Location = New-Object System.Drawing.Point(545, 11)
$btnBrowse.Size = New-Object System.Drawing.Size(90, 28)
$btnBrowse.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
$btnBrowse.FlatStyle = "Flat"
$btnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Kies de hoofdmap van je git-project"
    $dlg.RootFolder = [System.Environment+SpecialFolder]::MyComputer
    $dlg.SelectedPath = "C:\"
    if ($dlg.ShowDialog() -eq "OK") {
        $txtFolder.Text = $dlg.SelectedPath
    }
})
$form.Controls.Add($btnBrowse)

# Label: Commit message
$lblMsg = New-Object System.Windows.Forms.Label
$lblMsg.Text = "Commit message:"
$lblMsg.Location = New-Object System.Drawing.Point(15, 55)
$lblMsg.Size = New-Object System.Drawing.Size(120, 22)
$form.Controls.Add($lblMsg)

# Tekstveld: commit message
$txtMsg = New-Object System.Windows.Forms.TextBox
$txtMsg.Location = New-Object System.Drawing.Point(140, 53)
$txtMsg.Size = New-Object System.Drawing.Size(495, 24)
$txtMsg.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 48)
$txtMsg.ForeColor = [System.Drawing.Color]::White
$txtMsg.BorderStyle = "FixedSingle"
$form.Controls.Add($txtMsg)

# Checkbox: force push
$chkForce = New-Object System.Windows.Forms.CheckBox
$chkForce.Text = "Force push (--force) — gebruik alleen als jij de enige ontwikkelaar bent"
$chkForce.Location = New-Object System.Drawing.Point(15, 90)
$chkForce.Size = New-Object System.Drawing.Size(620, 22)
$chkForce.ForeColor = [System.Drawing.Color]::Orange
$form.Controls.Add($chkForce)

# Knop: Push uitvoeren
$btnPush = New-Object System.Windows.Forms.Button
$btnPush.Text = "Commit && Push naar GitHub"
$btnPush.Location = New-Object System.Drawing.Point(15, 122)
$btnPush.Size = New-Object System.Drawing.Size(620, 34)
$btnPush.BackColor = [System.Drawing.Color]::FromArgb(0, 122, 204)
$btnPush.ForeColor = [System.Drawing.Color]::White
$btnPush.FlatStyle = "Flat"
$btnPush.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($btnPush)

# Logvenster
$txtLog = New-Object System.Windows.Forms.RichTextBox
$txtLog.Location = New-Object System.Drawing.Point(15, 168)
$txtLog.Size = New-Object System.Drawing.Size(620, 320)
$txtLog.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 20)
$txtLog.ForeColor = [System.Drawing.Color]::LightGray
$txtLog.ReadOnly = $true
$txtLog.BorderStyle = "FixedSingle"
$txtLog.Font = New-Object System.Drawing.Font("Consolas", 9)
$txtLog.ScrollBars = "Vertical"
$form.Controls.Add($txtLog)

# Knop: log wissen
$btnClear = New-Object System.Windows.Forms.Button
$btnClear.Text = "Log wissen"
$btnClear.Location = New-Object System.Drawing.Point(15, 498)
$btnClear.Size = New-Object System.Drawing.Size(100, 26)
$btnClear.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
$btnClear.FlatStyle = "Flat"
$btnClear.Add_Click({ $txtLog.Clear() })
$form.Controls.Add($btnClear)

# Knop: sluiten
$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "Sluiten"
$btnClose.Location = New-Object System.Drawing.Point(535, 498)
$btnClose.Size = New-Object System.Drawing.Size(100, 26)
$btnClose.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
$btnClose.FlatStyle = "Flat"
$btnClose.Add_Click({ $form.Close() })
$form.Controls.Add($btnClose)

# Vul automatisch de huidige map in als die een git-repo is
$currentDir = Get-Location
if (Test-Path (Join-Path $currentDir ".git")) {
    $txtFolder.Text = $currentDir.Path
}

# ─── Push-logica ───────────────────────────────────────────────────────────
$btnPush.Add_Click({
    $txtLog.Clear()
    $projectPath = $txtFolder.Text.Trim()
    $commitMsg   = $txtMsg.Text.Trim()
    $forcePush   = $chkForce.Checked

    # Validaties
    if ([string]::IsNullOrWhiteSpace($projectPath)) {
        Write-Log "Fout: kies eerst een projectmap." ([System.Drawing.Color]::Salmon)
        return
    }
    if (-not (Test-Path (Join-Path $projectPath ".git"))) {
        Write-Log "Fout: '$projectPath' is geen git-repository." ([System.Drawing.Color]::Salmon)
        return
    }
    if ([string]::IsNullOrWhiteSpace($commitMsg)) {
        Write-Log "Fout: vul een commit message in." ([System.Drawing.Color]::Salmon)
        return
    }

    # Navigeer naar projectmap
    Push-Location $projectPath
    try {
        # VS Code Save All
        $codeCmd = Get-Command code -ErrorAction SilentlyContinue
        if ($codeCmd) {
            Write-Log "VS Code Save All triggeren..." ([System.Drawing.Color]::Cyan)
            & $codeCmd.Source --reuse-window --command workbench.action.files.saveAll 2>$null
            Start-Sleep -Milliseconds 800
        }

        # Git status
        Write-Log "`nHuidige git status:" ([System.Drawing.Color]::Cyan)
        Invoke-Git -GitArgs @("status", "--short") | Out-Null

        # Alles toevoegen
        Write-Log "`nBestanden toevoegen..." ([System.Drawing.Color]::Cyan)
        Invoke-Git -GitArgs @("add", "-A") | Out-Null

        # Controleer of er iets te committen is
        $staged = & git diff --cached --name-only 2>&1
        if (-not $staged) {
            Write-Log "`nGeen wijzigingen om te committen. Klaar." ([System.Drawing.Color]::Yellow)
            return
        }

        Write-Log "`nTe committen bestanden:" ([System.Drawing.Color]::Cyan)
        Invoke-Git -GitArgs @("diff", "--cached", "--name-status") | Out-Null

        # Commit
        Write-Log "`nCommitten..." ([System.Drawing.Color]::Cyan)
        $exitCode = Invoke-Git -GitArgs @("commit", "-m", $commitMsg)
        if ($exitCode -ne 0) {
            Write-Log "`nCommit mislukt." ([System.Drawing.Color]::Salmon)
            return
        }

        # Push
        Write-Log "`nPushen naar GitHub..." ([System.Drawing.Color]::Cyan)
        if ($forcePush) {
            $exitCode = Invoke-Git -GitArgs @("push", "--force")
        } else {
            $exitCode = Invoke-Git -GitArgs @("push")
        }

        if ($exitCode -ne 0) {
            Write-Log "`nPush mislukt! Probeer 'Force push' aan te vinken als jij de enige ontwikkelaar bent." ([System.Drawing.Color]::Salmon)
        } else {
            Write-Log "`nKlaar! Je wijzigingen staan nu op GitHub." ([System.Drawing.Color]::LightGreen)
            $txtMsg.Clear()
        }
    } finally {
        Pop-Location
    }
})

# ─── Formulier tonen ───────────────────────────────────────────────────────
[void]$form.ShowDialog()
