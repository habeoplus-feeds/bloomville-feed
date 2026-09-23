<#
  Zet de bestaande Habeo+ EDU-DEX feed om naar het Bloomville / LearningVille
  XML-formaat (courseFeed1.0.xsd, specificatie v1.13).

  Gebruik:
    .\edudex-naar-bloomville.ps1 -Output bloomville-feed.xml
    .\edudex-naar-bloomville.ps1 -Output voorbeeld.xml -OnlyIds 1695
    .\edudex-naar-bloomville.ps1 -CacheDir C:\temp\edudex   (lokale kopie van program-XML's: e<id>.xml)

  Dit is een referentie-implementatie / prototype. De definitieve feed hoort
  door de website zelf gegenereerd te worden (net als de EDU-DEX feed), met
  dezelfde mapping. Zie de gap-analyse voor velden die nog ontbreken.
#>
param(
  [string]$DirectoryUrl = 'https://habeoplus.nl/edudex/habeoplus/programs',
  [string]$Output = 'bloomville-feed.xml',
  [string]$CacheDir = '',
  [string[]]$OnlyIds = @(),
  [string]$XsdPath = '',
  # Sla het uitlezen van de opleidingspagina's (doelgroep, werkvorm, ...) over
  [switch]$SkipWebPages,
  # Veiligheidsgrens: bij minder cursussen (bijv. EDU-DEX storing) wordt de bestaande feed niet overschreven
  [int]$MinCourses = 1,
  # Optioneel tekstbestand met datum, aantallen en waarschuwingen van deze run
  [string]$ReportPath = '',
  # Tijdelijke standaardtijden zolang de EDU-DEX feed geen lesdagen/-tijden bevat
  [string]$DefaultStartTime = '09:00:00',
  [string]$DefaultEndTime = '17:00:00'
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'
$utf8 = New-Object Text.UTF8Encoding($false)
$wc = New-Object Net.WebClient
$wc.Encoding = $utf8

function Get-Xml([string]$url, [string]$id) {
  if ($CacheDir -and $id -and (Test-Path (Join-Path $CacheDir "e$id.xml"))) {
    return [xml][IO.File]::ReadAllText((Join-Path $CacheDir "e$id.xml"), $utf8)
  }
  return [xml]$wc.DownloadString($url)
}

function Format-Amount($value) {
  # Bloomville: decimaal-komma, 2 decimalen, geen duizendtalscheiding
  return ([decimal]$value).ToString('0.00', [Globalization.CultureInfo]::InvariantCulture).Replace('.', ',')
}

function Get-Bytes([string]$s) { return $utf8.GetByteCount($s) }

# Bloomville accepteert alleen: p ol ul li hr br b strong i em a(href)
function ConvertTo-SanitizedHtml([string]$html, [int]$maxBytes) {
  if (-not $html) { return '' }
  $h = $html -replace '&nbsp;', ' ' -replace "\r|\n", ' '
  # Koppen worden vetgedrukte alinea's
  $h = [regex]::Replace($h, '<h[1-6][^>]*>', '<p><strong>', 'IgnoreCase')
  $h = [regex]::Replace($h, '</h[1-6]\s*>', '</strong></p>', 'IgnoreCase')
  $h = [regex]::Replace($h, '<(/?)blockquote[^>]*>', '<$1p>', 'IgnoreCase')
  # Links: alleen href behouden
  $h = [regex]::Replace($h, '<a\s[^>]*?href\s*=\s*"([^"]*)"[^>]*>', '<a href="$1">', 'IgnoreCase')
  # Overige toegestane tags zonder attributen
  $h = [regex]::Replace($h, '<(/?)(p|ol|ul|li|b|strong|i|em)(\s[^>]*)?>', '<$1$2>', 'IgnoreCase')
  $h = [regex]::Replace($h, '<(br|hr)[^>]*>', '<$1 />', 'IgnoreCase')
  # Alle niet-toegestane tags verwijderen (inhoud blijft staan)
  $h = [regex]::Replace($h, '<(?!/?(p|ol|ul|li|b|strong|i|em|a)[\s>]|(br|hr) />)[^>]*>', '', 'IgnoreCase')
  $h = [regex]::Replace($h, '<p>\s*</p>', '')
  $h = [regex]::Replace($h, '\s{2,}', ' ').Trim()
  if ($maxBytes -gt 0 -and (Get-Bytes $h) -gt $maxBytes) {
    # Afkappen op het laatste afgesloten blok dat nog past
    $blocks = [regex]::Matches($h, '<(p|ul|ol)>.*?</\1>')
    $sb = ''
    foreach ($b in $blocks) {
      if ((Get-Bytes ($sb + $b.Value)) -gt $maxBytes) { break }
      $sb += $b.Value
    }
    $h = $sb
  }
  return $h
}

# Leest de sectie "Praktische informatie" van de opleidingspagina en splitst die op de kopjes.
# Resultaat: hashtable met kopje (kleine letters) -> HTML van de tekst onder dat kopje.
function Get-PageSections([string]$url, [string]$id) {
  $cache = if ($CacheDir) { Join-Path $CacheDir "p$id.html" } else { '' }
  if ($cache -and (Test-Path $cache)) { $html = [IO.File]::ReadAllText($cache, $utf8) }
  else {
    $html = $wc.DownloadString($url)
    if ($cache) { [IO.File]::WriteAllText($cache, $html, $utf8) }
  }
  $result = @{}
  $start = $html.IndexOf('<section id="praktische-informatie"')
  if ($start -lt 0) { return $result }
  $end = $html.IndexOf('</section>', $start)
  $section = $html.Substring($start, $end - $start)
  $text = (([regex]::Matches($section, '(?s)<div class="text-long">(.*?)</div>')) | ForEach-Object { $_.Groups[1].Value }) -join ''
  # Kopjes staan afhankelijk van de pagina als h2, h3 of h4
  $parts = [regex]::Split($text, '(?s)<h[2-4][^>]*>(.*?)</h[2-4]>')
  # $parts = [tekst voor 1e kopje, kopje1, tekst1, kopje2, tekst2, ...]
  for ($i = 1; $i -lt $parts.Count - 1; $i += 2) {
    $key = ($parts[$i] -replace '<[^>]+>', '' -replace '&nbsp;', ' ').Trim().ToLower()
    $result[$key] = $parts[$i + 1]
  }
  return $result
}

function Write-HtmlElement($writer, [string]$name, [string]$html) {
  if (-not $html) { return }
  $writer.WriteStartElement($name)
  $writer.WriteCData($html)
  $writer.WriteEndElement()
}

function Get-Level([string]$edudexLevel) {
  switch -regex ($edudexLevel) {
    '^mbo'   { return 'MBO' }
    'hbo'    { return 'HBO' }      # hbo, post-hbo
    'master' { return 'Master' }
    default  { return '' }
  }
}

function Get-CertValue([string]$degree) {
  switch ($degree) {
    'diploma'                       { return 'Diploma' }
    'certificate'                   { return 'Certificaat' }
    'certificate of participation'  { return 'Bewijs van deelname' }
    'testimonial'                   { return 'Getuigschrift' }
    default                         { return '' }
  }
}

function Get-Delivery([string]$mode, [bool]$hasRuns) {
  switch ($mode) {
    'blended learning'    { if ($hasRuns) { return 'blended' } else { return 'instructor-led date-tbd' } }
    'individual guidance' { return 'individual' }
    default               { if ($hasRuns) { return 'instructor-led' } else { return 'instructor-led date-tbd' } }
  }
}

# Duur in hele uren. EDU-DEX levert geen contacturen; we gebruiken de studiebelasting.
function Get-DurationHours($p) {
  $load = $p.programCurriculum.studyLoad | Select-Object -First 1
  if (-not $load) { return 0 }
  $hours = [decimal]$load.'#text'
  if (-not $hours) { $hours = [decimal]"$load" }
  if ($load.period -eq 'week') {
    $dur = $p.programClassification.programDuration
    if ($dur.unit -eq 'week') { $hours = $hours * [decimal]$dur.'#text' }
  }
  return [int][math]::Round($hours)
}

# EDU-DEX costType -> Bloomville prijscomponent
function Get-PriceNode($cost) {
  $amount = [decimal]$cost.amount
  $vat = [decimal]$cost.amountVAT
  $rate = if ($amount -gt 0) { $vat / $amount } else { 0 }
  switch ($cost.costType) {
    'tuition fee'        { return 'PriceBase' }
    'registration fee'   { return 'PriceEnrol' }
    'examination fee'    { return 'PriceExam' }
    'dinner'             { if ($rate -gt 0.15) { 'PriceArrFacHigh' } else { 'PriceArrFacLow' } }
    'lunch'              { if ($rate -gt 0.15) { 'PriceArrFacHigh' } else { 'PriceArrFacLow' } }
    'accommodation'      { return 'PriceOvernight' }
    default              { if ($rate -gt 0.15) { 'PriceMaterialHigh' } else { 'PriceMaterialLow' } }  # study material, books, ...
  }
}

$priceNodes = 'PriceBase','PriceEnrol','PriceMaterialLow','PriceMaterialHigh','PriceArrFacLow','PriceArrFacHigh','PriceExam','PriceOvernight'

# --- Ophalen ---------------------------------------------------------------
$directory = [xml]$wc.DownloadString($DirectoryUrl)
$resources = $directory.edudexDirectory.programResource
if ($OnlyIds.Count) { $resources = $resources | Where-Object { $OnlyIds -contains $_.programId } }

$settings = New-Object Xml.XmlWriterSettings
$settings.Indent = $true
$settings.IndentChars = '    '
$settings.Encoding = $utf8
$Output = [IO.Path]::GetFullPath($Output)
$tempOutput = "$Output.tmp"
$w = [Xml.XmlWriter]::Create($tempOutput, $settings)
$w.WriteStartDocument()
$w.WriteStartElement('CourseTemplates')

$warnings = New-Object Collections.Generic.List[string]
$count = 0

foreach ($res in $resources) {
  try { $x = Get-Xml $res.resourceUrl $res.programId }
  catch { $warnings.Add("$($res.programId) : EDU-DEX programma niet op te halen ($($_.Exception.Message))"); continue }
  $p = $x.program
  if ($p.inPublication -ne '1') { continue }

  $id    = $p.programClassification.programId
  $d     = $p.programDescriptions
  $runs  = @($p.programSchedule.programRun | Where-Object { $_ })
  $mode  = @($p.programCurriculum.instructionMode)[0]
  $delivery = Get-Delivery $mode ($runs.Count -gt 0)
  # Alle uitvoeringen volledig online -> Virtual Class
  if ($runs.Count -and $delivery -eq 'instructor-led' -and -not ($runs | Where-Object { $_.fullyOnline -ne 'true' })) { $delivery = 'Virtual Class' }
  $isSession = $delivery -in 'blended','instructor-led','examination','seminar','Virtual Class'

  $w.WriteStartElement('CourseTemplate')
  $w.WriteElementString('Code', $id)
  $w.WriteElementString('Title', ($d.programName.'#cdata-section').Trim())
  $w.WriteElementString('Language', 'nl')
  $w.WriteElementString('Duration', [string](Get-DurationHours $p))

  $w.WriteStartElement('Description')
  $w.WriteCData(($d.programSummaryText.'#cdata-section').Trim())
  $w.WriteEndElement()

  $long = ConvertTo-SanitizedHtml $d.programDescriptionHtml.'#cdata-section' 3980
  if (-not $long) { $long = ($d.programDescriptionText.'#cdata-section').Trim() }
  $w.WriteStartElement('DescriptionLong')
  $w.WriteCData($long)
  $w.WriteEndElement()

  # Losse tekstvelden uit "Praktische informatie" op de opleidingspagina
  $page = @{}
  if (-not $SkipWebPages) {
    try { $page = Get-PageSections $d.webLink.'#cdata-section' $id }
    catch { $warnings.Add("$id : opleidingspagina niet op te halen ($($_.Exception.Message))") }
    $missing = @('doelgroep', 'werkvorm', 'tijdsinvestering', 'diploma') | Where-Object { -not $page[$_] }
    if ($missing) { $warnings.Add("$id : kopje(s) niet gevonden op de website: $($missing -join ', ')") }
  }
  Write-HtmlElement $w 'TargetAudience' (ConvertTo-SanitizedHtml $page['doelgroep'] 3980)
  $format = ''
  foreach ($k in 'werkvorm', 'tijdsinvestering') {
    if ($page[$k]) { $format += '<p><strong>' + $k.Substring(0,1).ToUpper() + $k.Substring(1) + '</strong></p>' + $page[$k] }
  }
  Write-HtmlElement $w 'CourseFormat' (ConvertTo-SanitizedHtml $format 3980)
  $cert = ConvertTo-SanitizedHtml $page['diploma'] 3980
  if (-not $cert) { $cert = Get-CertValue $p.programClassification.degree }
  Write-HtmlElement $w 'CertValue' $cert
  $w.WriteElementString('Level', (Get-Level $p.programClassification.programLevel))

  # Prijzen: uit genericProgramRun, anders uit de eerste uitvoering
  $costs = @($p.programSchedule.genericProgramRun.cost | Where-Object { $_ -and $_.isRequiredCost -eq 'true' })
  if (-not $costs.Count -and $runs.Count) { $costs = @($runs[0].cost | Where-Object { $_ -and $_.isRequiredCost -eq 'true' }) }
  $grouped = @{}
  foreach ($c in $costs) {
    $node = Get-PriceNode $c
    if (-not $grouped[$node]) { $grouped[$node] = @{} }
    $from = "$($c.amountValidFrom)"
    if ($grouped[$node].ContainsKey($from)) {
      # Meerdere kosten van hetzelfde type en dezelfde periode worden opgeteld
      $grouped[$node][$from].amount += [decimal]$c.amount
      $grouped[$node][$from].vat += [decimal]$c.amountVAT
    } else {
      $grouped[$node][$from] = @{ amount = [decimal]$c.amount; vat = [decimal]$c.amountVAT }
    }
  }
  if (-not $grouped['PriceBase']) { $warnings.Add("$id : geen collegegeld (tuition fee) - wordt door Bloomville niet gepubliceerd") }
  foreach ($node in $priceNodes) {
    if (-not $grouped[$node]) { continue }
    $w.WriteStartElement($node)
    foreach ($from in ($grouped[$node].Keys | Sort-Object)) {
      $v = $grouped[$node][$from]
      $w.WriteStartElement('Price')
      if ($from) { $w.WriteAttributeString('from', $from) }
      $w.WriteElementString('Base', (Format-Amount $v.amount))
      $w.WriteElementString('Vat', (Format-Amount $v.vat))
      # BTW-vrije levering: bij vrijgesteld onderwijs (0 BTW) is de prijs gelijk aan Base
      if ($v.vat -eq 0) { $w.WriteElementString('VatFree', (Format-Amount $v.amount)) }
      $w.WriteEndElement()
    }
    $w.WriteEndElement()
  }

  if ($runs.Count) {
    # Sommige uitvoeringen hebben een afwijkende prijs t.o.v. de generieke prijs; Bloomville kent alleen prijs per cursus
    $baseAmounts = $runs | ForEach-Object { $_.cost | Where-Object { $_.costType -eq 'tuition fee' } | ForEach-Object { $_.amount } } | Sort-Object -Unique
    if (@($baseAmounts).Count -gt 1) { $warnings.Add("$id : uitvoeringen hebben verschillende prijzen ($($baseAmounts -join ' / ')) - Bloomville ondersteunt 1 prijs per cursus") }
  }

  $w.WriteElementString('Delivery', $delivery)
  $w.WriteStartElement('Classes')
  if ($isSession) {
    foreach ($r in $runs) {
      $w.WriteStartElement('Class')
      $w.WriteElementString('Code', $r.id)
      $loc = $r.location
      $city = "$($loc.city)".Trim()
      $country = "$($loc.country.'#cdata-section')$($loc.country.'#text')".Trim()
      if ($country -and $country -ne 'nl') { $city = "$($country.ToUpper()) $city" }
      if ($r.fullyOnline -eq 'true') { $city = 'Virtual' }
      if (-not $city) { $warnings.Add("$id / $($r.id) : uitvoering zonder plaatsnaam") }
      $w.WriteElementString('Location', $city)
      $w.WriteStartElement('Sessions')
      # TIJDELIJK: EDU-DEX bevat geen losse lesdagen; 1 sessie van start- t/m einddatum
      $w.WriteStartElement('Session')
      $w.WriteAttributeString('StartDateTime', "$($r.startDate.'#text')T$DefaultStartTime")
      $w.WriteAttributeString('EndDateTime', "$($r.endDate.'#text')T$DefaultEndTime")
      $w.WriteEndElement()
      $w.WriteEndElement()
      $w.WriteEndElement()
    }
  } else {
    $w.WriteStartElement('Class')
    $w.WriteElementString('Code', "$id-OPEN")
    $w.WriteStartElement('Location'); $w.WriteString(''); $w.WriteFullEndElement()
    $w.WriteEndElement()
  }
  $w.WriteEndElement()   # Classes
  $w.WriteEndElement()   # CourseTemplate
  $count++
}

$w.WriteEndElement()
$w.WriteEndDocument()
$w.Close()

# --- Validatie tegen de Bloomville XSD --------------------------------------
$errors = New-Object Collections.Generic.List[string]
if ($XsdPath) {
  $rs = New-Object Xml.XmlReaderSettings
  $rs.ValidationType = 'Schema'
  [void]$rs.Schemas.Add($null, $XsdPath)
  $rs.add_ValidationEventHandler({ param($s, $e) $errors.Add("regel $($e.Exception.LineNumber): $($e.Message)") })
  $rd = [Xml.XmlReader]::Create($tempOutput, $rs)
  while ($rd.Read()) { }
  $rd.Close()
  Write-Host "XSD-validatie: $($errors.Count) fout(en)"
  $errors | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" }
}
$warnings | ForEach-Object { Write-Warning $_ }

$ok = ($count -ge $MinCourses) -and ($errors.Count -eq 0)
if ($ok) {
  Move-Item -Force $tempOutput $Output
  Write-Host "$count cursussen geschreven naar $Output"
} else {
  Remove-Item $tempOutput -ErrorAction SilentlyContinue
  Write-Host "NIET bijgewerkt: $count cursussen (minimum $MinCourses), $($errors.Count) XSD-fout(en). Bestaande feed blijft staan."
}

if ($ReportPath) {
  $status = if ($ok) { 'BIJGEWERKT' } else { 'NIET BIJGEWERKT' }
  $lines = @(
    "Bloomville feed - run $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
    "Status: $status",
    "Cursussen: $count",
    "XSD-fouten: $($errors.Count)",
    "",
    "Waarschuwingen ($($warnings.Count)):"
  ) + ($warnings | ForEach-Object { "- $_" }) + ($errors | ForEach-Object { "- XSD $_" })
  [IO.File]::WriteAllLines([IO.Path]::GetFullPath($ReportPath), $lines, $utf8)
}

if (-not $ok) { exit 1 }
