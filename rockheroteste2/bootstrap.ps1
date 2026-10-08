# bootstrap.ps1 - RockHero one-liner bootstrap (idempotent)
[CmdletBinding()]
param(
    [string]$Branch = 'main',
    [string]$Owner  = 'brunohenriquegardanimonteiro-crypto',
    [string]$Repo   = 'rockhero-teste2',
    [switch]$Force,
    [string]$Entry  = '',
    [switch]$SelfTest,
    [switch]$ListSongs,
    [switch]$Benchmark,
    [switch]$AudioDiag,
    [switch]$NoAudio,
    [switch]$Ascii,
    [switch]$Console,
    [int]$Volume,
    [double]$SpeedScale
)

$ErrorActionPreference = 'Stop'
$Base    = Join-Path $env:LOCALAPPDATA 'RockHero'
$RepoDir = Join-Path $Base $Repo
$Zip     = Join-Path $Base "$Repo.zip"
$Url     = "https://github.com/$Owner/$Repo/archive/refs/heads/$Branch.zip"

$null = New-Item -ItemType Directory -Force -Path $Base

function Find-Launcher {
    if (-not (Test-Path -LiteralPath $RepoDir)) { return $null }
    $f = Get-ChildItem -LiteralPath $RepoDir -Recurse -Filter 'rockhero.ps1' -File
    if ($f) { return @($f)[0].FullName }
    return $null
}

$Launcher = Find-Launcher
if ($Force -or -not $Launcher) {
    Write-Host "Baixando $Url"
    Invoke-WebRequest -Uri $Url -OutFile $Zip -UseBasicParsing
    $Tmp = Join-Path $Base '_extract'
    if (Test-Path -LiteralPath $Tmp) { Remove-Item -LiteralPath $Tmp -Recurse -Force }
    Expand-Archive -LiteralPath $Zip -DestinationPath $Tmp -Force
    if (Test-Path -LiteralPath $RepoDir) { Remove-Item -LiteralPath $RepoDir -Recurse -Force }
    $Root = @(Get-ChildItem -LiteralPath $Tmp -Directory)[0]
    Move-Item -LiteralPath $Root.FullName -Destination $RepoDir
    Remove-Item -LiteralPath $Tmp -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $Zip -Force -ErrorAction SilentlyContinue
    $Launcher = Find-Launcher
}

if (-not $Launcher) { throw "rockhero.ps1 nao encontrado em $RepoDir" }

# repassa apenas o que o rockhero.ps1 realmente aceita
$accepted = @((Get-Command -Name $Launcher).Parameters.Keys)
$own = @('Branch', 'Owner', 'Repo', 'Force')
$splat = @{}
foreach ($k in $PSBoundParameters.Keys) {
    if ($own -contains $k) { continue }
    if ($accepted -contains $k) {
        $splat[$k] = $PSBoundParameters[$k]
    } else {
        Write-Warning "parametro -$k nao existe no rockhero.ps1 e foi ignorado"
    }
}

& $Launcher @splat
if ($LASTEXITCODE) { Write-Host "rockhero terminou com codigo $LASTEXITCODE" }
