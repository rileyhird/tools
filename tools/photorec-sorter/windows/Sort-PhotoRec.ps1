<#
.SYNOPSIS
  Sort PhotoRec's recup_dir.* output into tidy folders (Windows / PowerShell).
.DESCRIPTION
  Sorts by type (Photos, Documents, Videos, Audio, Archives), keeps only files above a
  size threshold, skips exact duplicates, and files photos by date taken (EXIF) when
  available. By default this only CHECKS and writes nothing; add -Run to really copy.
  Files are COPIED; nothing is deleted unless you also use -Move.
.EXAMPLE
  .\Sort-PhotoRec.ps1 -Source D:\recup -Dest E:\sorted
  .\Sort-PhotoRec.ps1 -Source D:\recup -Dest E:\sorted -Run
#>
param(
  [Parameter(Mandatory)][string]$Source,
  [Parameter(Mandatory)][string]$Dest,
  [int]$MinPhotoKB = 200,
  [int]$MinDocKB = 10,
  [int]$MinVideoMB = 5,
  [switch]$IncludeOther,
  [switch]$Move,
  [switch]$Run,
  [switch]$DryRun
)
$DryRun = -not $Run
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Source -PathType Container)) { throw "Not a folder: $Source" }

$cats = @{
  Photos    = '.jpg','.jpeg','.png','.gif','.bmp','.tif','.tiff','.heic','.webp','.cr2','.nef','.arw','.dng','.raf','.orf'
  Documents = '.pdf','.doc','.docx','.xls','.xlsx','.ppt','.pptx','.odt','.ods','.odp','.rtf','.txt','.csv','.epub'
  Videos    = '.mp4','.mov','.avi','.mkv','.mpg','.mpeg','.wmv','.3gp','.m4v','.flv'
  Audio     = '.mp3','.wav','.flac','.m4a','.ogg','.wma','.aac'
  Archives  = '.zip','.rar','.7z','.gz','.tar','.bz2'
}
$mins = @{ Photos = $MinPhotoKB*1KB; Documents = $MinDocKB*1KB; Videos = $MinVideoMB*1MB; Audio = 100KB; Archives = 10KB }

function Get-Category($ext) { foreach ($c in $cats.Keys) { if ($cats[$c] -contains $ext) { return $c } }; 'Other' }

function Get-PhotoDate($path) {
  try {
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    $img = [System.Drawing.Image]::FromFile($path)
    try {
      foreach ($id in 36867, 306) {
        if ($img.PropertyIdList -contains $id) {
          $raw = [System.Text.Encoding]::ASCII.GetString($img.GetPropertyItem($id).Value).Trim([char]0)
          return [datetime]::ParseExact($raw.Substring(0,19), 'yyyy:MM:dd HH:mm:ss', $null)
        }
      }
    } finally { $img.Dispose() }
  } catch {}
  $null
}

$files = Get-ChildItem -LiteralPath $Source -Recurse -File -ErrorAction SilentlyContinue
Write-Host "Found $($files.Count) files in $Source"
if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $Dest | Out-Null }

$seen = @{}; $kept = @{}; $keptBytes = @{}; $skipped = @{}; $rows = @()
function Skip($why) { $script:skipped[$why] = 1 + [int]$script:skipped[$why] }

# Biggest first so the best copy of a duplicate wins
foreach ($f in ($files | Sort-Object Length -Descending)) {
  $ext = $f.Extension.ToLower()
  $cat = Get-Category $ext
  if ($cat -eq 'Other' -and -not $IncludeOther) { Skip 'other type'; continue }
  if ($mins.ContainsKey($cat) -and $f.Length -lt $mins[$cat]) { Skip "too small ($cat)"; continue }
  try { $hash = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA1).Hash } catch { Skip 'unreadable'; continue }
  if ($seen.ContainsKey($hash)) { Skip 'duplicate'; continue }

  $extName = if ($ext) { $ext.TrimStart('.') } else { 'noext' }
  if ($cat -eq 'Photos') {
    $d = Get-PhotoDate $f.FullName
    $sub = Join-Path 'Photos' ($(if ($d) { $d.ToString('yyyy-MM') } else { 'undated' }))
  } else { $sub = Join-Path $cat $extName }
  $tdir = Join-Path $Dest $sub
  $target = Join-Path $tdir $f.Name
  $n = 1
  while (Test-Path -LiteralPath $target) { $target = Join-Path $tdir ("{0}_{1}{2}" -f $f.BaseName, $n, $f.Extension); $n++ }
  if (-not $DryRun) {
    New-Item -ItemType Directory -Force -Path $tdir | Out-Null
    if ($Move) { Move-Item -LiteralPath $f.FullName -Destination $target } else { Copy-Item -LiteralPath $f.FullName -Destination $target }
  }
  $seen[$hash] = $target
  $kept[$cat] = 1 + [int]$kept[$cat]; $keptBytes[$cat] = [long]$keptBytes[$cat] + $f.Length
  $rows += [pscustomobject]@{ file = $target; category = $cat; bytes = $f.Length; sha1 = $hash; original = $f.FullName }
}

if (-not $DryRun) { $rows | Export-Csv -NoTypeInformation -Path (Join-Path $Dest 'manifest.csv') }
if ($DryRun) { Write-Host "`nCHECK ONLY - nothing was copied. Add -Run to do it for real." }
Write-Host "`nKept:"
foreach ($c in ($kept.Keys | Sort-Object)) { '  {0,-10} {1,7} files {2,9:N1} MB' -f $c, $kept[$c], ($keptBytes[$c]/1MB) | Write-Host }
Write-Host "Skipped:"
foreach ($k in ($skipped.Keys | Sort-Object)) { '  {0,-22} {1}' -f $k, $skipped[$k] | Write-Host }
if (-not $DryRun) { Write-Host "`nDone. Sorted files and manifest.csv are in $Dest" }
