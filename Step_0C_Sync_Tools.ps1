function Sync-WithFFSubSync {
        Write-Host "[DEBUG] ffsubsync: Video=$VideoPath, Sub=$($SubtitleInfo.Path)" -ForegroundColor Cyan
    param(
        [string]$VideoPath,
        [hashtable]$SubtitleInfo,
        [string]$VideoDir
    )
    $ffsubsyncExe = if ($Global:FFSubSyncExe -and (Test-Path $Global:FFSubSyncExe)) { $Global:FFSubSyncExe } else { Join-Path $PSScriptRoot 'ffsubsync.exe' }
    if (-not (Test-Path $ffsubsyncExe)) {
        Show-Format "SKIP SYNC" "$($SubtitleInfo.Name)" "ffsubsync.exe niet gevonden" -NameColor "Yellow"
        return $false
    }
    $syncOutput = Join-Path $VideoDir "$([System.IO.Path]::GetFileNameWithoutExtension($SubtitleInfo.Name)).ffsubsync.synced.srt"
    $args = @(
        $VideoPath,
        "-i", $SubtitleInfo.Path,
        "-o", $syncOutput
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ffsubsyncExe
    $psi.Arguments = $args -join ' '
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $null = $proc.Start()
    
    # Read output character by character to handle tqdm progress bars
    $outputBuffer = ""
    $lastProgressLine = ""
    while (-not $proc.HasExited) {
        # Read available output
        $char = $proc.StandardOutput.Read()
        if ($char -gt 0) {
            $char = [char]$char
            $outputBuffer += $char
            
            # If we hit a newline, process the line
            if ($char -eq "`n") {
                $line = $outputBuffer.TrimEnd("`r", "`n")
                $outputBuffer = ""
                
                # Handle tqdm progress bars (lines starting with percentage)
                if ($line -match '^\d+%\|') {
                    # Overwrite previous progress line
                    if ($lastProgressLine) {
                        Write-Host ("`r" + (" " * $lastProgressLine.Length) + "`r") -NoNewline
                    }
                    Write-Host $line -NoNewline
                    $lastProgressLine = $line
                } else {
                    # Clear progress line if it exists
                    if ($lastProgressLine) {
                        Write-Host ("`r" + (" " * $lastProgressLine.Length) + "`r") -NoNewline
                        $lastProgressLine = ""
                    }
                    Write-Host $line
                }
            }
        }
        
        # Also check stderr
        $errorChar = $proc.StandardError.Read()
        if ($errorChar -gt 0) {
            $errorChar = [char]$errorChar
            Write-Host $errorChar -ForegroundColor Red -NoNewline
        }
        
        Start-Sleep -Milliseconds 10  # Very fast polling
    }
    
    # Clear final progress line
    if ($lastProgressLine) {
        Write-Host ("`r" + (" " * $lastProgressLine.Length) + "`r") -NoNewline
    }
    
    # Get any remaining output
    $remainingOutput = $proc.StandardOutput.ReadToEnd()
    if ($remainingOutput) { Write-Host $remainingOutput }
    $remainingError = $proc.StandardError.ReadToEnd()
    if ($remainingError) { Write-Host $remainingError -ForegroundColor Red }
    if ($proc.ExitCode -eq 0 -and (Test-Path -LiteralPath $syncOutput)) {
        return $syncOutput
    } else {
        return $null
    }
}

function Sync-WithAlass {
        Write-Host "[DEBUG] alass: Video=$VideoPath, Sub=$($SubtitleInfo.Path)" -ForegroundColor Cyan
    param(
        [string]$VideoPath,
        [hashtable]$SubtitleInfo,
        [string]$VideoDir
    )
    $alassExe = if ($Global:AlassExe -and (Test-Path $Global:AlassExe)) { $Global:AlassExe } else { Join-Path $PSScriptRoot 'alass.exe' }
    if (-not (Test-Path $alassExe)) {
        Show-Format "SKIP SYNC" "$($SubtitleInfo.Name)" "alass.exe niet gevonden" -NameColor "Yellow"
        return $false
    }
    $syncOutput = Join-Path $VideoDir "$([System.IO.Path]::GetFileNameWithoutExtension($SubtitleInfo.Name)).alass.synced.srt"
    $args = @(
        $VideoPath,
        $SubtitleInfo.Path,
        $syncOutput
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $alassExe
    $psi.Arguments = $args -join ' '
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $null = $proc.Start()
    $stdOut = $proc.StandardOutput.ReadToEnd()
    $stdErr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    if ($proc.ExitCode -eq 0 -and (Test-Path -LiteralPath $syncOutput)) {
        return $syncOutput
    } else {
        return $null
    }
}
