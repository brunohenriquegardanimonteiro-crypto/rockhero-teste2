#Requires -Version 5.1
<#
    ============================================================================
     ROCK HERO  -  a Guitar-Hero-style rhythm game written entirely in PowerShell
    ============================================================================

     Every note of music, every drum hit and every chart is generated at runtime
     by an embedded C# synthesiser (compiled on the fly with Add-Type).  There
     are no sample files, no downloads and no dependencies: one .ps1 file,
     PowerShell 5.1+, Windows.

     USAGE
       .\rockhero.ps1                      play
       .\rockhero.ps1 -SelfTest            full automated test-suite
       .\rockhero.ps1 -ListSongs           print the song list and exit
       .\rockhero.ps1 -AudioDiag           report the sound card, the mix and the
                                           song clock (writes a text file too)
       .\rockhero.ps1 -DumpWav song3.wav -DumpSong 3
       .\rockhero.ps1 -Benchmark           render timing for every song

     KEYS
       1 2 3 4 5  (or A S D F G)   strike the five fret lanes
       SPACE                         Overdrive when the ROCK meter is full
       ESC                           pause / back
       ENTER                         confirm

     ABOUT THE MUSIC
       The riffs are ORIGINAL compositions written in the style of each band:
       a playable tribute, not a recording and not a transcription of
       copyrighted material.  Bands are credited so you know what you hear.
    ============================================================================
#>

[CmdletBinding()]
param(
    [switch] $SelfTest,
    [switch] $ListSongs,
    [switch] $Benchmark,
    [switch] $AudioDiag,
    [switch] $NoAudio,
    [switch] $Ascii,
    [ValidateRange(0, 100)]   [int]    $Volume    = 78,
    [ValidateRange(0.5, 2.0)] [double] $SpeedScale = 1.0,
    [string] $DumpWav = '',
    [ValidateRange(1, 99)]    [int]    $DumpSong  = 1
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# ============================================================================
#  GLOBALS
# ============================================================================
$script:LANES   = 5
$script:LW      = 6              # characters per fret lane
$script:HWLEFT  = 6              # left margin of the highway
$script:HWTOP   = 3              # first highway row
$script:MINW    = 72
$script:MINH    = 24
$script:IDEALW  = 104
$script:IDEALH  = 40

$script:W      = 104
$script:H      = 40
$script:HITROW = 34
$script:PANELX = 41
$script:PANELW = 30

$script:Ansi     = $false
$script:Ascii    = $Ascii.IsPresent
$script:NoAudio  = $NoAudio.IsPresent
$script:Vol      = $Volume
$script:SpScale  = $SpeedScale
# missed notes you are allowed before the song is lost; 0 = never fail
$script:FailMisses = 16
$script:E        = [string][char]0x1B

# judgement windows (seconds)
$script:WPerfect = 0.048
$script:WGreat   = 0.090
$script:WGood    = 0.140
$script:WMiss    = 0.170

$script:BaseTravel = 1.15        # seconds a note is on screen before the line
$script:FrameMs    = 20

$script:G        = $null
$script:C        = $null
$script:Base     = $null
$script:BaseW    = 0
$script:BaseH    = 0
$script:Sfx      = $null
$script:Music    = $null
$script:Blips    = @{}
$script:AudioDiagText = $null
$script:DataDir  = $null
$script:ScoreFile = $null
$script:High     = @{}
$script:Catalog  = $null
$script:ForceMain = $false
$script:Quitting = $false

# ============================================================================
#  EMBEDDED C# ENGINE
# ============================================================================
$script:EngineSource = @'
__ENGINE_SOURCE__
'@

function Initialize-Engine {
    if ('RockHero.Synth' -as [type]) { return $true }

    $sha = [Security.Cryptography.SHA1]::Create()
    $hash = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($script:EngineSource))).Replace('-', '')
    $script:EngineHash = $hash

    $asmPath = Join-Path $script:DataDir 'RockHeroEngine.dll'
    $stamp = Join-Path $script:DataDir 'RockHeroEngine.stamp'

    # A dll left behind by an older build would quietly keep running the old
    # engine, so the cached copy is only reused when the source hash matches.
    $cached = $false
    if ((Test-Path -LiteralPath $asmPath) -and (Test-Path -LiteralPath $stamp)) {
        $old = ''
        try { $old = [IO.File]::ReadAllText($stamp).Trim() } catch { }
        if ($old -eq $hash) { $cached = $true }
    }

    if ($cached) {
        try {
            Add-Type -Path $asmPath -ErrorAction Stop
            if ('RockHero.Synth' -as [type]) { return $true }
        } catch { }
    }

    # compile to a fresh file first: that way the cache can be refreshed in the
    # same run and the next launch starts instantly
    $built = $null
    try {
        $built = Join-Path ([IO.Path]::GetTempPath()) ('RockHeroEngine-' + $hash.Substring(0, 8) + '.dll')
        if (Test-Path -LiteralPath $built) { Remove-Item -LiteralPath $built -Force -ErrorAction SilentlyContinue }
        Add-Type -TypeDefinition $script:EngineSource -Language CSharp -OutputAssembly $built -ErrorAction Stop
        Add-Type -Path $built -ErrorAction Stop
        if ('RockHero.Synth' -as [type]) {
            try {
                Copy-Item -LiteralPath $built -Destination $asmPath -Force -ErrorAction Stop
                Set-Content -LiteralPath $stamp -Value $hash -Encoding ASCII -ErrorAction Stop
            } catch { }
            return $true
        }
    } catch { }

    Add-Type -TypeDefinition $script:EngineSource -Language CSharp -ErrorAction Stop
    return [bool]('RockHero.Synth' -as [type])
}

function Get-DataDir {
    $d = $null
    if ($env:LOCALAPPDATA) { $d = Join-Path $env:LOCALAPPDATA 'RockHeroPS' }
    if (-not $d) { $d = Join-Path ([IO.Path]::GetTempPath()) 'RockHeroPS' }
    try {
        if (-not (Test-Path -LiteralPath $d)) {
            New-Item -ItemType Directory -Path $d -Force -ErrorAction Stop | Out-Null
        }
    } catch { }
    $script:DataDir   = $d
    $script:ScoreFile = Join-Path $d 'highscores.xml'
    $script:SetFile   = Join-Path $d 'settings.txt'
    return $d
}

# ============================================================================
#  SETTINGS  (plain key=value so the file can still be hand-edited)
# ============================================================================
$script:FailLadder = @(3, 5, 8, 10, 16, 25, 50, 0)   # 0 = never

function Get-FailLabel {
    param([int]$N)
    if ($N -le 0) { return 'never (no limit)' }
    if ($N -eq 1) { return '1 miss and you are out' }
    return ('{0} misses and you are out' -f $N)
}

function Load-Settings {
    if (-not $script:SetFile) { return }
    try {
        if (-not (Test-Path -LiteralPath $script:SetFile)) { return }
        foreach ($ln in [IO.File]::ReadAllLines($script:SetFile)) {
            if ($ln -match '^\s*#') { continue }
            if ($ln -notmatch '=') { continue }
            $k = ($ln -split '=', 2)[0].Trim().ToLowerInvariant()
            $v = ($ln -split '=', 2)[1].Trim()
            switch ($k) {
                'failmisses' {
                    $n = 0
                    if ([int]::TryParse($v, [ref]$n) -and ($n -ge 0)) { $script:FailMisses = $n }
                }
                'volume' {
                    $n = 0
                    if ([int]::TryParse($v, [ref]$n) -and ($n -ge 0 -and $n -le 100)) { $script:Vol = $n }
                }
            }
        }
    } catch { }
}

function Save-Settings {
    if (-not $script:SetFile) { return $false }
    try {
        $body = @(
            '# RockHeroPS settings - delete this file to go back to the defaults',
            ('failmisses = ' + $script:FailMisses),
            ('volume = ' + $script:Vol)
        ) -join "`r`n"
        [IO.File]::WriteAllText($script:SetFile, $body + "`r`n")
        return $true
    } catch { return $false }
}

# ============================================================================
#  GLYPHS AND COLOURS
# ============================================================================
function New-GlyphTable {
    if ($script:Ascii) {
        $script:G = @{
            note = '#'; hold = '='; rail = '|'; receptor = '='; top = '-'
            barfull = '#'; empty = '.'; arrow = '>'; dot = '*'
        }
    } else {
        $script:G = @{
            note     = [string][char]0x2588   # full block
            hold     = [string][char]0x2593   # medium shade
            rail     = [string][char]0x2502   # box drawings light vertical
            receptor = [string][char]0x2550   # box drawings double horizontal
            top      = [string][char]0x2500   # box drawings light horizontal
            barfull  = [string][char]0x2588
            empty    = [string][char]0x2591   # light shade
            arrow    = [string][char]0x25B6   # black right pointing triangle
            dot      = [string][char]0x2605   # black star
        }
    }
    foreach ($k in @($script:G.Keys)) {
        if ($script:G[$k].Length -ne 1) { $script:G[$k] = [string]$script:G[$k][0] }
    }
}

function New-ColorTable {
    if ($script:Ascii) {
        $script:C = @{
            R = ''; Title = ''; Sel = ''; Nrm = ''; Dim = ''; Label = ''; Val = ''
            Perf = ''; Great = ''; Good = ''; Miss = ''; Hold = ''; Od = ''
            Bar = ''; Warn = ''; Ok = ''
        }
        return
    }
    $e = $script:E
    $script:C = @{
        R     = "$e[0m"
        Title = "$e[1;38;5;220m"
        Sel   = "$e[1;38;5;226m"
        Nrm   = "$e[38;5;250m"
        Dim   = "$e[38;5;240m"
        Label = "$e[38;5;245m"
        Val   = "$e[1;38;5;231m"
        Perf  = "$e[1;38;5;46m"
        Great = "$e[1;38;5;220m"
        Good  = "$e[38;5;51m"
        Miss  = "$e[1;38;5;203m"
        Hold  = "$e[38;5;208m"
        Od    = "$e[1;38;5;129m"
        Bar   = "$e[38;5;208m"
        Warn  = "$e[1;38;5;214m"
        Ok    = "$e[1;38;5;77m"
    }
}

# ============================================================================
#  AUDIO / INPUT HELPERS
# ============================================================================
function Play-Blip {
    param([int]$Kind = 0)
    if ($script:NoAudio -or $null -eq $script:Sfx) { return }
    try {
        if (-not $script:Blips.ContainsKey($Kind)) {
            $a = [RockHero.Synth]::Blip($Kind)
            $script:Blips[$Kind] = $a.Pcm
        }
        $script:Sfx.Play($script:Blips[$Kind], [int][RockHero.Synth]::SR)
    } catch { }
}

function Apply-Volume {
    try {
        if ($script:Sfx)   { $script:Sfx.Volume   = $script:Vol }
        if ($script:Music) { $script:Music.Volume = $script:Vol }
    } catch { }
}

function Get-AudioDiag {
    if ($script:AudioDiagText) { return $script:AudioDiagText }
    if ($script:NoAudio) { $script:AudioDiagText = 'audio: off (-NoAudio)'; return $script:AudioDiagText }
    if (-not ('RockHero.Player' -as [type])) {
        $script:AudioDiagText = 'audio: the C# engine did not compile'
        return $script:AudioDiagText
    }
    try { $script:AudioDiagText = 'audio: ' + [RockHero.Player]::Diagnose() }
    catch { $script:AudioDiagText = 'audio: probe failed - ' + $_.Exception.Message }
    return $script:AudioDiagText
}

# ---------------------------------------------------------------------------
#  -AudioDiag : say out loud why a song can be seen but not heard (or the
#  other way round).  Everything lands on screen and in a text file so the
#  report can be pasted somewhere else.
# ---------------------------------------------------------------------------
function Invoke-AudioDiag {
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $num = { param([double]$v, [int]$d = 2) [Math]::Round($v, $d).ToString(('F' + $d), $inv) }
    $rep = New-Object System.Collections.Generic.List[string]
    $say = {
        param([string]$m)
        [void]$rep.Add($m)
        Write-Host ('  ' + $m) -ForegroundColor DarkGray
    }

    Write-Host ''
    Write-Host '  ROCK HERO - audio report' -ForegroundColor Yellow
    Write-Host ''

    & $say ('powerShell      : ' + $PSVersionTable.PSVersion)
    & $say ('engine compiled : ' + ('RockHero.Player' -as [type]))
    & $say ('-NoAudio switch : ' + [bool]$script:NoAudio)
    & $say ('waveOut probe   : ' + (Get-AudioDiag) + '   (only waveOut; the real backend is shown below)')

    $song = $script:Catalog[0]
    if ($DumpSong -ge 1 -and $DumpSong -le $script:Catalog.Count) { $song = $script:Catalog[$DumpSong - 1] }
    $meta = Get-SongMeta $song
    & $say ('song            : ' + $song.Band + ' - ' + $song.Title + '  (' + (& $num $meta.Total 1) + 's)')

    $aud = $null; $chart = $null; $err = ''
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        $ev  = New-SongEvents $song $meta
        $aud = [RockHero.Synth]::Render($ev, $meta.Total)
        $chart = Get-Chart $song $meta 'Easy'
    } catch { $err = $_.Exception.Message }
    $sw.Stop()
    if ($err) { & $say ('RENDER FAILED   : ' + $err) }
    if ($null -ne $aud) {
        $peak = 0; $sum = 0.0
        foreach ($s in $aud.Pcm) {
            $a = [Math]::Abs([int]$s)
            if ($a -gt $peak) { $peak = $a }
            $sum += [double]$s * $s
        }
        $rms = [Math]::Sqrt($sum / [Math]::Max(1, $aud.Pcm.Length))
        & $say ('mix             : ' + $aud.Pcm.Length + ' bytes, ' + $aud.Rate + ' Hz, ' +
                (& $num ($aud.Pcm.Length / 2.0 / $aud.Rate) 2) + 's, peak=' + $peak + ', rms=' + (& $num $rms 1))
        if ($peak -eq 0) { & $say ('VERDICT         : the mix is digital silence - nothing can be heard.') }
    }
    if ($null -ne $chart) {
        & $say ('chart (Easy)    : ' + $chart.Count + ' notes, first at ' +
                (& $num $chart[0].T 2) + 's, last at ' +
                (& $num $chart[$chart.Count - 1].T 2) + 's')
    }
    & $say ('render took     : ' + (& $num $sw.Elapsed.TotalSeconds 2) + 's')

    $pl = $null
    try {
        $pl = [RockHero.Player]::new()
        $pl.Play($aud.Pcm, [int]$aud.Rate)
        $pl.Volume = $script:Vol
        & $say ('player mode     : ' + $pl.Mode + '   volume=' + $script:Vol + '/' + $pl.Volume)
        & $say ('hardware open   : ' + $pl.Hardware + '   duration=' + (& $num $pl.Duration 2) + 's')
        if ($pl.LastError) { & $say ('driver error    : ' + $pl.LastError) }
        if ($pl.Mode -like 'sound*') {
            & $say ('note            : waveOut is unusable on this PC (the driver opens but')
            & $say ('                  never reports a moving position), so playback moved')
            & $say ('                  to the MCI backend.  "sound+clock" means the music is')
            & $say ('                  really playing and the notes follow it on the wall clock.')
        }
        $at = @()
        for ($i = 0; $i -lt 6; $i++) {
            Start-Sleep -Milliseconds 450
            $at += (& $num $pl.Position 2)
        }
        & $say ('song clock      : ' + ($at -join ' -> ') + '  (seconds)')
        $moved = $false
        for ($i = 1; $i -lt $at.Count; $i++) { if ($at[$i] -gt $at[$i - 1]) { $moved = $true } }
        if (-not $moved) {
            & $say ('VERDICT         : the song clock never moves - the game falls back to the')
            & $say ('                  wall clock so the notes keep scrolling without sound.')
        }
    } catch {
        & $say ('PLAYER FAILED   : ' + $_.Exception.Message)
    }
    if ($null -ne $pl) { try { $pl.Stop(); $pl.Dispose() } catch { } }

    $where = $null
    try { $where = Join-Path (Get-DataDir) 'rockhero-audiodiag.txt' } catch { }
    if ($where) {
        try {
            [IO.File]::WriteAllText($where, ($rep -join "`r`n"), (New-Object Text.UTF8Encoding($false)))
            Write-Host ''
            Write-Host ('  report written to ' + $where) -ForegroundColor Yellow
        } catch { }
    }
    Write-Host ''
    return 0
}

function Read-Keys {
    $out = New-Object System.Collections.ArrayList
    try {
        $n = 0
        while ($n -lt 48 -and [Console]::KeyAvailable) {
            [void]$out.Add([Console]::ReadKey($true))
            $n++
        }
    } catch { }
    return $out
}

function Wait-Key {
    while ($true) {
        $k = $null
        try {
            if ([Console]::KeyAvailable) { $k = [Console]::ReadKey($true) }
        } catch { return $null }
        if ($null -ne $k) { return $k }
        [Threading.Thread]::Sleep(14)
    }
}

function Get-Bar {
    param([double]$Frac, [int]$Width)
    if ($Width -lt 4) { return '' }
    $f = $Frac
    if ($f -lt 0) { $f = 0 }
    if ($f -gt 1) { $f = 1 }
    $n = [int][Math]::Round($f * $Width)
    return ($script:G.barfull * $n) + ($script:G.empty * ($Width - $n))
}
