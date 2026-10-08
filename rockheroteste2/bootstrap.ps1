# bootstrap.ps1 - RockHero one-liner bootstrap (idempotent)
[CmdletBinding()]
param(
    [string]$Branch = 'main',
    [string]$Owner  = 'brunohenriquegardanimonteiro-crypto',
    [string]$Repo   = 'rockhero-teste2',
    [string]$Entry  = '',
    [switch]$SelfTest,
    [switch]$NoAudio,
    [switch]$Console,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$Base    = Join-Path $env:LOCALAPPDATA 'RockHero'
$RepoDir = Join-Path $Base $Repo
$Zip     = Join-Path $Base "$Repo.zip"
$Url     = "https://github.com/$Owner/$Repo/archive/refs/heads/$Branch.zip"

New-Item -ItemType Directory -Force -Path $Base |
