# ============================================================================
#  GAME RULES
#  These are plain functions of (score state, chart, position) so the whole
#  judgement / hold / meter / fail system can be driven head-less by -SelfTest.
# ============================================================================
function Invoke-Hit {
    # a lane was struck at time $pos
    param($S, $Chart, [double]$Pos, [int]$Lane)
    if ($Lane -lt 0 -or $Lane -ge $script:LANES) { return }
    $best = -1; $bd = 9.0e9
    for ($j = $S.Cur[$Lane]; $j -lt $Chart.Count; $j++) {
        $n = $Chart[$j]
        $dt = $n.T - $Pos
        if ($dt -gt $script:WMiss) { break }
        if ($n.Judged) { continue }
        if ($n.Lane -ne $Lane) { continue }
        $ad = [Math]::Abs($dt)
        if ($ad -lt $bd) { $bd = $ad; $best = $j }
    }
    if ($best -lt 0) { return }

    $n = $Chart[$best]
    $n.Judged = $true
    $n.Offset = $n.T - $Pos
    $jt = Get-Judgement $n.Offset
    switch ($jt) {
        'PERFECT' { $S.Perfect++; $S.Meter += 0.017; Add-Score $S 300 $n.Offset; $S.JudColor = 'Perf' }
        'GREAT'   { $S.Great++;   $S.Meter += 0.012; Add-Score $S 200 $n.Offset; $S.JudColor = 'Great' }
        'GOOD'    { $S.Good++;    $S.Meter += 0.007; Add-Score $S 100 $n.Offset; $S.JudColor = 'Good' }
    }
    $S.Judged++
    $S.Judgement = $jt; $S.JudAt = $Pos
    if ($n.Hold -gt 0.06) { $S.HoldN[$Lane] = $n }
    else {
        $S.Combo++
        if ($S.Combo -gt $S.MaxCombo) { $S.MaxCombo = $S.Combo }
    }
    if ($S.Meter -ge 1.0) { $S.Meter = 1.0; $S.OdReady = $true }
}

function Step-LaneCursors {
    # keep each lane's cursor on the next note that could still be struck
    param($S, $Chart, [double]$Pos)
    for ($l = 0; $l -lt $script:LANES; $l++) {
        while ($S.Cur[$l] -lt $Chart.Count) {
            $cn = $Chart[$S.Cur[$l]]
            if ($cn.Lane -eq $l -and -not $cn.Judged) { break }
            if ($cn.T -gt ($Pos + 1.0)) { break }
            $S.Cur[$l]++
        }
    }
}

# The player is out when the misses he allowed himself run out.  A dropped
# hold counts as a miss, exactly like it does in the real thing.  With
# $script:FailMisses = 0 there is no limit at all and the song can only end
# when the last note is done.
function Get-StrikeLeft {
    param($S)
    if ($script:FailMisses -le 0) { return -1 }
    return ($script:FailMisses - ($S.Miss + $S.HoldDrop))
}

function Test-RockOut {
    param($S)
    if ($script:FailMisses -le 0) { return $false }
    return (($S.Miss + $S.HoldDrop) -ge $script:FailMisses)
}

function Kill-Player {
    param($S)
    $S.Meter = 0; $S.Failed = $true; $S.Done = $true
}

function Step-Misses {
    param($S, $Chart, [double]$Pos)
    while ($S.Idx -lt $Chart.Count -and ($Chart[$S.Idx].T - $Pos) -lt (-$script:WMiss)) {
        $n = $Chart[$S.Idx]
        if (-not $n.Judged) {
            $n.Judged = $true
            $S.Miss++; $S.Judged++
            $S.Combo = 0
            $S.Meter -= 0.062
            $S.Judgement = 'MISS'; $S.JudAt = $Pos; $S.JudColor = 'Miss'
            if (Test-RockOut $S) { Kill-Player $S }
        }
        $S.Idx++
    }
}

function Step-Holds {
    param($S, [double]$Pos)
    for ($l = 0; $l -lt $script:LANES; $l++) {
        $n = $S.HoldN[$l]
        if ($null -eq $n) { continue }
        $end = $n.T + $n.Hold
        if ($Pos -ge ($end - 0.025)) {
            $S.Holds++
            $S.Meter += 0.012
            $S.Combo++
            if ($S.Combo -gt $S.MaxCombo) { $S.MaxCombo = $S.Combo }
            Add-Score $S (120 + [int]($n.Hold * 240)) 0.0
            $S.Judgement = 'HOLD'; $S.JudAt = $Pos; $S.JudColor = 'Hold'
            $S.HoldN[$l] = $null
            if ($S.Meter -ge 1.0) { $S.Meter = 1.0; $S.OdReady = $true }
        } elseif (-not $S.Down[$l]) {
            $S.HoldDrop++
            $S.Combo = 0
            $S.Meter -= 0.030
            $S.Judgement = 'DROPPED'; $S.JudAt = $Pos; $S.JudColor = 'Miss'
            $S.HoldN[$l] = $null
            if (Test-RockOut $S) { Kill-Player $S }
        } elseif (($Pos - $end) -gt 0.6) {
            $S.HoldN[$l] = $null
        }
    }
}

function Step-Meter {
    param($S, [int]$Frame)
    if ($S.Od -gt 0) {
        if (($Frame % 2) -eq 0) { $S.Od -= 1.0 / 30.0 }
        if ($S.Od -le 0) { $S.Od = 0; $S.Meter = 0.92; $S.OdReady = $false }
    } else {
        $S.Meter -= 0.0006
        if ($S.Meter -lt 0) { $S.Meter = 0 }
    }
}

function Invoke-Overdrive {
    param($S, [double]$Pos)
    if (-not $S.OdReady -or $S.Od -gt 0) { return $false }
    $S.Od = 8.0; $S.OdReady = $false; $S.Meter = 1.0
    $S.Judgement = 'OVERDRIVE'; $S.JudAt = $Pos; $S.JudColor = 'Od'
    return $true
}

# ============================================================================
#  THE GAME LOOP
# ============================================================================
function Invoke-Game {
    param([int]$SongIndex, [string]$DiffName)

    $song = $script:Catalog[$SongIndex]
    $meta = Get-SongMeta $song
    $df   = Get-Difficulty $DiffName
    Set-Screen

    # ---- build the band -------------------------------------------------
    $lines = New-BlankLines
    # keep the status line on a row the console actually has, otherwise a short
    # window shows a blank screen for as long as the band takes to synthesise
    $brow = 10
    if ($brow -gt ($script:H - 2)) { $brow = [Math]::Max(0, $script:H - 2) }
    $bcol = [Math]::Max(0, [int](($script:W - 22) / 2))
    Set-Cell $lines $brow $bcol ($script:C.Title + 'building the band...' + $script:C.R) 21
    Write-Screen $lines
    try { [Console]::Out.Flush() } catch { }

    $aud = $null; $chart = $null; $err = $null
    $bw = [Diagnostics.Stopwatch]::StartNew()
    try {
        if (Test-CustomSong $song) {
            # the chart comes out of the recording itself, and the recording is
            # what plays: nothing is synthesised for these songs
            $cErr = ''
            $ce = [ref]$cErr
            $null = Get-CustomAnalysis $song $ce
            if ($cErr) { throw $cErr }
            # a file from the music folder can end up with no notes at all, and
            # @() keeps that an empty list instead of nothing
            $chart = @(Get-Chart $song $meta $DiffName)
            if ($chart.Count -eq 0) { throw 'no notes could be placed in this recording' }
            $meta = Get-SongMeta $song
        } else {
            $ev = New-SongEvents $song $meta
            $aud = [RockHero.Synth]::Render($ev, $meta.Total)
            $chart = @(Get-Chart $song $meta $DiffName)
            if ($chart.Count -eq 0) { throw 'chart is empty' }
        }
    } catch {
        $err = $_.Exception.Message
    }
    $bw.Stop()

    if ($err) {
        Set-Screen
        $items = @('BACK')
        $null = Show-Menu -Title 'AUDIO ERROR' -Sub $err -Items $items `
            -DrawRow { param($i, $s)
                if ($s) { return $script:C.Sel + $script:G.arrow + ' BACK' + $script:C.R }
                return '   BACK' }
        return 'back'
    }

    # ---- start the song --------------------------------------------------
    $S  = New-ScoreState $chart
    $audioMode = 'off'
    if (-not $script:NoAudio -and $null -ne $script:Music) {
        try {
            if (Test-CustomSong $song) {
                $ok = $false
                try { $ok = [bool]$script:Music.PlayFile($song.Path) } catch { $ok = $false }
                if ($ok) {
                    $script:Music.Volume = $script:Vol
                    $audioMode = 'file'
                    $dur = [double]$script:Music.Duration
                    if ($dur -gt 0.2) {
                        $meta.Total = [double]$meta.LeadIn + $dur + 2.0
                        $song.Duration = $dur
                    }
                } else {
                    $audioMode = 'off'
                }
            } else {
                $script:Music.Play($aud.Pcm, [int]$aud.Rate)
                $script:Music.Volume = $script:Vol
                $audioMode = $script:Music.Mode
            }
        } catch { $audioMode = 'off' }
    }
    if ($audioMode -eq 'none') { $audioMode = 'off' }
    if ($audioMode -ne 'off' -and $audioMode -notlike 'sound*') {
        # be honest about a driver that opens but produces no sound at all,
        # otherwise the panel just says "audio: waveOut" and looks healthy.
        # The probe only exercises waveOut, so skip it when MCI is the backend.
        $probe = Get-AudioDiag
        if ($probe -match 'silent|refused|no audio device') { $audioMode = $audioMode + ' NO SOUND' }
    }

    $travel = $script:BaseTravel / ($df.Speed * $script:SpScale)
    $nRows  = ($script:HITROW - $script:HWTOP) + 1
    if ($nRows -lt 4) { $nRows = 4 }
    $invRow = $nRows / $travel
    $lastT  = $chart[$chart.Count - 1].T
    $endAt  = $meta.Total
    if (($lastT + 3.0) -gt $endAt) { $endAt = $lastT + 3.0 }

    $sw = [Diagnostics.Stopwatch]::StartNew()
    $frame = 0
    $pauseOffset = 0.0
    # The note timeline follows the sound, but never at the cost of a frozen
    # screen: if the device position stops moving while the wall clock does not,
    # the song carries on driven by the stopwatch.
    $useClock  = ($audioMode -eq 'off')
    $audioPos  = 0.0
    $audioSeen = 0.0

    while ($true) {
        $f0 = $sw.Elapsed.TotalMilliseconds

        if (-not $useClock) {
            $wall = $sw.Elapsed.TotalSeconds - $pauseOffset
            $ap = -1.0
            try { $ap = [double]$script:Music.Position } catch { $ap = -1.0 }
            if ($ap -lt 0) {
                $useClock = $true
            } elseif ($ap -gt ($audioPos + 0.002)) {
                $audioPos = $ap; $audioSeen = $wall
            } elseif (($wall - $audioSeen) -gt 0.75) {
                $useClock = $true
            }
            if ($useClock) { $audioMode = $audioMode + '+clock' }
        }
        if ($useClock) { $pos = $sw.Elapsed.TotalSeconds - $pauseOffset }
        else           { $pos = $audioPos }
        if ($pos -lt 0) { $pos = 0 }

        # ---------------- input -------------------------------------------
        foreach ($k in (Read-Keys)) {
            if ($k.Key -eq 'Escape') {
                $tPause = $sw.Elapsed.TotalSeconds
                $act = Show-Pause
                if ($act -eq 'list')  { $S.Done = $true; break }
                if ($act -eq 'main')  { $S.Done = $true; $script:ForceMain = $true; break }
                if ($act -eq 'restart') {
                    try { if ($script:Music) { $script:Music.Stop() } } catch { }
                    return 'restart'
                }
                if ($useClock) { $pauseOffset += $sw.Elapsed.TotalSeconds - $tPause }
                else { $audioSeen = $sw.Elapsed.TotalSeconds - $pauseOffset }
                continue
            }
            if ($k.Key -eq 'Space') {
                $null = Invoke-Overdrive $S $pos
                continue
            }
            $lane = Get-LaneFromKey $k
            if ($lane -lt 0) { continue }
            if ($k.Key -eq 'KeyUp') { $S.Down[$lane] = $false; continue }

            $S.Down[$lane] = $true
            $S.Flash[$lane] = $pos
            Invoke-Hit $S $chart $pos $lane
        }

        Step-LaneCursors $S $chart $pos
        Step-Misses     $S $chart $pos
        Step-Holds      $S $pos
        Step-Meter      $S $frame

        if ($pos -ge $endAt) { $S.Done = $true }
        if ($S.Failed) { $S.Done = $true }

        Write-Screen (New-GameFrame $S $song $df $pos $invRow $audioMode $meta)
        $frame++

        if ($S.Done) { break }

        # ---------------- frame pacing ------------------------------------
        $el = $sw.Elapsed.TotalMilliseconds - $f0
        $rem = $script:FrameMs - $el
        if ($rem -gt 2.0) {
            [Threading.Thread]::Sleep([int]($rem - 1.0))
        } elseif ($rem -gt 0.3) {
            $sp = [Diagnostics.Stopwatch]::StartNew()
            while ($sp.Elapsed.TotalMilliseconds -lt $rem) { }
        }
    }

    try { if ($script:Music) { $script:Music.Stop() } } catch { }
    $rv = Show-Results $SongIndex $DiffName $S $song $df
    if ($rv -eq 'main') { return 'main' }
    if ($rv -eq 'retry') { return 'restart' }
    return 'back'
}

# ============================================================================
#  PAUSE
# ============================================================================
function Show-Pause {
    while ($true) {
        if ($script:Music) { $script:Music.Pause() }
        Set-Screen
        $items = @('RESUME', 'RESTART SONG', 'SONG LIST', 'MAIN MENU')
        $sel = Show-Menu -Title 'PAUSED' -Sub 'the song is waiting' -Items $items `
            -DrawRow {
                param($i, $s)
                $mark = if ($s) { $script:C.Sel + $script:G.arrow + ' ' } else { '   ' }
                $col  = if ($s) { $script:C.Sel } else { $script:C.Nrm }
                return $mark + $col + $items[$i] + $script:C.R
            } `
            -DrawFoot { $script:C.Label + 'ESC resumes' + $script:C.R }
        if ($null -ne $script:Music) { $script:Music.Resume() }
        if ($sel -eq -1 -or $sel -eq 0) { return 'resume' }
        if ($sel -eq 1) { return 'restart' }
        if ($sel -eq 2) { return 'list' }
        if ($sel -eq 3) { return 'main' }
    }
}

# ============================================================================
#  RESULTS
# ============================================================================
function Show-Results {
    param([int]$SongIndex, [string]$DiffName, $S, $Song, $Df)

    $acc  = Get-Accuracy $S.Perfect $S.Great $S.Good $S.Miss
    $rank = Get-Rank $acc
    $stars = Get-Stars $acc
    $rec = [pscustomobject]@{
        Score = $S.Score; Combo = $S.MaxCombo; Acc = $acc; Rank = $rank
        Stars = $stars; When = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        Diff = $DiffName; Song = $Song.Title; Band = $Song.Band
        Perfect = $S.Perfect; Great = $S.Great; Good = $S.Good; Miss = $S.Miss
    }
    $isNew = Set-ScoreFor $SongIndex $DiffName $rec
    if ($isNew) { Save-Scores | Out-Null }

    Set-Screen
    while ($true) {
        $lines = New-BlankLines
        $c = $script:C; $g = $script:G
        $w = $script:W

        $head = if ($S.Failed) { 'YOU ROCKED OUT' } else { 'RESULTS' }
        $pad = [int][Math]::Max(0, [int](($w - $head.Length) / 2))
        Set-Cell $lines 1 $pad ($c.Title + $head + $c.R) $head.Length
        Set-Cell $lines 2 4 ($c.Label + ('{0} - {1}   [{2}]' -f $Song.Band, $Song.Title, $Df.Pt) + $c.R) 40

        # rank block
        $rankCol = $c.Title
        if ($rank -eq 'D' -or $rank -eq 'C') { $rankCol = $c.Miss }
        elseif ($rank -eq 'A' -or $rank -eq 'B') { $rankCol = $c.Good }
        $rw = [Math]::Max(0, [int](($w - 10) / 2))
        Set-Cell $lines 5 $rw ($rankCol + ('  ' + $rank + '  ') + $c.R) ($rank.Length + 4)
        $starTxt = ($g.dot * $stars) + ($g.empty * (5 - $stars))
        Set-Cell $lines 6 ($rw - 1) ($c.Title + $starTxt + $c.R) 5

        $stats = @(
            @('SCORE',    ('{0,10}' -f $S.Score),      11),
            @('ACCURACY', ('{0,9:N2}%' -f ($acc * 100)), 12),
            @('MAX COMBO',('{0,10}' -f $S.MaxCombo),     11),
            @('PERFECT',  ('{0,10}' -f $S.Perfect),      10),
            @('GREAT',    ('{0,10}' -f $S.Great),        10),
            @('GOOD',     ('{0,10}' -f $S.Good),         10),
            @('MISS',     ('{0,10}' -f $S.Miss),         10),
            @('HOLDS',    ('{0,10}  ({1} dropped)' -f $S.Holds, $S.HoldDrop), 25)
        )
        $lw = 10
        $sx = 4
        $row = 9
        foreach ($st in $stats) {
            $label = [string]$st[0]
            $value = [string]$st[1]
            $vlen  = [int]$st[2]
            Set-Cell $lines $row $sx ($c.Label + ('{0,-' + $lw + '}') -f $label) $lw
            $vc = $c.Val
            if ($label -eq 'MISS' -and $S.Miss -gt 0) { $vc = $c.Miss }
            if ($label -eq 'PERFECT') { $vc = $c.Perf }
            if ($label -eq 'GREAT')   { $vc = $c.Great }
            Set-Cell $lines $row ($sx + $lw + 2) ($vc + $value + $c.R) ($vlen + 2)
            $row++
        }

        if ($isNew) {
            Set-Cell $lines $row 4 ($c.Ok + '>> NEW HIGH SCORE <<' + $c.R) 22
        } else {
            $best = Get-ScoreFor $SongIndex $DiffName
            if ($best) {
                Set-Cell $lines $row 4 ($c.Label + ('best {0}  [{1}]' -f $best.Score, $best.Rank) + $c.R) 22
            }
        }
        $row++
        Set-Cell $lines $row 4 ($c.Label + 'ENTER = song list    ESC = main menu    R = retry' + $c.R) 48

        Write-Screen $lines
        $k = Wait-Key
        if ($null -eq $k) { return 'list' }
        if ($k.Key -eq 'Enter' -or $k.Key -eq 'Space') { return 'list' }
        if ($k.Key -eq 'Escape') { return 'main' }
        $ch = [string]$k.KeyChar
        if ($ch -match '^[rR]$') { return 'retry' }
    }
}
