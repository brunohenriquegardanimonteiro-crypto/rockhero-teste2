# ============================================================================
#  SELF TEST
# ============================================================================
$script:TPass = 0
$script:TFail = 0
$script:TLog  = New-Object System.Collections.ArrayList

function T-Result {
    param([bool]$Ok, [string]$Name, [string]$Detail = '')
    if ($Ok) {
        $script:TPass++
        [void]$script:TLog.Add(@($true, $Name, ''))
    } else {
        $script:TFail++
        [void]$script:TLog.Add(@($false, $Name, $Detail))
        Write-Host ("  FAIL  " + $Name + $(if ($Detail) { "  ->  " + $Detail } else { '' })) -ForegroundColor Red
    }
}

function T-Is {
    param([bool]$Cond, [string]$Name, [string]$Detail = '')
    T-Result $Cond $Name $Detail
}

function T-Throws {
    param([scriptblock]$Block, [string]$Name)
    $threw = $false
    try { $null = & $Block } catch { $threw = $true }
    T-Result $threw $Name 'expected an exception but none was thrown'
}

function T-NoThrow {
    param([scriptblock]$Block, [string]$Name)
    $msg = ''
    $ok = $true
    try { $null = & $Block } catch { $ok = $false; $msg = $_.Exception.Message }
    T-Result $ok $Name $msg
}

# same check, but the value the block produced is left in $script:TVal so the
# caller can look at it (an assignment inside a plain scriptblock would not
# survive the scope)
function T-Try {
    param([scriptblock]$Block, [string]$Name)
    $script:TVal = $null
    $script:TOk = $true
    $script:TErr = ''
    try { $script:TVal = & $Block } catch { $script:TOk = $false; $script:TErr = $_.Exception.Message }
    T-Result $script:TOk $Name $script:TErr
    return $script:TOk
}

function Test-ValidBar {
    param([string]$Pattern, [string]$Name)
    $rx = [regex]::new($Pattern)
    return $rx.IsMatch($Name)
}

function Simulate-Play {
    param($Chart, [string]$Mode, [double]$Delta = 0.0, [int]$Seed = 7)
    $P = 0; $G = 0; $Gd = 0; $M = 0
    $rng = New-Object Random $Seed
    foreach ($n in $Chart) {
        $hit = $true
        if ($Mode -eq 'idle') { $hit = $false }
        elseif ($Mode -eq 'random') { $hit = ($rng.NextDouble() -lt 0.65) }
        if ($hit) {
            switch (Get-Judgement $Delta) {
                'PERFECT' { $P++ }
                'GREAT'   { $G++ }
                'GOOD'    { $Gd++ }
                default   { $M++ }
            }
        } else { $M++ }
    }
    return [pscustomobject]@{ P = $P; G = $G; Gd = $Gd; M = $M }
}

function New-TestChart {
    # every scenario needs its own note objects: Judged lives on the note
    param([switch]$WithHold)
    $l = New-Object System.Collections.Generic.List[object]
    foreach ($p in @(@(1.0, 0), @(2.0, 1), @(3.0, 2), @(4.0, 3), @(5.0, 4), @(6.0, 1))) {
        $l.Add((New-ChartNote $p[0] $p[1] 0.0 0))
    }
    if ($WithHold) {
        $l.Clear()
        $l.Add((New-ChartNote 2.0 2 0.0 0))
        $l.Add((New-ChartNote 4.0 4 0.60 1))
    }
    return $l.ToArray()
}

function Invoke-SelfTest {
    $script:TPass = 0; $script:TFail = 0; $script:TLog = New-Object System.Collections.ArrayList
    Write-Host ''
    Write-Host '  ROCK HERO - SELF TEST' -ForegroundColor Yellow
    Write-Host '  ----------------------' -ForegroundColor DarkGray

    $SR = [int][RockHero.Synth]::SR

    # ---------------- engine ---------------------------------------------
    T-Is ($null -ne ('RockHero.Synth' -as [type])) 'engine type loaded'
    T-Is ($SR -eq 32000) 'sample rate is 32000' ("got $SR")

    foreach ($b in 0..3) {
        T-NoThrow { $null = [RockHero.Synth]::Blip($b) } "blip kind $b synthesises"
    }
    $b0 = [RockHero.Synth]::Blip(0)
    T-Is ($b0.Pcm.Length -gt 100) 'blip produces samples' ("len=$($b0.Pcm.Length)")
    T-Is (-not $b0.HasNaN) 'blip has no NaN samples'

    $empty = [RockHero.Synth]::Render((New-Object 'System.Collections.Generic.List[RockHero.Ev]'), 0.5)
    T-Is ($empty.Pcm.Length -gt 0) 'rendering an empty score still yields a buffer'
    T-Is (-not $empty.HasNaN) 'empty render has no NaN'
    T-Is ($empty.Peak -eq 0) 'empty render is silent' ("peak=$($empty.Peak)")

    $zero = [RockHero.Synth]::Render((New-Object 'System.Collections.Generic.List[RockHero.Ev]'), -5.0)
    T-Is ($zero.Seconds -gt 0.1) 'negative duration is clamped' ("sec=$($zero.Seconds)")

    $w = [RockHero.Synth]::WrapWav($empty)
    T-Is ($w.Length -eq ($empty.Pcm.Length + 44)) 'WAV header adds exactly 44 bytes'
    T-Is ([Text.Encoding]::ASCII.GetString($w, 0, 4) -eq 'RIFF') 'WAV starts with RIFF'
    T-Is ([Text.Encoding]::ASCII.GetString($w, 8, 4) -eq 'WAVE') 'WAV has WAVE type'
    T-Is ([Text.Encoding]::ASCII.GetString($w, 36, 4) -eq 'data') 'WAV has data chunk'
    $bits = [BitConverter]::ToInt16($w, 34)
    T-Is ($bits -eq 16) 'WAV is 16 bit'
    $ch = [BitConverter]::ToInt16($w, 22)
    T-Is ($ch -eq 1) 'WAV is mono'

    # ---------------- player ---------------------------------------------
    $p = [RockHero.Player]::new()
    T-NoThrow { $p.Play($null, 32000) } 'player tolerates a null buffer'
    T-Is ($p.Mode -eq 'silent' -or $p.Mode -eq 'none') 'player falls back safely on a null buffer' ("mode=$($p.Mode)")

    $tiny = New-Object 'byte[]' (32000 * 2)
    T-NoThrow { $p.Play($tiny, 32000) } 'player accepts a 1 second buffer'
    T-Is ($p.Duration -gt 0.9 -and $p.Duration -lt 1.1) 'player reports the right duration' ("dur=$($p.Duration)")
    $pos1 = $p.Position
    [Threading.Thread]::Sleep(120)
    $pos2 = $p.Position
    T-Is ($pos2 -ge $pos1) 'player position never goes backwards' ("$pos1 -> $pos2")
    T-NoThrow { $p.Volume = -50 } 'player clamps a negative volume'
    T-Is ($p.Volume -eq 0) 'volume clamps at 0' ("vol=$($p.Volume)")
    $p.Volume = 500
    T-Is ($p.Volume -eq 100) 'volume clamps at 100'
    T-NoThrow { $p.Pause(); $p.Resume(); $p.Stop() } 'pause/resume/stop do not throw'
    T-NoThrow { $p.Stop() } 'stop is idempotent'
    T-NoThrow { $p.Dispose(); $p.Dispose() } 'dispose is idempotent'

    # ---------------- catalogue -------------------------------------------
    $cat = $script:Catalog
    T-Is ($null -ne $cat -and $cat.Count -ge 20) 'catalogue has at least 20 songs' ("count=$(if ($cat) { $cat.Count } else { 0 })")

    $riffRx   = '^[.\-0-4]{16}$'
    $drumRx   = '^[.KksshHx]{16}$'
    $leadRx   = '^[.\-0-9]{16}$'
    $badRiff = @(); $badDrum = @(); $badLead = @()
    $badMeta = @(); $badProg = @(); $badBars = @()
$titles = @{}; $dupes = @()
    $nOwn = 0

    foreach ($s in $cat) {
        # a file from the player's own folder has no riff, and it is checked on
        # its own further down
        if (Test-CustomSong $s) { $nOwn++; continue }
        if ($titles.ContainsKey($s.Title + '|' + $s.Band)) { $dupes += ($s.Band + '/' + $s.Title) }
        $titles[$s.Title + '|' + $s.Band] = 1
        if ($s.Bpm -lt 40 -or $s.Bpm -gt 220) { $badMeta += ($s.Title + ' bpm=' + $s.Bpm) }
        if ($s.Root -lt 20 -or $s.Root -gt 80) { $badMeta += ($s.Title + ' root=' + $s.Root) }
        foreach ($r in $s.Riff)  { if (-not (Test-ValidBar $riffRx $r)) { $badRiff  += ($s.Title + ':[' + $r + ']') } }
        foreach ($r in $s.Drums) { if (-not (Test-ValidBar $drumRx $r)) { $badDrum  += ($s.Title + ':[' + $r + ']') } }
        foreach ($r in $s.Lead)  { if (-not (Test-ValidBar $leadRx $r)) { $badLead  += ($s.Title + ':[' + $r + ']') } }
        foreach ($p in $s.Prog) {
            $v = 0
            if (-not [int]::TryParse($p, [ref]$v)) { $badProg += ($s.Title + ':[' + $p + ']') }
            elseif ($v -lt -12 -or $v -gt 12) { $badProg += ($s.Title + ':[' + $p + ']') }
        }
        if ($s.Prog.Count -ne $s.Riff.Count)  { $badBars += ($s.Title + ' prog=' + $s.Prog.Count + ' riff=' + $s.Riff.Count) }
        if ($s.Drums.Count -ne $s.Riff.Count) { $badBars += ($s.Title + ' drums=' + $s.Drums.Count) }
        if ($s.Lead.Count -ne $s.Riff.Count)  { $badBars += ($s.Title + ' lead=' + $s.Lead.Count) }
        if ($s.Riff.Count -lt 1) { $badBars += ($s.Title + ' empty riff') }
    }
    T-Is ($badRiff.Count -eq 0) 'every riff bar is 16 valid characters' ($badRiff -join ', ')
    T-Is ($badDrum.Count -eq 0) 'every drum bar is 16 valid characters' ($badDrum -join ', ')
    T-Is ($badLead.Count -eq 0) 'every lead bar is 16 valid characters' ($badLead -join ', ')
    T-Is ($badProg.Count -eq 0) 'every progression value parses as a small semitone offset' ($badProg -join ', ')
    T-Is ($badMeta.Count -eq 0) 'tempo and key of every song are sane' ($badMeta -join ', ')
    T-Is ($badBars.Count -eq 0) 'prog/drums/lead bar counts match the riff' ($badBars -join ', ')
    T-Is ($dupes.Count -eq 0) 'no duplicate song titles' ($dupes -join ', ')

    # ---------------- music, charts, audio --------------------------------
    $badEv = @(); $badCh = @(); $badAud = @(); $slow = @()
    $swTot = [Diagnostics.Stopwatch]::StartNew()
foreach ($s in $cat) {
        if (Test-CustomSong $s) { continue }
        $meta = Get-SongMeta $s
        if (-not ($meta.Bars -gt 0 -and $meta.LeadIn -gt 0 -and $meta.Total -gt 0 -and $meta.Total -lt 900)) {
            $badEv += ($s.Title + ' meta')
        }
        $evs = New-SongEvents $s $meta
        if ($evs.Count -lt 20) { $badEv += ($s.Title + ' only ' + $evs.Count + ' events') }
        $badt = $false
        foreach ($e in $evs) {
            if ($e.T -lt -0.001 -or $e.T -gt ($meta.Total + 0.01)) { $badt = $true; break }
            if ($e.Midi -lt 12 -or $e.Midi -gt 108) { $badt = $true; break }
            if ($e.Kind -lt 0 -or $e.Kind -gt 6) { $badt = $true; break }
        }
        if ($badt) { $badEv += ($s.Title + ' event range') }

        $sw1 = [Diagnostics.Stopwatch]::StartNew()
        $aud = [RockHero.Synth]::Render($evs, $meta.Total)
        $sw1.Stop()
        if ($aud.HasNaN) { $badAud += ($s.Title + ' NaN') }
        if ($aud.Peak -lt 8000) { $badAud += ($s.Title + ' too quiet peak=' + $aud.Peak) }
        if ($aud.Peak -gt 32767) { $badAud += ($s.Title + ' clipping peak=' + $aud.Peak) }
        if ($aud.Rms -lt 0.02 -or $aud.Rms -gt 0.65) { $badAud += ($s.Title + ' rms=' + [Math]::Round($aud.Rms, 4)) }
        if ($aud.Pcm.Length -lt 1000) { $badAud += ($s.Title + ' no audio') }
        if ($sw1.ElapsedMilliseconds -gt 6000) { $slow += ($s.Title + ' ' + $sw1.ElapsedMilliseconds + 'ms') }

        $prevCount = -1
        foreach ($dn in $script:Difficulty) {
            $ch = Get-Chart $s $meta $dn.Name
            if ($null -eq $ch -or $ch.Count -eq 0) { $badCh += ($s.Title + '/' + $dn.Name + ' empty'); continue }
            if ($ch.Count -lt $prevCount) { $badCh += ($s.Title + '/' + $dn.Name + ' fewer notes than easier tier') }
            $prevCount = $ch.Count
            $sorted = $true; $lastT = -1.0; $laneLast = @{}
            foreach ($n in $ch) {
                if ($n.T -lt $lastT) { $sorted = $false }
                $lastT = $n.T
                if ($n.Lane -lt 0 -or $n.Lane -ge 5) { $badCh += ($s.Title + '/' + $dn.Name + ' lane=' + $n.Lane); break }
                if ($n.T -lt ($meta.LeadIn - 0.01)) { $badCh += ($s.Title + '/' + $dn.Name + ' before count-in'); break }
                if ($n.T -gt $meta.Total) { $badCh += ($s.Title + '/' + $dn.Name + ' past end'); break }
                if ($n.Hold -lt 0 -or $n.Hold -gt 1.35) { $badCh += ($s.Title + '/' + $dn.Name + ' hold=' + $n.Hold); break }
                if ($laneLast.ContainsKey($n.Lane)) {
                    if (($n.T - $laneLast[$n.Lane]) -lt 0.045) { $badCh += ($s.Title + '/' + $dn.Name + ' unhittable stack in lane ' + $n.Lane); break }
                }
                $laneLast[$n.Lane] = $n.T
            }
            if (-not $sorted) { $badCh += ($s.Title + '/' + $dn.Name + ' chart not sorted') }
        }
    }
    $swTot.Stop()
    T-Is ($badEv.Count -eq 0) 'event lists are valid and inside the song bounds' ($badEv -join '; ')
    T-Is ($badAud.Count -eq 0) 'every song renders loud, clean, unclipped audio' ($badAud -join '; ')
    T-Is ($slow.Count -eq 0) 'no song takes longer than 6s to synthesise' ($slow -join ', ')
    T-Is ($badCh.Count -eq 0) 'every chart is sorted, in range and actually playable' ($badCh -join '; ')

    # ---------------- scoring ---------------------------------------------
    T-Is ((Get-Judgement 0.0)      -eq 'PERFECT') 'delta 0 is PERFECT'
    T-Is ((Get-Judgement 0.0479)   -eq 'PERFECT') 'inside the perfect window'
    T-Is ((Get-Judgement 0.0481)   -eq 'GREAT')   'just past perfect is GREAT'
    T-Is ((Get-Judgement -0.0479)  -eq 'PERFECT') 'negative delta is PERFECT (late keypress)'
    T-Is ((Get-Judgement -0.09)    -eq 'GREAT')   'late at the great boundary'
    T-Is ((Get-Judgement 0.1399)   -eq 'GOOD')    'just inside the good window'
    T-Is ((Get-Judgement 0.2)      -eq 'MISS')    'way off is a MISS'
    T-Is ((Get-BasePoints 'PERFECT') -eq 300) 'PERFECT is worth 300'
    T-Is ((Get-BasePoints 'NOPE')    -eq 0)   'unknown judgement is worth 0'
    T-Is ((Get-Mult 0)   -eq 1) 'combo 0 is x1'
    T-Is ((Get-Mult 9)   -eq 1) 'combo 9 is x1'
    T-Is ((Get-Mult 10)  -eq 2) 'combo 10 is x2'
    T-Is ((Get-Mult 25)  -eq 3) 'combo 25 is x3'
    T-Is ((Get-Mult 50)  -eq 4) 'combo 50 is x4'
    T-Is ((Get-Mult 100) -eq 5) 'combo 100 is x5'
    T-Is ((Get-Mult 9999) -eq 5) 'combo beyond 100 caps at x5'
    T-Is ((Get-Accuracy 0 0 0 0) -eq 0.0) 'accuracy of nothing is 0'
    T-Is ((Get-Accuracy 10 0 0 0) -eq 1.0) 'flawless accuracy is 1'
    T-Is ((Get-Accuracy 0 0 0 10) -eq 0.0) 'all miss accuracy is 0'
    T-Is ((Get-Rank 0.99) -eq 'S+') '99% is S+'
    T-Is ((Get-Rank 0.94) -eq 'S')  '94% is S'
    T-Is ((Get-Rank 0.89) -eq 'A')  '89% is A'
    T-Is ((Get-Rank 0.81) -eq 'B')  '81% is B'
    T-Is ((Get-Rank 0.71) -eq 'C')  '71% is C'
    T-Is ((Get-Rank 0.10) -eq 'D')  '10% is D'
    T-Is ((Get-Stars 1.0) -eq 5) 'perfect run is 5 stars'
    T-Is ((Get-Stars 0.0) -eq 0) 'empty run is 0 stars'
    T-Is ((Get-Stars 0.19) -eq 0) '19% is still 0 stars'
    T-Is ((Get-Stars 0.99) -eq 4) '99% is 4 stars (floor)'

    $s0 = $script:Catalog[0]
    $m0 = Get-SongMeta $s0
    $c0 = Get-Chart $s0 $m0 'Normal'
    $perf = Simulate-Play $c0 'perfect' 0.0
    $acc0 = Get-Accuracy $perf.P $perf.G $perf.Gd $perf.M
    T-Is ($perf.M -eq 0) 'a flawless run misses nothing'
    T-Is ($acc0 -eq 1.0) 'a flawless run has 100% accuracy'
    T-Is ((Get-Rank $acc0) -eq 'S+') 'a flawless run ranks S+'

    $idle = Simulate-Play $c0 'idle'
    T-Is ($idle.M -eq $c0.Count) 'standing still misses every note'
    T-Is ((Get-Rank (Get-Accuracy $idle.P $idle.G $idle.Gd $idle.M)) -eq 'D') 'standing still ranks D'

    $rnd = Simulate-Play $c0 'random' 0.03
    $tot = $rnd.P + $rnd.G + $rnd.Gd + $rnd.M
    T-Is ($tot -eq $c0.Count) 'random play still accounts for every note'

    $S = New-ScoreState $c0
    Add-Score $S 300 0.0
    T-Is ($S.Score -eq 300) 'score accumulates'
    $S.Combo = 50
    Add-Score $S 300 0.0
    T-Is ($S.Score -gt 300) 'the multiplier increases the score'
    $before = $S.Score
    Add-Score $S 0 0.0
    T-Is ($S.Score -eq $before) 'a zero-value hit adds nothing'

    # ---------------- game rules, driven head-less -----------------------
    # a deterministic six-note chart: one note a second, no holds

    # Judged lives on the note object, so every scenario needs its own chart
    $tcl = New-TestChart


    $tcl = New-TestChart


    $G1 = New-ScoreState $tcl
    for ($i = 0; $i -lt $tcl.Count; $i++) {
        Step-LaneCursors $G1 $tcl $tcl[$i].T
        Invoke-Hit $G1 $tcl $tcl[$i].T $tcl[$i].Lane
    }
    T-Is ($G1.Perfect -eq 6) 'flawless input registers six perfects' ("perfect=$($G1.Perfect)")
    T-Is ($G1.Miss -eq 0) 'flawless input registers no misses'
    T-Is ($G1.Combo -eq 6) 'flawless input builds a six combo' ("combo=$($G1.Combo)")
    T-Is ($G1.MaxCombo -eq 6) 'the best combo is remembered' ("max=$($G1.MaxCombo)")
    T-Is ($G1.Judged -eq 6) 'every note is accounted for exactly once' ("judged=$($G1.Judged)")
    T-Is ($G1.Score -gt 0) 'flawless input scores points' ("score=$($G1.Score)")
    T-Is ((Get-Rank (Get-Accuracy $G1.Perfect $G1.Great $G1.Good $G1.Miss)) -eq 'S+') 'a perfect run ranks S+'

    $tcl = New-TestChart

    $G1b = New-ScoreState $tcl
    Step-LaneCursors $G1b $tcl $tcl[0].T
    Invoke-Hit $G1b $tcl $tcl[0].T $tcl[0].Lane
    Invoke-Hit $G1b $tcl $tcl[0].T $tcl[0].Lane
    T-Is ($G1b.Judged -eq 1) 'the same note cannot be hit twice' ("judged=$($G1b.Judged)")

    $tcl = New-TestChart

    $G1c = New-ScoreState $tcl
    Step-LaneCursors $G1c $tcl $tcl[0].T
    Invoke-Hit $G1c $tcl $tcl[0].T (($tcl[0].Lane + 1) % $script:LANES)
    T-Is ($G1c.Judged -eq 0) 'striking the wrong lane does nothing'

    $tcl = New-TestChart

    $G1d = New-ScoreState $tcl
    Step-LaneCursors $G1d $tcl ($tcl[0].T - 0.5)
    Invoke-Hit $G1d $tcl ($tcl[0].T - 0.5) $tcl[0].Lane
    T-Is ($G1d.Judged -eq 0) 'a strike far outside the window does nothing'

    T-NoThrow { $G1x = New-ScoreState $tcl; Invoke-Hit $G1x $tcl 1.0 -1; Invoke-Hit $G1x $tcl 1.0 99 } 'stray lane numbers are ignored safely'
    T-NoThrow { $G1y = New-ScoreState (New-Object 'object[]' 0); Invoke-Hit $G1y (New-Object 'object[]' 0) 1.0 0; Step-Misses $G1y (New-Object 'object[]' 0) 9.0; Step-Holds $G1y 9.0 } 'an empty chart is safe'

    $tcl = New-TestChart

    $G2 = New-ScoreState $tcl
    Step-LaneCursors $G2 $tcl $tcl[0].T
    Invoke-Hit $G2 $tcl ($tcl[0].T + 0.060) $tcl[0].Lane
    T-Is ($G2.Great -eq 1 -and $G2.Perfect -eq 0) 'a late strike inside the great window is a GREAT' ("great=$($G2.Great)")

    $tcl = New-TestChart

    $G3 = New-ScoreState $tcl
    Step-LaneCursors $G3 $tcl $tcl[0].T
    Invoke-Hit $G3 $tcl ($tcl[0].T - 0.120) $tcl[0].Lane
    T-Is ($G3.Good -eq 1) 'a strike inside the good window is a GOOD' ("good=$($G3.Good)")

$tcl = New-TestChart

    $saveFail = $script:FailMisses
    try {
        $script:FailMisses = 4
        $G4 = New-ScoreState $tcl
        Step-Misses $G4 $tcl 99.0
        T-Is ($G4.Miss -eq 6) 'letting every note pass counts six misses' ("miss=$($G4.Miss)")
        T-Is ($G4.Failed) 'missing everything makes you rock out'
        T-Is ($G4.Combo -eq 0) 'missing everything leaves no combo'
        T-Is ($G4.Meter -eq 0) 'the rock meter bottoms out'

        # the limit the player picked decides when the song is lost.
        # a fresh chart per state: Judged lives on the note objects.
        $script:FailMisses = 3
        $tcl = New-TestChart
        $two = New-Object 'object[]' 2
        $two[0] = $tcl[0]; $two[1] = $tcl[1]
        $G4b = New-ScoreState $two
        Step-Misses $G4b $two 99.0
        T-Is ($G4b.Miss -eq 2) 'two misses were counted' ("miss=$($G4b.Miss)")
        T-Is (-not $G4b.Failed) 'staying under the miss limit keeps the song going'
        T-Is ((Get-StrikeLeft $G4b) -eq 1) 'the panel knows one strike is left' ("left=$(Get-StrikeLeft $G4b)")

        $script:FailMisses = 2
        $tcl = New-TestChart
        $two = New-Object 'object[]' 2
        $two[0] = $tcl[0]; $two[1] = $tcl[1]
        $G4c = New-ScoreState $two
        Step-Misses $G4c $two 99.0
        T-Is ($G4c.Failed) 'the miss that reaches the limit is the fatal one'

        $script:FailMisses = 0
        $tcl = New-TestChart
        $G4d = New-ScoreState $tcl
        Step-Misses $G4d $tcl 99.0
        T-Is ($G4d.Miss -eq 6) 'with no limit every note can still be missed' ("miss=$($G4d.Miss)")
        T-Is (-not $G4d.Failed) 'fail = never means you cannot rock out'
        T-Is ((Get-StrikeLeft $G4d) -eq -1) 'no limit reports no strikes at all'

        $script:FailMisses = 6
        $tcl = New-TestChart
        $G4e = New-ScoreState $tcl
        Step-Misses $G4e $tcl 99.0
        T-Is ($G4e.Failed) 'the sixth miss is fatal at a limit of six'
        $script:FailMisses = 7
        $tcl = New-TestChart
        $G4f = New-ScoreState $tcl
        Step-Misses $G4f $tcl 99.0
        T-Is (-not $G4f.Failed) 'the same six misses survive a limit of seven'
    } finally { $script:FailMisses = $saveFail }
    T-Is ($script:FailMisses -eq $saveFail) 'the self test leaves the miss limit as it was'
    T-Is ((Get-FailLabel 0) -like 'never*') 'a zero limit is spelled out in words'
    T-Is ((Get-FailLabel 16) -like '16*') 'a normal limit shows the number'

    $tcl = New-TestChart

    $G5 = New-ScoreState $tcl
    Step-Misses $G5 $tcl ($tcl[0].T + $script:WMiss - 0.01)
    T-Is ($G5.Miss -eq 0) 'a note still inside the miss window is hittable' ("miss=$($G5.Miss)")
    Step-Misses $G5 $tcl ($tcl[0].T + $script:WMiss + 0.01)
    T-Is ($G5.Miss -eq 1) 'a note is only missed once it is truly gone' ("miss=$($G5.Miss)")
    Step-Misses $G5 $tcl 99.0
    T-Is ($G5.Miss -eq 6 -and $G5.Idx -eq 6) 'the miss cursor walks the whole chart exactly once'

    # ---- overdrive -------------------------------------------------------
    $tcl = New-TestChart
    $G6 = New-ScoreState $tcl
    T-Is (-not (Invoke-Overdrive $G6 1.0)) 'overdrive refuses to fire on a cold meter'
    $G6.Meter = 1.0; $G6.OdReady = $true
    T-Is (Invoke-Overdrive $G6 1.0) 'overdrive fires when the meter is full'
    T-Is ($G6.Od -eq 8.0) 'overdrive lasts eight seconds'
    T-Is (-not (Invoke-Overdrive $G6 1.1)) 'overdrive cannot be stacked while it runs'
    $base0 = $G6.Score
    Step-LaneCursors $G6 $tcl $tcl[0].T
    Invoke-Hit $G6 $tcl $tcl[0].T $tcl[0].Lane
    $withOd = $G6.Score - $base0
    $tcl = New-TestChart
    $G6b = New-ScoreState $tcl
    Step-LaneCursors $G6b $tcl $tcl[0].T
    Invoke-Hit $G6b $tcl $tcl[0].T $tcl[0].Lane
    T-Is ($withOd -eq ($G6b.Score * 2)) 'overdrive doubles the score of a hit' ("od=$withOd plain=$($G6b.Score)")
    for ($f = 0; $f -lt 600; $f++) { Step-Meter $G6 $f }
    T-Is ($G6.Od -eq 0) 'overdrive eventually runs out'
    T-Is (-not $G6.OdReady) 'overdrive has to be earned again'

    # ---- hold notes ------------------------------------------------------
    # the loop always marks the lane down before striking it, so do the same
    $hcl = New-TestChart -WithHold
    $H1 = New-ScoreState $hcl
    Step-LaneCursors $H1 $hcl 2.0
    $H1.Down[2] = $true
    Invoke-Hit $H1 $hcl 2.0 2
    T-Is ($H1.Perfect -eq 1 -and $H1.Combo -eq 1) 'a normal note scores and builds combo'
    Step-Holds $H1 2.1
    T-Is ($H1.Combo -eq 1) 'a tapped note cannot be held'
    Step-LaneCursors $H1 $hcl 4.0
    $H1.Down[4] = $true
    Invoke-Hit $H1 $hcl 4.0 4
    T-Is ($H1.Combo -eq 1) 'striking a hold does not finish the combo yet' ("combo=$($H1.Combo)")
    T-Is ($null -ne $H1.HoldN[4]) 'the hold is now being tracked'
    Step-Holds $H1 4.30
    T-Is ($H1.Holds -eq 0 -and $H1.Combo -eq 1) 'holding early does nothing' ("holds=$($H1.Holds) combo=$($H1.Combo)")
    Step-Holds $H1 4.65
    T-Is ($H1.Holds -eq 1) 'holding to the end completes the hold' ("holds=$($H1.Holds)")
    T-Is ($H1.Combo -eq 2) 'completing a hold builds the combo' ("combo=$($H1.Combo)")
    T-Is ($null -eq $H1.HoldN[4]) 'a finished hold is cleared'
    T-Is ($H1.HoldDrop -eq 0) 'a finished hold is not a drop'

    $hcl = New-TestChart -WithHold
    $H2 = New-ScoreState $hcl
    Step-LaneCursors $H2 $hcl 4.0
    $H2.Down[4] = $true
    Invoke-Hit $H2 $hcl 4.0 4
    Step-Holds $H2 4.10
    $H2.Down[4] = $false
    $H2.Combo = 20
    Step-Holds $H2 4.20
    T-Is ($H2.HoldDrop -eq 1) 'letting go of a hold drops it' ("drops=$($H2.HoldDrop)")
    T-Is ($H2.Combo -eq 0) 'dropping a hold breaks the combo'
    T-Is ($H2.Judgement -eq 'DROPPED') 'a dropped hold says so on screen'
    T-Is ($null -eq $H2.HoldN[4]) 'a dropped hold is cleared'

    # a dropped hold burns a strike, exactly like a missed note
    $saveFail2 = $script:FailMisses
    try {
        $script:FailMisses = 1
        $hcl = New-TestChart -WithHold
        $H2b = New-ScoreState $hcl
        Step-LaneCursors $H2b $hcl 4.0
        $H2b.Down[4] = $true
        Invoke-Hit $H2b $hcl 4.0 4
        Step-Holds $H2b 4.10
        $H2b.Down[4] = $false
        Step-Holds $H2b 4.20
        T-Is ($H2b.HoldDrop -eq 1) 'the drop was counted'
        T-Is ($H2b.Failed) 'a dropped hold counts against the miss limit'

        $script:FailMisses = 2
        $hcl = New-TestChart -WithHold
        $H2c = New-ScoreState $hcl
        Step-LaneCursors $H2c $hcl 4.0
        $H2c.Down[4] = $true
        Invoke-Hit $H2c $hcl 4.0 4
        Step-Holds $H2c 4.10
        $H2c.Down[4] = $false
        Step-Holds $H2c 4.20
        T-Is (-not $H2c.Failed) 'one drop is survivable at a limit of two'

        $script:FailMisses = 0
        $hcl = New-TestChart -WithHold
        $H2d = New-ScoreState $hcl
        Step-LaneCursors $H2d $hcl 4.0
        $H2d.Down[4] = $true
        Invoke-Hit $H2d $hcl 4.0 4
        Step-Holds $H2d 4.10
        $H2d.Down[4] = $false
        Step-Holds $H2d 4.20
        T-Is (-not $H2d.Failed) 'with no limit even a drop cannot end the song'
    } finally { $script:FailMisses = $saveFail2 }

    $hcl = New-TestChart -WithHold
    $H3 = New-ScoreState $hcl
    Step-LaneCursors $H3 $hcl 4.0
    $H3.Down[4] = $true
    Invoke-Hit $H3 $hcl 4.0 4
    Step-Holds $H3 9.0
    T-Is ($null -eq $H3.HoldN[4]) 'a hold nobody finished eventually times out'
    T-Is ($H3.Holds -eq 1 -and $H3.HoldDrop -eq 0) 'a timed-out hold that reached its end still counts' ("holds=$($H3.Holds) drops=$($H3.HoldDrop)")

    # a real chart must exercise the hold code path
    $holdFound = $false
    foreach ($sg in $cat) {
        $mt = Get-SongMeta $sg
        foreach ($dn in $script:Difficulty) {
            $cc = Get-Chart $sg $mt $dn.Name
            foreach ($n in $cc) { if ($n.Hold -gt 0.06) { $holdFound = $true; break } }
            if ($holdFound) { break }
        }
        if ($holdFound) { break }
    }
    T-Is $holdFound 'at least one real chart produces hold notes'


    $oldW = $script:W; $oldH = $script:H
    $layoutOk = $true; $layoutMsg = ''
    foreach ($sz in @(@(40, 12), @(72, 24), @(104, 40), (300, 100))) {
        try {
            $script:W = $sz[0]; $script:H = $sz[1]
            $script:Base = $null
            Update-Base
            if ($script:PANELW -lt 12) { $layoutOk = $false; $layoutMsg = "panel too narrow at $($sz[0])x$($sz[1])" }
            $script:HITROW = [Math]::Max($script:HWTOP + 8, $script:H - 6)
            $dummy = New-GameFrame $S $s0 (Get-Difficulty 'Normal') 1.0 8.0 'off' $m0
            if ($null -eq $dummy) { $layoutOk = $false; $layoutMsg = 'renderer returned nothing' }
        } catch {
$layoutOk = $false
            $layoutMsg = "$($sz[0])x$($sz[1]): " + $_.Exception.Message + ' @ ' + (($_.ScriptStackTrace -split "`n")[0])
        }
    }
    T-Is $layoutOk 'the renderer survives tiny, minimum, normal and huge consoles' $layoutMsg
    $script:W = $oldW; $script:H = $oldH; $script:Base = $null; Set-Screen

    T-NoThrow { $null = Wrap-Runs 'abc' $null } 'Wrap-Runs handles a null run list'
    T-NoThrow { $rr = New-Object System.Collections.ArrayList; [void]$rr.Add(@(0, 2, 'X')); $null = Wrap-Runs 'abcdef' $rr } 'Wrap-Runs handles a run list'
    $escBefore = [RockHero.Synth]::SR
    T-Is ($escBefore -eq 32000) 'engine constant readable'

    $f0 = New-GameFrame $S $s0 (Get-Difficulty 'Normal') 0.0 8.0 'off' $m0
    T-Is ($f0.Count -eq $script:H) 'frame has exactly one line per screen row'
    $badLen = 0
    foreach ($l in $f0) { if ($null -eq $l) { $badLen++ } }
    T-Is ($badLen -eq 0) 'no null lines in a rendered frame'

    $midPos = $m0.Total * 0.5
    $S2 = New-ScoreState $c0
    $S2.WinLo = 0
    T-NoThrow { $null = New-GameFrame $S2 $s0 (Get-Difficulty 'Expert') $midPos 12.0 'waveOut' $m0 } 'mid-song frame renders'

    # frame with an empty chart must not divide by zero or read past the end
    $Sempty = New-ScoreState (New-Object 'object[]' 0)
    T-NoThrow { $null = New-GameFrame $Sempty $s0 (Get-Difficulty 'Normal') 1.0 8.0 'off' $m0 } 'frame renders with an empty chart'

    $d1 = $script:Ansi
    $script:Ansi = $true
    T-NoThrow { $null = New-GameFrame $S2 $s0 (Get-Difficulty 'Normal') $midPos 10.0 'off' $m0 } 'frame renders with ANSI colour on'
    $script:Ansi = $d1

    T-Is ((Get-Bar 0.5 20).Length -eq 20) 'progress bar is exactly the requested width'
    T-Is ((Get-Bar -3 20) -eq (Get-Bar 0 20)) 'progress bar survives a negative fraction'
    T-Is ((Get-Bar 5 20) -eq (Get-Bar 1 20)) 'progress bar survives a fraction above 1'
    T-Is ((Get-Bar 0 20) -notmatch [regex]::Escape([string]$script:G.barfull)) 'an empty bar is all empty cells'
    T-Is ((Get-Bar 1 20) -notmatch [regex]::Escape([string]$script:G.empty)) 'a full bar is all full cells'
    T-Is ((Get-Bar 0.5 2) -eq '') 'progress bar refuses a silly width'
    T-Is ((Get-Bar 0.5 0) -eq '') 'progress bar survives a zero width'

    # ---------------- difficulty fallback ----------------------------------
    $fb = Get-Chart $s0 $m0 'NoSuchMode'
    T-Is ($fb.Count -gt 0) 'an unknown difficulty falls back to a valid chart'
    $fbd = Get-Difficulty 'NoSuchMode'
    T-Is ($fbd.Name -eq 'Normal') 'an unknown difficulty name falls back to Normal'

    # ---------------- extreme tempo ---------------------------------------
    $t1 = (New-Song -Band 'x' -Title 't' -Style 't' -Bpm 30  -Riff @('0...0...4...4...') -Drums @('K...s...K...s...') -Lead @('0...4...3...2...') -Prog @('0'))
    $t2 = (New-Song -Band 'x' -Title 't' -Style 't' -Bpm 400 -Riff @('0...0...4...4...') -Drums @('K...s...K...s...') -Lead @('0...4...3...2...') -Prog @('0'))
    $extOk = $true; $extMsg = ''
    foreach ($t in @($t1, $t2)) {
        try {
            $mt = Get-SongMeta $t
            if (-not ($mt.Total -gt 0 -and $mt.Total -lt 4000 -and -not [double]::IsInfinity($mt.Step))) {
                $extOk = $false; $extMsg = 'meta out of range for bpm ' + $t.Bpm
            }
            $et = New-SongEvents $t $mt
            if ($et.Count -lt 5) { $extOk = $false; $extMsg = 'no events for bpm ' + $t.Bpm }
            $ct = Get-Chart $t $mt 'Normal'
            if ($ct.Count -eq 0) { $extOk = $false; $extMsg = 'no chart for bpm ' + $t.Bpm }
        } catch { $extOk = $false; $extMsg = $_.Exception.Message }
    }
    T-Is $extOk 'extreme tempos (30 and 400 BPM) build correctly' $extMsg

    # ---------------- input when redirected --------------------------------
    T-NoThrow { $null = Read-Keys } 'Read-Keys is safe when stdin is redirected'
    T-NoThrow { $k = Get-LaneFromKey ([pscustomobject]@{ Key = 'A'; KeyChar = [char]97 }); if ($k -ne 0) { throw 'lane map wrong for a' } } 'letter keys map to lanes'
    T-NoThrow { $k = Get-LaneFromKey ([pscustomobject]@{ Key = 'F1'; KeyChar = [char]0 }); if ($k -ne -1) { throw 'function keys must not map to a lane' } } 'function keys are ignored'
    T-NoThrow { $k = Get-LaneFromKey ([pscustomobject]@{ Key = 'D3'; KeyChar = [char]0 }); if ($k -ne 2) { throw 'numpad map wrong' } } 'numpad keys map to lanes'

    # ---------------- high scores -----------------------------------------
    $testDir = Join-Path ([IO.Path]::GetTempPath()) ('rh_test_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $testDir -Force | Out-Null
    $f = Join-Path $testDir 'hs.xml'
    $realScoreFile = $script:ScoreFile
    $script:ScoreFile = $f
    $script:High = @{}
    $saveOk = $true
    try {
        Set-ScoreFor 1 'Normal' ([pscustomobject]@{ Score = 12345; Rank = 'A'; Combo = 40; Acc = 0.9; When = 'now' }) | Out-Null
        if (-not (Save-Scores)) { $saveOk = $false; 'Save-Scores returned false' }
        $script:High = @{}
        Load-Scores
        if (-not (Get-ScoreFor 1 'Normal')) { $saveOk = $false }
    } catch { $saveOk = $false; $_.Exception.Message }

    Load-Scores
    T-Is $saveOk 'high scores survive a save/load round trip'
    $r1 = Get-ScoreFor 1 'Normal'
    T-Is ($null -ne $r1 -and $r1.Score -eq 12345) 'the loaded score is the right one'
    $replaced = Set-ScoreFor 1 'Normal' ([pscustomobject]@{ Score = 500; Rank = 'D'; Combo = 1; Acc = 0.1; When = 'now' })
    T-Is (-not $replaced) 'a worse score does not overwrite the record'
    T-Is ((Get-ScoreFor 1 'Normal').Score -eq 12345) 'the record still holds the best score'
    $replaced = Set-ScoreFor 1 'Normal' ([pscustomobject]@{ Score = 99999; Rank = 'S'; Combo = 99; Acc = 0.99; When = 'now' })
    T-Is $replaced 'a better score does overwrite the record'
    T-Is ($null -eq (Get-ScoreFor 99 'Normal')) 'an unknown song has no record'

    Set-Content -LiteralPath $f -Value 'this is not xml at all' -Encoding UTF8
    T-NoThrow { Load-Scores } 'a corrupted score file does not crash the game'
    T-Is ($script:High.Count -eq 0) 'a corrupted score file resets to empty'
    T-NoThrow { Save-Scores } 'saving over a corrupted file repairs it'
    T-Is ((Save-Scores -Path 'Z:\definitely\not\here\hs.xml') -eq $false) 'saving to an impossible path fails quietly'

    $script:ScoreFile = $realScoreFile
    $script:High = @{}
    Load-Scores
    Remove-Item -LiteralPath $testDir -Recurse -Force -ErrorAction SilentlyContinue

    # ---------------- the player's own music ------------------------------
    $ownRoot = Join-Path $testDir 'music'
    $ownCache = Join-Path $testDir 'owncharts'
    New-Item -ItemType Directory -Path $ownRoot -Force -ErrorAction SilentlyContinue | Out-Null
    New-Item -ItemType Directory -Path $ownCache -Force -ErrorAction SilentlyContinue | Out-Null
    $savedMusic = $script:MusicFolder
    $savedChart = $script:ChartFolder
    $script:MusicFolder = $ownRoot
    $script:ChartFolder = $ownCache

    try {
        # a four second click track, eight snare hits every 500 ms
        $evOwn = New-Object 'System.Collections.Generic.List[RockHero.Ev]'
        for ($i = 0; $i -lt 8; $i++) { $evOwn.Add((New-Ev ($i * 0.5) 0.12 3 38 0.95 0)) }
        $audOwn = [RockHero.Synth]::Render($evOwn, 4.0)
        $ownWav = Join-Path $ownRoot 'zz-selftest-click.wav'
        [IO.File]::WriteAllBytes($ownWav, [RockHero.Synth]::WrapWav($audOwn))

        $ownList = @(Get-CustomSongs)
        T-Is ($ownList.Count -eq 1) 'a wav in the music folder is picked up' ("count=$($ownList.Count)")
        T-Is ($ownList.Count -eq 1 -and $ownList[0].Custom) 'the picked up song is flagged as own music'
        T-Is ($ownList.Count -eq 1 -and $ownList[0].Band -eq 'my music') 'own music shows under its own band'

        $ownInfo = $null
        if (T-Try { [RockHero.Decode]::Info($ownWav) } 'wav header can be read') { $ownInfo = $script:TVal }
        T-Is ($null -ne $ownInfo -and $ownInfo.Ok) 'wav header is valid' ("err=" + $ownInfo.Error)
        T-Is ($ownInfo.Rate -eq 32000 -and $ownInfo.Channels -eq 1 -and $ownInfo.Bits -eq 16) 'wav format is reported' ("rate=$($ownInfo.Rate) ch=$($ownInfo.Channels) bits=$($ownInfo.Bits)")
        T-Is ([Math]::Abs($ownInfo.Seconds - 4.0) -lt 0.1) 'wav length is reported in seconds' ("sec=$($ownInfo.Seconds)")

        $ownSong = $ownList[0]
        $ownErr = ''
        $ownOnsets = $null
        if (T-Try { Get-CustomAnalysis $ownSong ([ref]$ownErr) } 'the analysis of own music does not crash') { $ownOnsets = $script:TVal }
        T-Is ($null -ne $ownOnsets -and @($ownOnsets).Count -ge 6) 'the click track yields onsets' ("onsets=$(if ($ownOnsets) { @($ownOnsets).Count } else { 0 })")
        $ownSorted = $true
        $ownInRange = $true
        $ownNear = 0
        if ($ownOnsets) {
            $prevT = -1.0
            foreach ($o in $ownOnsets) {
                if ($o.T -le $prevT) { $ownSorted = $false }
                $prevT = $o.T
                if ($o.T -lt 0.0 -or $o.T -gt $ownInfo.Seconds) { $ownInRange = $false }
                if ($o.Strength -lt 0.0 -or $o.Strength -gt 1.0) { $ownInRange = $false }
                for ($k = 0; $k -lt 8; $k++) {
                    if ([Math]::Abs($o.T - ($k * 0.5)) -lt 0.06) { $ownNear++; break }
                }
            }
        }
        T-Is $ownSorted 'onsets come out in ascending order'
        T-Is $ownInRange 'every onset is inside the recording and 0..1 strong'
        T-Is ($ownNear -ge 6) 'most onsets sit on the clicks that were actually rendered' ("near=$ownNear")
        T-Is ($ownSong.Bpm -ge 70 -and $ownSong.Bpm -le 180) 'the tempo guess lands in a sane range' ("bpm=$($ownSong.Bpm)")

        # the cache has to hand back exactly what the detector produced
        $ownSong2 = $ownList[0]
        $ownErr2 = ''
        $ownCached = Get-CustomAnalysis $ownSong2 ([ref]$ownErr2)
        $same = ($null -ne $ownCached -and @($ownCached).Count -eq @($ownOnsets).Count)
        if ($same) {
            for ($i = 0; $i -lt @($ownOnsets).Count; $i++) {
                if ([Math]::Abs([double]$ownCached[$i].T - [double]$ownOnsets[$i].T) -gt 0.002) { $same = $false; break }
            }
        }
        T-Is $same 'a second read returns the onsets from the cache unchanged'
        T-Is ($ownSong2.Bpm -eq $ownSong.Bpm -and [Math]::Abs($ownSong2.Duration - $ownSong.Duration) -lt 0.01) 'the cached tempo and length match'

        $ownMeta = Get-SongMeta $ownSong
        T-Is ([Math]::Abs($ownMeta.LeadIn - 2.0) -lt 0.001) 'own music gets a two second lead in'
        T-Is ($ownMeta.Total -gt $ownSong.Duration) 'own music lasts longer than the recording'

        $ownBad = @(); $ownCount = 0
        foreach ($dset in $script:Difficulty) {
            $c = @(Get-Chart $ownSong $ownMeta $dset.Name)
            $ownCount += $c.Count
            if ($c.Count -eq 0) { $ownBad += ($dset.Name + ' empty'); continue }
            $limit = 0.30
            if ($dset.Name -eq 'Normal') { $limit = 0.17 }
            elseif ($dset.Name -eq 'Hard') { $limit = 0.12 }
            elseif ($dset.Name -eq 'Expert') { $limit = 0.08 }
            $runLane = -1; $run = 0
            for ($i = 0; $i -lt $c.Count; $i++) {
                $nt = [double]$c[$i].T
                if ($nt -lt $ownMeta.LeadIn - 0.05 -or $nt -gt $ownMeta.Total) { $ownBad += ($dset.Name + ' note out of range') }
                if ($i -gt 0 -and ($nt - [double]$c[$i - 1].T) -lt $limit - 0.001) { $ownBad += ($dset.Name + ' notes too close') }
                $ln = [int]$c[$i].Lane
                if ($ln -lt 0 -or $ln -ge $script:LANES) { $ownBad += ($dset.Name + ' lane out of range') }
                if ($ln -eq $runLane) { $run++ } else { $run = 1; $runLane = $ln }
                if ($run -ge 4) { $ownBad += ($dset.Name + ' long repeat on one lane') }
            }
        }
        T-Is ($ownBad.Count -eq 0) 'generated charts for own music are playable' (($ownBad | Select-Object -Unique) -join ', ')
        T-Is ($ownCount -gt 0) 'own music produces notes' ("notes=$ownCount")

        # a recording with nothing to chart must say so instead of crashing
        $silence = New-Object 'byte[]' (44 + 32000 * 2)
        [Array]::Copy([RockHero.Synth]::WrapWav($audOwn), 0, $silence, 0, 44)
        $silWav = Join-Path $ownRoot 'zz-selftest-silence.wav'
        [IO.File]::WriteAllBytes($silWav, $silence)
        $silSong = @(Get-CustomSongs | Where-Object { $_.Title -like '*silence*' })[0]
        $silErr = ''
        $silOn = $null
        if (T-Try { Get-CustomAnalysis $silSong ([ref]$silErr) } 'a silent recording does not crash the analysis') { $silOn = $script:TVal }
        T-Is ($null -eq $silOn -and $silErr -ne '') 'a silent recording reports why it has no chart' ("err=$silErr")
        T-Is (@(Get-Chart $silSong $ownMeta 'Easy').Count -eq 0) 'a silent recording charts as empty'

        # playing the recording has to drive the clock
        $pp = [RockHero.Player]::new()
        $ownOk = $false
        if (T-Try { $pp.PlayFile($ownWav) } 'the player opens a wav from disk') { $ownOk = $script:TVal }
        T-Is ($ownOk -and $pp.Mode -eq 'file') 'the player reports file mode' ("ok=$ownOk mode=$($pp.Mode)")
        T-Is ([Math]::Abs($pp.Duration - $ownInfo.Seconds) -lt 0.2) 'the player reports the length of the recording' ("dur=$($pp.Duration)")
        $posA = $pp.Position
        Start-Sleep -Milliseconds 400
        $posB = $pp.Position
        T-Is ($posB -gt $posA) 'the position of a file moves forward while it plays' ("$posA -> $posB")
        T-NoThrow { $pp.Stop() } 'stopping a file leaves the clock at zero'
        $pp.Dispose()

        # a broken path has to fail instead of taking the song down
        $badPath = Join-Path $ownRoot 'zz-selftest-missing.wav'
        $pb2 = [RockHero.Player]::new()
        T-Is ((-not $pb2.PlayFile($badPath))) 'a missing file fails cleanly'
        T-Is ($pb2.LastError -ne '') 'a missing file says what went wrong'
        $pb2.Dispose()

        T-NoThrow { [RockHero.Decode]::Info((Join-Path $ownRoot 'zz-selftest-nope.wav')) } 'reading a missing wav does not crash'
        T-Is (-not [RockHero.Decode]::Info((Join-Path $ownRoot 'zz-selftest-nope.wav')).Ok) 'a missing wav is reported as unreadable'
        $notAudio = Join-Path $ownRoot 'zz-selftest-notes.txt'
        Set-Content -LiteralPath $notAudio -Value 'plain text, not audio at all' -Encoding UTF8
        T-Is (-not [RockHero.Decode]::Info($notAudio).Ok) 'a file that is not audio is rejected'
        T-NoThrow { [RockHero.Decode]::Analyze($notAudio, 5.0, 60.0, 1.2) } 'analysing something that is not audio does not crash'
        T-Is (@([RockHero.Decode]::Analyze($notAudio, 5.0, 60.0, 1.2)).Length -eq 0) 'something that is not audio has no onsets'
    } catch {
        T-Result $false 'own music section runs to the end' $_.Exception.Message
    } finally {
        $script:MusicFolder = $savedMusic
        $script:ChartFolder = $savedChart
        Remove-Item -LiteralPath $ownRoot -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $ownCache -Recurse -Force -ErrorAction SilentlyContinue
    }

    # ---------------- summary ---------------------------------------------
    $tot = $script:TPass + $script:TFail
    Write-Host ''
    if ($script:TFail -eq 0) {
        Write-Host ("  ALL {0} TESTS PASSED   (total synthesising time {1:N1}s)" -f $tot, $swTot.Elapsed.TotalSeconds) -ForegroundColor Green
    } else {
        Write-Host ("  {0} of {1} TESTS FAILED" -f $script:TFail, $tot) -ForegroundColor Red
    }
    Write-Host ''
    return [pscustomobject]@{ Pass = $script:TPass; Fail = $script:TFail; Total = $tot }
}

function Run-SelfTestScreen {
    $null = Invoke-SelfTest
    Set-Screen
    $items = @('BACK')
    $null = Show-Menu -Title 'SELF-TEST COMPLETE' -Sub ('{0} passed, {1} failed' -f $script:TPass, $script:TFail) -Items $items `
        -DrawRow {
            param($i, $s)
            if ($s) { return $script:C.Sel + $script:G.arrow + ' BACK' + $script:C.R }
            return '   BACK'
        } `
        -DrawFoot { $script:C.Label + 'ESC to go back' + $script:C.R }
}

# ============================================================================
#  MAIN
# ============================================================================
function Show-StartupError {
    param([string]$Msg)
    Write-Host ''
    Write-Host '  ROCK HERO cannot start.' -ForegroundColor Red
    Write-Host ('  ' + $Msg) -ForegroundColor Yellow
    Write-Host ''
}

function Main {
    Get-DataDir | Out-Null

    try {
        $ok = Initialize-Engine
    } catch {
        Show-StartupError ("The audio engine failed to compile: " + $_.Exception.Message)
        return 2
    }
    if (-not $ok) {
        Show-StartupError 'The audio engine could not be loaded.'
        return 2
    }

$script:Catalog = Get-Catalog
    try { $script:Catalog = @($script:Catalog + @(Get-CustomSongs)) } catch { }
    New-GlyphTable
    New-ColorTable
    Load-Settings
    Apply-Volume
    Load-Scores

    # ---- non interactive modes ------------------------------------------
if ($SelfTest) {
        $r = Invoke-SelfTest
        if ($r.Fail -gt 0) { return 1 }
        return 0
    }

    if ($AudioDiag) {
        return Invoke-AudioDiag
    }

    if ($ListSongs) {
        Write-Host ''
        Write-Host '  ROCK HERO - song list' -ForegroundColor Yellow
        Write-Host ('  {0} songs from {1} bands' -f $script:Catalog.Count, (Get-BandCount)) -ForegroundColor DarkGray
        Write-Host ''
        $i = 0
        foreach ($s in $script:Catalog) {
            $i++
            Write-Host ('  {0,3}. {1,-18} {2,-24} {3,4} bpm  {4}' -f $i, $s.Band, $s.Title, $s.Bpm, $s.Style)
        }
        Write-Host ''
        Write-Host '  All riffs are original compositions written in the style of each band.' -ForegroundColor DarkGray
        Write-Host ''
        return 0
    }

    if ($Benchmark) {
        Write-Host ''
        Write-Host '  ROCK HERO - synthesis benchmark' -ForegroundColor Yellow
        Write-Host ''
        Write-Host ('  {0,-18} {1,-24} {2,7} {3,10} {4,9} {5,8}' -f 'BAND', 'TITLE', 'BPM', 'SECONDS', 'RENDER', 'SIZE') -ForegroundColor DarkGray
        $tot = 0.0
        foreach ($s in $script:Catalog) {
            $m = Get-SongMeta $s
            $sw = [Diagnostics.Stopwatch]::StartNew()
            $a = [RockHero.Synth]::Render((New-SongEvents $s $m), $m.Total)
            $sw.Stop()
            $tot += $sw.Elapsed.TotalSeconds
            Write-Host ('  {0,-18} {1,-24} {2,7} {3,10:N1} {4,8}ms {5,7:N1}MB' -f $s.Band, $s.Title, $s.Bpm, $m.Total, $sw.ElapsedMilliseconds, ($a.Pcm.Length / 1MB))
        }
        Write-Host ''
        Write-Host ('  total render time {0:N2}s' -f $tot) -ForegroundColor Green
        Write-Host ''
        return 0    }

    if ($DumpWav -gt '') {
        if ($DumpSong -lt 1 -or $DumpSong -gt $script:Catalog.Count) {
            Show-StartupError ("-DumpSong must be between 1 and " + $script:Catalog.Count)
            return 2
        }
        $s = $script:Catalog[$DumpSong - 1]
        $m = Get-SongMeta $s
        Write-Host ''
        Write-Host ("  synthesising '{0} - {1}' ..." -f $s.Band, $s.Title)
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $a = [RockHero.Synth]::Render((New-SongEvents $s $m), $m.Total)
        $sw.Stop()
        $bytes = [RockHero.Synth]::WrapWav($a)
        try {
            $dir = Split-Path -Parent $DumpWav
            if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            [IO.File]::WriteAllBytes($DumpWav, $bytes)
            Write-Host ('  wrote {0}  ({1:N1}s of audio, {2:N1}MB, peak {3}, rms {4:N3})' -f $DumpWav, $a.Seconds, ($bytes.Length / 1MB), $a.Peak, $a.Rms)
            Write-Host ('  synthesis took {0}ms' -f $sw.ElapsedMilliseconds)
            return 0
        } catch {
            Show-StartupError ("Could not write '$DumpWav': " + $_.Exception.Message)
            return 2
        }
    }

    # ---- interactive -----------------------------------------------------
    if ([RockHero.Term]::IsRedirected()) {
        Show-StartupError 'Input is redirected, so the keyboard cannot be read. Run rockhero.ps1 in a normal PowerShell console (or Windows Terminal).'
        return 2
    }

    $rc = 0
    try {
        try { [Console]::CursorVisible = $false } catch { }
        try { [Console]::TreatControlCAsInput = $true } catch { }
        try { $script:Ansi = [RockHero.Term]::TryEnableAnsi() } catch { $script:Ansi = $false }
        try { [Console]::Title = 'ROCK HERO - PowerShell' } catch { }
        try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

        if (-not $script:NoAudio) {
            try {
                $script:Sfx = [RockHero.Player]::new()
                $script:Sfx.Volume = $script:Vol
                $script:Music = [RockHero.Player]::new()
                $script:Music.Volume = $script:Vol
            } catch {
                $script:Sfx = $null; $script:Music = $null
                $script:NoAudio = $true
            }
        }

        Set-Screen
        while ($script:W -lt $script:MINW -or $script:H -lt $script:MINH) {
            $lines = New-BlankLines
            $r1 = [Math]::Max(0, [Math]::Min(6, $script:H - 2))
            Set-Cell $lines $r1 2 ($script:C.Warn + 'Your console is only ' + $script:W + 'x' + $script:H + ' characters.' + $script:C.R) 60
            Set-Cell $lines ($r1 + 1) 2 ($script:C.Label + 'At least ' + $script:MINW + 'x' + $script:MINH + ' is needed. Enlarge the window and press ENTER.' + $script:C.R) 80
            Write-Screen $lines
            $k = Wait-Key
            if ($null -ne $k -and $k.Key -eq 'Escape') { return 2 }
            Set-Screen
        }

        $script:CursorSave = $true
        while ($true) {
            $r = Invoke-MainMenu
            if ($r -eq 'quit') { break }
        }
    } catch {
        Write-Host ''
        Write-Host ('  unexpected error: ' + $_.Exception.Message) -ForegroundColor Red
        Write-Host ($_.ScriptStackTrace) -ForegroundColor DarkGray
        Write-Host ''
        Write-Host '  The window stays open so the message can be read. Press ENTER to close.' -ForegroundColor DarkGray
        try { [Console]::TreatControlCAsInput = $false } catch { }
        try { [Console]::CursorVisible = $true } catch { }
        try { $null = [Console]::ReadLine() } catch { }
        $rc = 3
    } finally {
        try { if ($script:Music) { $script:Music.Stop() } } catch { }
        try { if ($script:Sfx) { $script:Sfx.Stop() } } catch { }
        try { [Console]::CursorVisible = $true } catch { }
        try { [Console]::TreatControlCAsInput = $false } catch { }
        try { [Console]::Out.Flush() } catch { }
    }
    Write-Host ''
    Write-Host '  Rock out.' -ForegroundColor Yellow
    Write-Host ''
    return $rc
}

$exitCode = Main
if (-not $NoAudio) {
    try { if ($script:Music) { $script:Music.Dispose() } } catch { }
    try { if ($script:Sfx) { $script:Sfx.Dispose() } } catch { }
}
exit $exitCode
