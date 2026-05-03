# Release Notes

## Subtitle pipeline improvements

Deze update maakt de subtitle-workflow betrouwbaarder, duidelijker en veiliger in gebruik.

### Nieuw en verbeterd
- fallback toegevoegd via OpenSubtitles.com wanneer een subtitle niet via de standaard route wordt gevonden
- betere afhandeling van verlopen login-token en rate limiting
- onveilige sync-resultaten worden nu geweigerd zodat een subtitle niet halverwege de film start
- de gekozen subtitle wordt bewaard en teruggekopieerd naar de bronmap, zodat deze mee kan naar Done
- duidelijkere pipeline samenvatting met stapnamen en nette tellingen voor succes, fout en skip
- opruiming van dubbele en verouderde step-bestanden
- nettere afsluiting van achterblijvende STT-processen

### Resultaat
- betere kans op juiste Nederlandse subtitles
- meer controle over wat uiteindelijk is geembed
- minder verwarring in logs en pipeline-output
- schonere projectstructuur

### Veiligheid
Lokale configuratie en authenticatiebestanden blijven buiten Git.
