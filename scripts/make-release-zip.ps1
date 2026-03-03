param(
    [string]$Output = "clawusage.zip"
)

$root = Split-Path -Parent $PSScriptRoot
$dest = Join-Path $root $Output
$destName = [System.IO.Path]::GetFileName($dest)

if (Test-Path -LiteralPath $dest) {
    Remove-Item -LiteralPath $dest -Force
}

$items = Get-ChildItem -LiteralPath $root -Force | Where-Object {
    $_.Name -ne $destName -and $_.Name -ne ".openclaw-state" -and $_.Name -ne ".publish-repo"
}

if (($items | Measure-Object).Count -eq 0) {
    throw "No files to package."
}

Compress-Archive -Path ($items | ForEach-Object { $_.FullName }) -DestinationPath $dest -Force
Write-Host "Created: $dest"
