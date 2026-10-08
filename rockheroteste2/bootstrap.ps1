# bootstrap.ps1 - RockHero one-liner bootstrap (idempotent)
[CmdletBinding()]
param(
    [string]$Branch = 'main',
    [string]$Owner  = 'brunohenriquegardanimonteiro',
    [string]$Repo   = 'rockhero',
    [string]$Entry  = '',
    [switch]$SelfTest,
    [switch]$NoAudio,
    [switch]$Console
)

$ErrorActionPreference = 'Stop'
$Base = Join-Path $env:LOCALAPPDATA 'RockHero'
$State = Join-Path $Base '.state'
$RepoDir = Join-Path $Base $Repo
$Zip = Join-Path $Base "$Repo.zip"

New-Item -ItemType Directory -Force -Path $Base, $State | Out-Null

$Url = "https://github.com/$Owner/$Repo/archive/refs/heads/$Branch.zip"
$Launcher = Join-Path $RepoDir 'rockhero.ps1'

function Get-FileHashString {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $h = Get-FileHash -LiteralPath $Path -Algorithm SHA256
    return $h.Hash
}

if (-not (Test-Path -LiteralPath $Launcher)) {
    try { Invoke-WebRequest -Uri $Url -OutFile $Zip -UseBasicParsing -ErrorAction Stop } catch {
        $wc = New-Object Net.WebClient
        $wc.DownloadFile($Url, $Zip)
    }
    Expand-Archive -LiteralPath $Zip -DestinationPath $Base -Force
    $Exp = Join-Path $Base ("$Repo-$Branch")
    if (Test-Path -LiteralPath $Exp) {
        if (Test-Path -LiteralPath $RepoDir) { Remove-Item -LiteralPath $RepoDir -Recurse -Force }
        Move-Item -LiteralPath $Exp -Destination $RepoDir
    }
    Remove-Item $Zip -Force -ErrorAction SilentlyContinue
}

if (-not (Test-Path -LiteralPath $Launcher)) {
    throw "rockhero.ps1 não encontrado em $RepoDir"
}

$Args = @()
if ($Entry) { $Args += '-Entry'; $Args += $Entry }
if ($SelfTest) { $Args += '-SelfTest' }
if ($NoAudio)  { $Args += '-NoAudio' }
if ($Console)  { $Args += '-Console' }
& $Launcher $Args
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
