param(
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [string]$FlagPattern = '(?i)[A-Za-z]*(?:flag|ctf)[A-Za-z]*\{[^}]{4,100}\}'
)

if (-not (Test-Path -LiteralPath $Path)) {
    Write-Host "[-] File not found: $Path" -ForegroundColor Red
    return
}

$raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8

$matches = [regex]::Matches($raw, 'effected\s*(?:=|\+=)\s*"([^"]*)"')
if ($matches.Count -eq 0) {
    Write-Host "[-] No 'effected' payload found in file." -ForegroundColor Red
    return
}
$noisy = -join ($matches | ForEach-Object { $_.Groups[1].Value })

# Auto-detect the noise character: the most frequent character outside the Base64 alphabet
$noiseChar = $noisy.ToCharArray() |
    Where-Object { $_ -notmatch '[A-Za-z0-9+/=]' } |
    Group-Object |
    Sort-Object Count -Descending |
    Select-Object -First 1 -ExpandProperty Name

if (-not $noiseChar) {
    Write-Host "[-] Could not detect a noise character (payload looks like plain Base64)." -ForegroundColor Red
    return
}
Write-Host "[*] Detected noise character: '$noiseChar' (U+$('{0:X4}' -f [int][char]$noiseChar))"

$clean = $noisy -replace [regex]::Escape($noiseChar), ''
$clean += '=' * ((4 - $clean.Length % 4) % 4)

try {
    $stage1 = [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String($clean))
}
catch {
    Write-Host "[-] Base64 decode failed - noise character detection may be wrong for this sample." -ForegroundColor Red
    return
}

Write-Host "`n----- Stage 1 (decoded PowerShell) -----`n"
Write-Host $stage1
Write-Host "`n-----------------------------------------`n"

$outFile = [System.IO.Path]::ChangeExtension($Path, '.stage1.ps1')
Set-Content -LiteralPath $outFile -Value $stage1 -Encoding UTF8
Write-Host "[*] Stage 1 saved to: $outFile"

$flag = [regex]::Match($stage1, $FlagPattern)
if ($flag.Success) {
    Write-Host "[+] FLAG: $($flag.Value)" -ForegroundColor Green
}
else {
    Write-Host "[-] No flag found in stage 1 - inspect $outFile for further stages." -ForegroundColor Yellow
}
