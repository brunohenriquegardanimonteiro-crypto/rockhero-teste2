# ============================================================================
#  THE PLAYER'S OWN MUSIC  (%LOCALAPPDATA%\RockHeroPS\music)
#
#  Any wav/mp3 file dropped in that folder shows up in the song list.  The
#  recording itself is the clock (MCI reports its real position), and the notes
#  are placed on the onsets the analysis finds in the audio, so the chart
#  follows what you actually hear instead of a guessed tempo.
# ============================================================================
$script:MusicExt = @('.wav', '.wave', '.mp3', '.wma', '.m4a', '.aac', '.ogg')
$script:ChartExt = @('.wav', '.wave', '.mp3', '.wma', '.m4a', '.aac', '.ogg')
$script:MusicFolder = $null
$script:ChartFolder = $null

# StrictMode 2 makes reading a missing property an error, and the built in songs
# have no Custom flag at all, so it is looked up instead of read.
function Test-CustomSong {
    param($Song)
    if ($null -eq $Song) { return $false }
    return ($null -ne $Song.PSObject.Properties['Custom'])
}

function Get-MusicFolder {
    if ($script:MusicFolder) { return $script:MusicFolder }
    $base = $script:DataDir
    if (-not $base) { $base = Get-DataDir }
    $d = Join-Path $base 'music'
    try {
        if (-not (Test-Path -LiteralPath $d)) {
            New-Item -ItemType Directory -Path $d -Force -ErrorAction Stop | Out-Null
        }
    } catch { }
    $script:MusicFolder = $d
    $script:ChartFolder = (Join-Path $base 'charts')
    try {
        if (-not (Test-Path -LiteralPath $script:ChartFolder)) {
            New-Item -ItemType Directory -Path $script:ChartFolder -Force -ErrorAction Stop | Out-Null
        }
    } catch { }
    return $d
}

function Get-CleanTitle {
    param([string]$Path)
    $n = [IO.Path]::GetFileNameWithoutExtension($Path)
    # "03 - Artist - Title (live)" reads a lot better than the raw file name
    $n = $n -replace '^\s*\d{1,3}\s*[-._)]\s*', ''
    $n = $n -replace '[_]+', ' '
    $n = $n -replace '\s{2,}', ' '
    return $n.Trim()
}

# A song entry for a file on disk.  Nothing heavy happens here: only the wav
# header is read, so a folder full of songs costs no measurable time.
function New-CustomSong {
    param([string]$Path)
    $info = $null
    try { $info = [RockHero.Decode]::Info($Path) } catch { $info = $null }
    $dur = 0.0
    if ($null -ne $info -and $info.Ok) { $dur = [double]$info.Seconds }
    $ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    $ready = ($dur -gt 0.5)
    $song = [pscustomobject]@{
        Custom = $true
        Path = $Path
        Title = (Get-CleanTitle $Path)
        Band = 'my music'
        Style = $ext.TrimStart('.')
        Bpm = 0
        Duration = $dur
        Ready = $ready
        Onsets = $null
        ChartNote = if ($ready) { '' } else { 'not analysed yet' }
    }
    # a file analysed before already knows its tempo, so the song list can show
    # it without decoding the audio again
    $cached = Read-AnalysisCache $song
    if ($null -ne $cached -and $cached.Length -gt 0) {
        $song.Onsets = $cached
        $song.Ready = $true
        $song.ChartNote = ('{0} onsets (cached)' -f $cached.Length)
    } elseif (-not $ready) {
        $song.ChartNote = 'not analysed yet'
    }
    return $song
}

function Get-CustomSongs {
    $out = New-Object System.Collections.Generic.List[object]
    $dir = Get-MusicFolder
    if (-not (Test-Path -LiteralPath $dir)) { return $out.ToArray() }
    $files = $null
    try { $files = [IO.Directory]::GetFiles($dir) } catch { $files = @() }
    foreach ($f in $files) {
        $ext = [IO.Path]::GetExtension($f).ToLowerInvariant()
        if ($script:MusicExt -notcontains $ext) { continue }
        try { $out.Add((New-CustomSong $f)) } catch { }
    }
    # no comma: the caller wraps this in @() so one file is still a list of one
    return $out.ToArray()
}

function Get-ChartCacheFile {
    param([string]$Path)
    $name = [IO.Path]::GetFileNameWithoutExtension($Path)
    $safe = ($name -replace '[^A-Za-z0-9._-]', '_')
    if ($safe.Length -gt 60) { $safe = $safe.Substring(0, 60) }
    return (Join-Path $script:ChartFolder ($safe + '.onsets'))
}

# The detector settings are part of the cache key: changing them must not be
# answered with onsets from an older run.
$script:ChartVer = 'v4 invariant-cache'

function Get-ChartStamp {
    param([string]$Path)
    $fi = New-Object IO.FileInfo $Path
    # The engine hash travels with the stamp: onsets from a different detector
    # must never be served from the cache.
    return ('#' + $script:ChartVer + ' ' + $script:EngineHash + ' ' + $fi.Length + '|' + $fi.LastWriteTimeUtc.Ticks)
}

function Read-AnalysisCache {
    param($Song)
    try {
        $f = Get-ChartCacheFile $Song.Path
        if (-not (Test-Path -LiteralPath $f)) { return $null }
        $lines = [IO.File]::ReadAllLines($f)
        if ($lines.Length -lt 3) { return $null }
        if ($lines[0] -ne (Get-ChartStamp $Song.Path)) { return $null }
        # line 2 carries the tempo and length so the cached path shows the same
        # numbers as a fresh analysis
        $meta = ($lines[1] -split '\|')
        if ($meta.Count -ge 2) {
            $Song.Bpm = [int][double]::Parse($meta[0], [Globalization.CultureInfo]::InvariantCulture)
            $Song.Duration = [double]::Parse($meta[1], [Globalization.CultureInfo]::InvariantCulture)
        }
        $list = New-Object System.Collections.Generic.List[object]
        $ic = [Globalization.CultureInfo]::InvariantCulture
        for ($i = 2; $i -lt $lines.Length; $i++) {
            $ln = $lines[$i]
            if ([string]::IsNullOrWhiteSpace($ln)) { continue }
            $p = $ln.Split('|')
            if ($p.Length -lt 4) { continue }
            $o = [pscustomobject]@{
                T = [double]::Parse($p[0], $ic); Strength = [double]::Parse($p[1], $ic)
                Centroid = [double]::Parse($p[2], $ic); Sustain = [double]::Parse($p[3], $ic)
            }
            $list.Add($o)
        }
        return ,$list.ToArray()
    } catch { return $null }
}

function Write-AnalysisCache {
    param($Song, $Onsets)
    try {
        $f = Get-ChartCacheFile $Song.Path
        $ic = [Globalization.CultureInfo]::InvariantCulture
        $sb = New-Object Text.StringBuilder
        [void]$sb.AppendLine((Get-ChartStamp $Song.Path))
        [void]$sb.AppendLine(('{0}|{1}' -f ([int]$Song.Bpm).ToString('0', $ic), ([double]$Song.Duration).ToString('0.###', $ic)))
        foreach ($o in $Onsets) {
            # invariant culture: a comma here would be read back as a thousands
            # separator and turn 4.835 seconds into 4835
            [void]$sb.AppendLine(([double]$o.T).ToString('0.000', $ic) + '|' +
                ([double]$o.Strength).ToString('0.000', $ic) + '|' +
                ([double]$o.Centroid).ToString('0.###', $ic) + '|' +
                ([double]$o.Sustain).ToString('0.000', $ic))
        }
        [IO.File]::WriteAllText($f, $sb.ToString())
        return $true
    } catch { return $false }
}

# Runs the detector (or reads the cache).  Returns $null plus an error string
# when the file cannot be charted at all.
function Get-CustomAnalysis {
    param($Song, [ref]$ErrorText)
    $ErrorText.Value = ''
    $cached = Read-AnalysisCache $Song
    if ($null -ne $cached -and $cached.Length -gt 0) {
        $Song.Onsets = $cached
        $Song.Ready = $true
        if ($Song.Duration -lt 0.5) { $Song.Duration = Get-FileSeconds $Song.Path }
        $Song.ChartNote = ('{0} onsets (cached)' -f $cached.Length)
        return ,$cached
    }

    $tmp = $null
    $target = $Song.Path
    try {
        $ext = [IO.Path]::GetExtension($Song.Path).ToLowerInvariant()
        if ($ext -ne '.wav' -and $ext -ne '.wave') {
            # let Windows itself decode mp3/aac/wma into a wav we can read
            $tmp = Join-Path ([IO.Path]::GetTempPath()) ('rhchart-{0}.wav' -f [guid]::NewGuid().ToString('N').Substring(0, 8))
            $err = [string][RockHero.Decode]::ToWav($Song.Path, $tmp)
            if ($err) { $ErrorText.Value = $err; return $null }
            $target = $tmp
        }

        $info = [RockHero.Decode]::Info($target)
        if (-not $info.Ok) { $ErrorText.Value = [string]$info.Error; return $null }

        # hop 5 ms for the time resolution, no two notes closer than 60 ms,
        # threshold 1.2 deviations above the local average
        $on = [RockHero.Decode]::Analyze($target, 5.0, 60.0, 1.2)
        if ($null -eq $on -or $on.Length -eq 0) {
            $ErrorText.Value = 'no clear rhythm found in this recording'
            return $null
        }
        $list = New-Object System.Collections.Generic.List[object]
        foreach ($o in $on) {
            $list.Add(([pscustomobject]@{
                T = [double]$o.T; Strength = [double]$o.Strength
                Centroid = [double]$o.Centroid; Sustain = [double]$o.Sustain
            }))
        }
        $arr = $list.ToArray()
        $Song.Onsets = $arr
        $Song.Duration = [double]$info.Seconds
        $Song.Ready = $true
        $Song.Bpm = (Get-OnsetBpm $arr)
        Write-AnalysisCache $Song $arr | Out-Null
        $Song.ChartNote = ('{0} onsets, {1:N0} bpm' -f $arr.Length, $Song.Bpm)
        return $arr
    } catch {
        $ErrorText.Value = $_.Exception.Message
        return $null
    } finally {
        if ($tmp) { try { Remove-Item -LiteralPath $tmp -Force -EA SilentlyContinue } catch { } }
    }
}

# Display-only tempo: finds the beat grid the onsets sit on. Every candidate
# bpm is tried and scored by how far the gaps are from a subdivision of it, so
# a fast song is not reported at half its speed.
function Get-OnsetBpm {
    param($Onsets)
    if ($null -eq $Onsets -or $Onsets.Length -lt 6) { return 0 }

    # histogram of the gaps in 20 ms bins
    $bin = 0.02
    $hist = New-Object 'int[]' 100
    $total = 0
    for ($i = 1; $i -lt $Onsets.Length; $i++) {
        $g = [double]$Onsets[$i].T - [double]$Onsets[$i - 1].T
        if ($g -lt 0.08 -or $g -gt 2.0) { continue }
        $b = [int][Math]::Floor($g / $bin)
        if ($b -lt 0 -or $b -ge $hist.Length) { continue }
        $hist[$b] = $hist[$b] + 1
        $total++
    }
    if ($total -lt 6) { return 0 }

    $bestBpm = 0
    $bestScore = [double]::MaxValue
    for ($bpm = 70; $bpm -le 180; $bpm++) {
        $step = 60.0 / $bpm
        $err = 0.0
        $hit = 0
        for ($b = 0; $b -lt $hist.Length; $b++) {
            if ($hist[$b] -le 0) { continue }
            $g = ($b + 0.5) * $bin
            $k = [Math]::Round($g / $step)
            if ($k -lt 1) { continue }
            $r = [Math]::Abs($g / $step - $k)
            if ($r -gt 0.30) { $r = 0.30 + $r }
            $err += $r * $hist[$b]
            if ($r -lt 0.18) { $hit += $hist[$b] }
        }
        # a grid that explains most of the gaps wins; ties go to the faster one
        $score = $err + (1.0 - ($hit / [double]$total)) * 3.0 + ($bpm * 0.0006)
        if ($score -lt $bestScore) { $bestScore = $score; $bestBpm = $bpm }
    }
    if ($bestBpm -le 0) { return 0 }
    return $bestBpm
}

function Get-FileSeconds {
    param([string]$Path)
    try {
        $p = New-Object RockHero.Player
        $ok = $p.PlayFile($Path)
        $s = 0.0
        if ($ok) { $s = [double]$p.Duration }
        $p.Stop(); $p.Dispose()
        if ($s -gt 0.2) { return $s }
    } catch { }
    # last resort: size over a plausible 128 kbit/s stream
    try {
        $kb = (New-Object IO.FileInfo $Path).Length / 16000.0
        if ($kb -gt 1) { return [Math]::Min(900.0, $kb) }
    } catch { }
    return 0.0
}

# Brightness decides the lane, the way high frets sit in the top lane: the
# quantiles are taken from this song itself, so a bright track fills the top
# lanes and a dark one the bottom without any hard coded frequency.
function Get-CustomLanes {
    param($Onsets)
    # Lanes come from the rank of the brightness, not from absolute Hz cutoffs:
    # every recording ends up with a spread over all five lanes, and the quiet
    # bass hits go to the low lane while the bright ones go to the high one.
    $n = $script:LANES
    $count = $Onsets.Length
    $lane = New-Object 'int[]' $count
    if ($count -eq 0) { return ,$lane }
    $order = New-Object 'int[]' $count
    for ($i = 0; $i -lt $count; $i++) { $order[$i] = $i }
    # ties are broken by index so the same onsets always give the same lanes,
    # fresh or cached
    $sorted = $order | Sort-Object -Property @{ Expression = { [double]$Onsets[$_].Centroid } }, @{ Expression = { $_ } }
    $pos = 0
    foreach ($i in $sorted) {
        $l = [int][Math]::Floor(($pos * $n) / $count)
        if ($l -ge $n) { $l = $n - 1 }
        if ($l -lt 0) { $l = 0 }
        $lane[$i] = $l
        $pos++
    }
    return ,$lane
}

function Get-CustomChart {
    param($Song, $Meta, [string]$DiffName)
    $d = Get-Difficulty $DiffName
    $ons = $Song.Onsets
    if ($null -eq $ons -or $ons.Length -eq 0) { return @() }

    $gapLimit = 0.26; $minStrength = 0.55
    switch ($d.Name) {
        'Easy'   { $gapLimit = 0.28; $minStrength = 0.60 }
        'Normal' { $gapLimit = 0.17; $minStrength = 0.42 }
        'Hard'   { $gapLimit = 0.12; $minStrength = 0.30 }
        default  { $gapLimit = 0.08; $minStrength = 0.00 }
    }

    $laneOf = Get-CustomLanes $ons
    $n = $script:LANES
    $notes = New-Object System.Collections.Generic.List[object]
    $lastT = -99.0
    $lastLane = -1
    $runSame = 0

    for ($i = 0; $i -lt $ons.Length; $i++) {
        $o = $ons[$i]
        if ($o.Strength -lt $minStrength) { continue }
        $t = [double]$o.T + [double]$Meta.LeadIn
        if (($t - $lastT) -lt $gapLimit) { continue }

        # lane chosen by brightness rank
        $lane = [int]$laneOf[$i]

        # three of the same lane in a row is not playable: walk it towards the middle
        if ($lane -eq $lastLane) {
            $runSame++
            if ($runSame -ge 2) {
                if ($lane -lt ($n - 1)) { $lane = $lane + 1 } else { $lane = $lane - 1 }
                $runSame = 0
            }
        } else { $runSame = 0 }

        $notes.Add((New-ChartNote $t $lane 0.0 0))
        $lastT = $t
        $lastLane = $lane
    }
    if ($notes.Count -eq 0) { return @() }

    # sustained sounds become hold notes: only when the lane stays free
    $busy = @{}
    foreach ($nn in $notes) {
        $k = [string]$nn.Lane
        if ($busy.ContainsKey($k)) {
            $busy[$k] = [double]$busy[$k] + [double]$nn.Hold + 0.070
        } else { $busy[$k] = [double]$nn.T }
    }
    for ($i = 0; $i -lt $ons.Length; $i++) {
        $o = $ons[$i]
        if ($o.Strength -lt $minStrength) { continue }
        $sus = [double]$o.Sustain
        if ($sus -lt 0.20) { continue }
        $t = [double]$o.T + [double]$Meta.LeadIn
        if (($t - $lastT) -gt 0.0 -and ($t - $lastT) -lt $gapLimit) { continue }
        foreach ($nn in $notes) {
            if ([Math]::Abs([double]$nn.T - $t) -gt 0.004) { continue }
            $hold = [Math]::Min(1.60, $sus - 0.06)
            if ($hold -lt 0.20) { continue }
            $clash = $false
            foreach ($other in $notes) {
                if ($other.Lane -ne $nn.Lane) { continue }
                if ($other -eq $nn) { continue }
                $d2 = [double]$other.T - $t
                if ($d2 -gt 0.001 -and $d2 -lt ($hold + 0.070)) { $clash = $true; break }
            }
            if (-not $clash) { $nn.Hold = $hold }
            break
        }
    }

    $arr = $notes.ToArray()
    [Array]::Sort($arr, [Comparison[object]] {
        param($x, $y)
        if ($x.T -lt $y.T) { return -1 }
        if ($x.T -gt $y.T) { return 1 }
        if ($x.Lane -lt $y.Lane) { return -1 }
        if ($x.Lane -gt $y.Lane) { return 1 }
        return 0
    })

    # same lane too close together cannot be hit
    $kept = New-Object System.Collections.Generic.List[object]
    $lastKept = @{}
    foreach ($nn in $arr) {
        if ($lastKept.ContainsKey($nn.Lane)) {
            if (([double]$nn.T - [double]$lastKept[$nn.Lane].T) -lt 0.048) { continue }
        }
        $kept.Add($nn)
        $lastKept[$nn.Lane] = $nn
    }
    return $kept.ToArray()
}