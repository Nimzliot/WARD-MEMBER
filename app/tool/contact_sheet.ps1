# Tiles screenshots from tool/shots into contact sheets (4 per sheet) for quick review.
#   powershell -File tool/contact_sheet.ps1
Add-Type -AssemblyName System.Drawing
$dir = Join-Path $PSScriptRoot 'shots'
$out = Join-Path $PSScriptRoot 'sheets'
New-Item -ItemType Directory -Force $out | Out-Null
$files = @(Get-ChildItem $dir -Filter *.png | Sort-Object Name)
$w = 420; $perSheet = 4
for ($s = 0; $s -lt $files.Count; $s += $perSheet) {
  $batch = @($files[$s..([Math]::Min($s + $perSheet, $files.Count) - 1)])
  $first = [System.Drawing.Image]::FromFile($batch[0].FullName)
  $h = [int]($first.Height * $w / $first.Width); $first.Dispose()
  $sheet = New-Object System.Drawing.Bitmap -ArgumentList ([int]($w * $batch.Count + 10 * ($batch.Count - 1))), ([int]($h + 30))
  $g = [System.Drawing.Graphics]::FromImage($sheet)
  $g.Clear([System.Drawing.Color]::FromArgb(40, 40, 40))
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $font = New-Object System.Drawing.Font -ArgumentList 'Segoe UI', 11
  for ($i = 0; $i -lt $batch.Count; $i++) {
    $img = [System.Drawing.Image]::FromFile($batch[$i].FullName)
    $x = $i * ($w + 10)
    $g.DrawImage($img, $x, 30, $w, $h)
    $g.DrawString($batch[$i].BaseName, $font, [System.Drawing.Brushes]::White, [single]($x + 4), [single]5)
    $img.Dispose()
  }
  $name = Join-Path $out ('sheet_{0:D2}.png' -f [int]($s / $perSheet + 1))
  $sheet.Save($name, [System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $sheet.Dispose()
  Write-Output $name
}
