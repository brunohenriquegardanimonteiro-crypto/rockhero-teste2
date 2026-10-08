# ============================================================================
#  MUSIC THEORY / EVENT GENERATION
# ============================================================================
function Get-SongMeta {
    param($Song)
    # a file from the player's own folder: the length comes from the recording
    # and a short lead-in lets the first notes scroll in before they are judged
    if (Test-CustomSong $Song) {
        $leadIn = 2.0
        $dur = [double]$Song.Duration
        if ($dur -lt 1.0) { $dur = 1.0 }
        return [pscustomobject]@{
            Song = $Song; Step = 0.25; Bar = 1.0; Bars = 0
            LeadIn = $leadIn; Beat = 0.5
            Total = ($leadIn + $dur + 2.0)
            Custom = $true
        }
    }
    $step = 60.0 / $Song.Bpm / 4.0
    $bar  = $step * 16.0
    $bars = $Song.Riff.Count * 4
    $leadIn = $bar * 2.0
    $total  = $leadIn + ($bars * $bar) + 2.5
    [pscustomobject]@{
        Song = $Song; Step = $step; Bar = $bar; Bars = $bars
        LeadIn = $leadIn; Beat = $step * 4.0; Total = $total
    }
}

function New-Ev {
    param([double]$T, [double]$Dur, [int]$Kind, [int]$Midi, [double]$Vol, [int]$Third = 0)
    $e = [RockHero.Ev]::new()
    $e.T = $T; $e.Dur = $Dur; $e.Kind = $Kind; $e.Midi = $Midi; $e.Vol = $Vol; $e.Third = $Third
    return $e
}

function New-SongEvents {
    param($Song, $Meta)
    $list  = New-Object 'System.Collections.Generic.List[RockHero.Ev]'
    $offs  = if ($Song.Minor) { @(0, 3, 7, 12, 10) } else { @(0, 4, 7, 12, 11) }
    $third = if ($Song.Minor) { 3 } else { 4 }
    $scale = if ($Song.Minor) { @(0, 2, 3, 5, 7, 8, 10, 12, 14, 15) } else { @(0, 2, 4, 5, 7, 9, 11, 12, 14, 16) }
    $step  = $Meta.Step

    $kGtr = 0; $kBass = 1; $kKick = 2; $kSnare = 3; $kHat = 4; $kCrash = 5; $kLead = 6

    # ---- count-in: crash on the bar line, hats on every beat -------------
    for ($bi = 0; $bi -lt 2; $bi++) {
        for ($i = 0; $i -lt 16; $i += 4) {
            $t = ($bi * 16 + $i) * $step
            if ($i -eq 0) { $list.Add((New-Ev $t 0.04 $kCrash 72 0.50 0)) }
            $list.Add((New-Ev $t 0.01 $kHat 60 0.32 0))
        }
    }

    for ($bar = 0; $bar -lt $Meta.Bars; $bar++) {
        $riff = $Song.Riff[$bar % $Song.Riff.Count]
        $dm   = $Song.Drums[$bar % $Song.Drums.Count]
        $ld   = $Song.Lead[$bar % $Song.Lead.Count]
        $root = $Song.Root + [int]$Song.Prog[$bar % $Song.Prog.Count]
        $t0   = $Meta.LeadIn + ($bar * 16 * $step)

        # -------- rhythm guitar -------------------------------------------
        for ($i = 0; $i -lt 16; $i++) {
            $gl = [string]$riff[$i]
            if ($gl -notmatch '^[0-4]$') { continue }
            $f = [int]$gl
            $midi = $root + $offs[$f]
            $dur = $step * 2.0
            for ($j = $i + 1; $j -lt 16; $j++) {
                $nx = [string]$riff[$j]
                if ($nx -ne '.' -and $nx -ne '-') { $dur = ($j - $i) * $step; break }
            }
            if ($dur -gt 0.95)     { $dur = 0.95 }
            if ($dur -lt $step)     { $dur = $step }
            $list.Add((New-Ev ($t0 + $i * $step) $dur $kGtr $midi 0.46 $third))
        }

        # -------- bass -----------------------------------------------------
        for ($i = 0; $i -lt 16; $i += 2) {
            $t = $t0 + $i * $step
            $m = $root - 12
            $dur = $step * 1.6
            if ($i -eq 6) { $m = $root - 5; $dur = $step * 1.2 }
            $list.Add((New-Ev $t $dur $kBass $m 0.52 0))
        }

        # -------- drums ----------------------------------------------------
        for ($i = 0; $i -lt 16; $i++) {
            $dc = [string]$dm[$i]
            if ($dc -eq '.') { continue }
            $t = $t0 + $i * $step
            switch ($dc) {
                'K' { $list.Add((New-Ev $t 0.02 $kCrash 72 0.34 0)) }
                'k' { $list.Add((New-Ev $t 0.02 $kKick 36 0.72 0)) }
                's' { $list.Add((New-Ev $t 0.02 $kSnare 60 0.64 0)) }
                'h' { $list.Add((New-Ev $t 0.01 $kHat 62 0.24 0)) }
                'H' { $list.Add((New-Ev $t 0.01 $kHat 62 0.30 0)) }
                'x' { $list.Add((New-Ev $t 0.01 $kHat 62 0.36 0)) }
                default { }
            }
        }

        # -------- lead melody ----------------------------------------------
        for ($i = 0; $i -lt 16; $i++) {
            $lc = [string]$ld[$i]
            if ($lc -notmatch '^[0-9]$') { continue }
            $d = [int]$lc
            $midi = $root + 12 + $scale[$d]
            $dur = $step * 1.4
            for ($j = $i + 1; $j -lt 16; $j++) {
                $nx = [string]$ld[$j]
                if ($nx -ne '.' -and $nx -ne '-') { $dur = ($j - $i) * $step; break }
            }
            if ($dur -gt 0.7) { $dur = 0.7 }
            $list.Add((New-Ev ($t0 + $i * $step) $dur $kLead $midi 0.32 0))
        }
    }
    return $list
}

# ============================================================================
#  CHART BUILDING
# ============================================================================
$script:Difficulty = @(
    [pscustomobject]@{ Name = 'Easy';   Pt = 'Easy';   Speed = 0.72; Sub = 1; Lead = $false; Drum = $false
                        Desc = 'relaxed 8ths, slow scroll' }
    [pscustomobject]@{ Name = 'Normal'; Pt = 'Normal'; Speed = 1.00; Sub = 0; Lead = $false; Drum = $false
                        Desc = 'the full riff exactly as written' }
    [pscustomobject]@{ Name = 'Hard';   Pt = 'Hard';   Speed = 1.25; Sub = 0; Lead = $true;  Drum = $false
                        Desc = '+ lead-melody stream, faster scroll' }
    [pscustomobject]@{ Name = 'Expert'; Pt = 'Expert'; Speed = 1.52; Sub = 0; Lead = $true;  Drum = $true
                        Desc = '+ drums. brutal note streams' }
)

function Get-Difficulty { param([string]$Name)
    $d = $script:Difficulty | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    if ($null -eq $d) { $d = $script:Difficulty[1] }
    return $d
}

function New-ChartNote {
    param([double]$T, [int]$Lane, [double]$Hold, [int]$Step)
    [pscustomobject]@{ T = $T; Lane = $Lane; Hold = $Hold; Step = $Step
                       Judged = $false; Judgement = ''; Offset = 0.0 }
}

function Get-Chart {
    param($Song, $Meta, [string]$DiffName = 'Normal')
    if (Test-CustomSong $Song) { return (Get-CustomChart $Song $Meta $DiffName) }
    $d = Get-Difficulty $DiffName
    $notes = New-Object System.Collections.Generic.List[object]
    $step  = $Meta.Step
    $lastT = @{}
    $lastN = @{}

    for ($bar = 0; $bar -lt $Meta.Bars; $bar++) {
        $riff = $Song.Riff[$bar % $Song.Riff.Count]
        $t0   = $Meta.LeadIn + ($bar * 16 * $step)

        for ($i = 0; $i -lt 16; $i++) {
            $gl = [string]$riff[$i]
            $absStep = ($bar * 16) + $i
            if ($gl -notmatch '^[0-4]$') { continue }
            $f = [int]$gl
            # Easy keeps the 8th-note skeleton
            if ($d.Sub -eq 1 -and ($absStep % 2) -ne 0) { continue }

            # a repeated fret in the same lane becomes a hold note
            if ($lastN.ContainsKey($f) -and $lastT.ContainsKey($f)) {
                $gap = $absStep - $lastT[$f]
                $pn = $lastN[$f]
                if ($gap -ge 1 -and $gap -le 5 -and $pn.Hold -le 0.0) {
                    $pn.Hold = [Math]::Min(1.30, ($gap - 0.80) * $step)
                }
            }
            $n = New-ChartNote ($t0 + $i * $step) $f 0.0 $absStep
            $notes.Add($n)
            $lastN[$f] = $n
            $lastT[$f] = $absStep
        }
    }

    if ($d.Lead) {
        for ($bar = 0; $bar -lt $Meta.Bars; $bar++) {
            $ld = $Song.Lead[$bar % $Song.Lead.Count]
            $t0 = $Meta.LeadIn + ($bar * 16 * $step)
            for ($i = 0; $i -lt 16; $i += 2) {
                $lc = [string]$ld[$i]
                if ($lc -notmatch '^[0-9]$') { continue }
                $dg = [int]$lc
                $notes.Add((New-ChartNote ($t0 + $i * $step) (2 + ($dg % 3)) 0.0 (($bar * 16) + $i)))
            }
        }
    }

    if ($d.Drum) {
        for ($bar = 0; $bar -lt $Meta.Bars; $bar++) {
            $dm = $Song.Drums[$bar % $Song.Drums.Count]
            $t0 = $Meta.LeadIn + ($bar * 16 * $step)
            for ($i = 0; $i -lt 16; $i += 2) {
                $dc = [string]$dm[$i]
                if ($dc -eq '.') { continue }
                $lane = 4
                if ($dc -eq 'k')     { $lane = 1 }
                elseif ($dc -eq 's') { $lane = 3 }
                elseif ($dc -eq 'K') { $lane = 4 }
                elseif ($dc -eq 'x') { $lane = 2 }
                else                 { $lane = 0 }
                $notes.Add((New-ChartNote ($t0 + $i * $step) $lane 0.0 (($bar * 16) + $i)))
            }
        }
    }

    $arr = $notes.ToArray()
    if ($arr.Length -eq 0) { return $arr }
    [Array]::Sort($arr, [Comparison[object]] {
        param($a, $b)
        if ($a.T -lt $b.T) { return -1 }
        if ($a.T -gt $b.T) { return 1 }
        if ($a.Lane -lt $b.Lane) { return -1 }
        if ($a.Lane -gt $b.Lane) { return 1 }
        return 0
    })

    # Two notes in the same lane closer than 48 ms cannot both be hit, and the
    # drum stream overlaps the riff lanes, so the later note is dropped.
    $kept = New-Object System.Collections.Generic.List[object]
    $lastKept = @{}
    foreach ($n in $arr) {
        if ($lastKept.ContainsKey($n.Lane)) {
            if (($n.T - $lastKept[$n.Lane].T) -lt 0.048) { continue }
        }
        $kept.Add($n)
        $lastKept[$n.Lane] = $n
    }
    $arr = $kept.ToArray()

    # a hold tail may never run into the next note of the same lane
    $byLane = @{}
    foreach ($n in $arr) {
        if ($byLane.ContainsKey($n.Lane)) {
            $p = $byLane[$n.Lane]
            if (($n.T - $p.T) -lt ($p.Hold + 0.070)) { $p.Hold = 0.0 }
        }
        $byLane[$n.Lane] = $n
    }
    return $arr
}

# ============================================================================
#  SCORING  (pure functions - also exercised by -SelfTest)
# ============================================================================
function Get-Judgement {
    param([double]$Delta)
    $a = [Math]::Abs($Delta)
    if ($a -le $script:WPerfect) { return 'PERFECT' }
    if ($a -le $script:WGreat)   { return 'GREAT' }
    if ($a -le $script:WGood)    { return 'GOOD' }
    return 'MISS'
}

function Get-BasePoints {
    param([string]$J)
    switch ($J) { 'PERFECT' { 300 } 'GREAT' { 200 } 'GOOD' { 100 } default { 0 } }
}

function Get-Mult {
    param([int]$Combo)
    if ($Combo -ge 100) { return 5 }
    if ($Combo -ge 50)  { return 4 }
    if ($Combo -ge 25)  { return 3 }
    if ($Combo -ge 10)  { return 2 }
    return 1
}

function Get-Accuracy {
    param([int]$P, [int]$G, [int]$Gd, [int]$M)
    $n = $P + $G + $Gd + $M
    if ($n -le 0) { return 0.0 }
    return ($P + ($G * 0.75) + ($Gd * 0.45)) / $n
}

function Get-Rank {
    param([double]$Acc)
    if ($Acc -ge 0.97) { return 'S+' }
    if ($Acc -ge 0.93) { return 'S' }
    if ($Acc -ge 0.88) { return 'A' }
    if ($Acc -ge 0.80) { return 'B' }
    if ($Acc -ge 0.70) { return 'C' }
    return 'D'
}

function Get-Stars {
    param([double]$Acc)
    $n = [int][Math]::Floor($Acc * 5.0)
    if ($n -lt 0) { $n = 0 }
    if ($n -gt 5) { $n = 5 }
    return $n
}
