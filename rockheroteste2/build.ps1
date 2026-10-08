param([string]$OutFile = 'C:\Users\bruno\AppData\Local\Temp\opencode\RockHero\rockhero.ps1')

$dir = 'C:\Users\bruno\AppData\Local\Temp\opencode\RockHero'
$engine = Get-Content -LiteralPath (Join-Path $dir 'RockEngine.cs') -Raw
if ($null -eq $engine) { throw 'engine source missing' }
# a here-string terminates only at a line that starts with '@
if ($engine -match "(?m)^\s*'@") { throw 'engine source contains a here-string terminator' }

$parts = @('p01.ps1','p02.ps1','p02b.ps1','p03.ps1','p04.ps1','p05.ps1','p06.ps1','p07.ps1','p08.ps1')
$chunks = New-Object System.Collections.Generic.List[string]
foreach ($p in $parts) {
    $t = Get-Content -LiteralPath (Join-Path $dir $p) -Raw
    if ($null -eq $t) { throw "missing part $p" }
    $chunks.Add($t.TrimEnd())
}

$text = ($chunks -join "`r`n`r`n") + "`r`n"
$marker = '__ENGINE_SOURCE__'
if ($text.IndexOf($marker) -lt 0) { throw 'engine marker not found' }
$text = $text.Replace($marker, $engine.TrimEnd())

# syntax check before writing
$errors = $null
$null = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$null, [ref]$errors)
if ($errors -and $errors.Count -gt 0) {
    Write-Host 'PARSE ERRORS:' -ForegroundColor Red
    foreach ($e in $errors) {
        Write-Host ('  line {0} col {1}: {2}' -f $e.Extent.StartLineNumber, $e.Extent.StartColumnNumber, $e.Message)
    }
    exit 1
}

$utf8 = New-Object System.Text.UTF8Encoding($true)
[IO.File]::WriteAllText($OutFile, $text, $utf8)
Write-Host ('wrote {0}  ({1:N0} bytes, {2} lines)' -f $OutFile, $text.Length, ($text -split "`n").Count)
Write-Host 'parse: OK'
