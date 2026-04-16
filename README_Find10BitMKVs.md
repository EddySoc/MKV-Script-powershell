# Find10BitMKVs.ps1

Dit PowerShell script scant recursief een gekozen map voor MKV-bestanden en identificeert welke 10-bit zijn.

## Gebruik

1. Voer het script uit: `.\Find10BitMKVs.ps1`
2. Klik op "Bladeren..." om een hoofdmap te kiezen.
3. Klik op "Scan Starten" om de scan te beginnen.
4. De resultaten worden getoond in de GUI: lijst van 10-bit MKV bestanden en telling.
5. Het script toont ook voortgang en debug info in de console.

## Vereisten

- PowerShell
- FFmpeg/ffprobe geïnstalleerd en geconfigureerd in `config.ini` (onder [Executables] FFprobeExe)
- Windows Forms (standaard in Windows PowerShell)

## Uitvoer

De GUI toont:
- Lijst van 10-bit MKV bestanden (volledige paden) in een textbox.
- Telling: "10-bit bestanden: x / Totaal gescand: y"

Een tekstbestand `10bits_mkvs.txt` wordt gemaakt met de lijst van bestanden.

## Probleemoplossing

- Zorg ervoor dat `config.ini` correct is geconfigureerd met het pad naar ffprobe.exe.
- Als ffprobe niet gevonden wordt, controleer de console output voor het pad.
- Het script detecteert 10-bit via bits_per_raw_sample of pix_fmt (bevat "p10").
- Console output toont ffprobe resultaten voor debugging.

## Voorbeeld uitvoer

GUI textbox:
```
C:\Videos\Movie1\file1.mkv
C:\Videos\Series\Season1\episode1.mkv
```

Label: 10-bit bestanden: 5 / Totaal gescand: 20