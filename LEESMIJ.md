# Bloomville feed Habeo+

Zet de EDU-DEX feed van habeoplus.nl, aangevuld met de doelgroep, werkvorm, tijdsinvestering en het diploma
van de opleidingspagina's, elke week om naar het Bloomville / LearningVille XML-formaat.
De feed komt op een vaste URL te staan die Bloomville zelf ophaalt.

## Wat zit erin

| Bestand | Functie |
|---|---|
| `edudex-naar-bloomville.ps1` | het omzetscript |
| `courseFeed.xsd` | het Bloomville-schema; elke run wordt de feed hiertegen gecontroleerd |
| `.github/workflows/update-feed.yml` | wekelijkse automatische run (maandagochtend) plus een knop voor handmatig bijwerken |
| `docs/bloomville-feed.xml` | de feed; dit is het bestand dat Bloomville ophaalt |
| `docs/rapport.txt` | datum, status en waarschuwingen van de laatste run |

## Eenmalig inrichten (ongeveer 15 minuten, alles in de browser)

1. Maak een (gratis) account aan op github.com, of gebruik een bestaand account van Habeo+.
2. Klik op **New repository**, noem het bijvoorbeeld `bloomville-feed` en kies **Public**.
   GitHub Pages is alleen gratis bij een publieke repository. Er staat alleen informatie in die ook al openbaar op de website staat.
3. Kies **uploading an existing file** en sleep de inhoud van deze map erin (`edudex-naar-bloomville.ps1`,
   `courseFeed.xsd`, `LEESMIJ.md` en de map `docs`). Klik op **Commit changes**.
4. Het workflowbestand moet apart, omdat mappen die met een punt beginnen vaak niet mee-uploaden:
   **Add file > Create new file**, typ als naam `.github/workflows/update-feed.yml`,
   plak de inhoud van dat bestand en klik op **Commit changes**.
5. Ga naar **Settings > Pages**. Kies bij *Source* **Deploy from a branch**, branch `main`, map `/docs`, en klik op **Save**.
6. Na een minuut staat de feed op
   `https://<account>.github.io/bloomville-feed/bloomville-feed.xml`
   Geef deze URL door aan Bloomville (opla@bloomville.nl), eerst voor de testomgeving en daarna voor productie.

## Gebruik

- **Automatisch:** elke maandagochtend draait de taak en wordt de feed bijgewerkt.
- **Handmatig:** ga naar **Actions > Bloomville feed bijwerken > Run workflow**. Na 5 à 10 minuten staat de nieuwe versie online.
- **Controle:** `docs/rapport.txt` laat zien wanneer de laatste run was en welke opleidingen een waarschuwing hebben
  (bijvoorbeeld een ontbrekend kopje op de website).
- **Beveiliging:** als de EDU-DEX feed minder dan 250 opleidingen oplevert (bijvoorbeeld door een storing), of als de feed
  niet aan het Bloomville-schema voldoet, blijft de vorige feed staan. De run wordt dan rood en GitHub stuurt je een e-mail.

## Afspraken voor de website-redactie

Het script zoekt in de sectie *Praktische informatie* naar deze kopjes (h2, h3 of h4, hoofdletters maken niet uit):

| Kopje | Bloomville-veld |
|---|---|
| Doelgroep | TargetAudience |
| Werkvorm + Tijdsinvestering | CourseFormat |
| Diploma | CertValue |

Een ander kopje (zoals "Tijdinvestering" of "Deze opleiding is geschikt voor jou") wordt niet herkend.
Dat veld blijft dan leeg en de opleiding komt als waarschuwing in het rapport.
