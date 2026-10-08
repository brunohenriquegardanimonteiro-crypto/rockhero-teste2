# ============================================================================
#  SCORE STATE
# ============================================================================
$script:LaneKeys = @{
    '1' = 0; '2' = 1; '3' = 2; '4' = 3; '5' = 4
    'A' = 0; 'S' = 1; 'D' = 2; 'F' = 3; 'G' = 4
}

function New-ScoreState {
    param($Chart)
    $fl = New-Object 'double[]' $script:LANES
    $cn = New-Object 'int[]'    $script:LANES
    $hn = New-Object 'object[]' $script:LANES
    $dn = New-Object 'bool[]'   $script:LANES
    for ($i = 0; $i -lt $script:LANES; $i++) { $fl[$i] = -99.0 }
    [pscustomobject]@{
        Chart = $Chart
        Score = 0; Combo = 0; MaxCombo = 0; Idx = 0; WinLo = 0
        Perfect = 0; Great = 0; Good = 0; Miss = 0
        Holds = 0; HoldDrop = 0; Judged = 0
        Meter = 0.0; Od = 0.0; OdReady = $false
        Judgement = ''; JudAt = -999.0; JudColor = 'Nrm'
        Flash = $fl; Cur = $cn; HoldN = $hn; Down = $dn
        Done = $false; Failed = $false
    }
}

function Add-Score {
    param($S, [int]$Base, [double]$Delta)
    $mult = Get-Mult $S.Combo
    $od = 1
    if ($S.Od -gt 0) { $od = 2 }
    $bonus = 1.0 + [Math]::Min(0.5, [Math]::Abs($Delta) * 0.6)
    $S.Score += [int][Math]::Round($Base * $mult * $od * $bonus)
}

function Get-LaneFromKey {
    param($KeyInfo)
    switch ($KeyInfo.Key) {
        'D1' { return 0 }
        'D2' { return 1 }
        'D3' { return 2 }
        'D4' { return 3 }
        'D5' { return 4 }
    }
    $ch = [string]$KeyInfo.KeyChar
    if ($ch.Length -eq 1 -and $script:LaneKeys.ContainsKey($ch)) { return $script:LaneKeys[$ch] }
    return -1
}

# ============================================================================
#  FRAME RENDERING
# ============================================================================
# Wrap a plain string with colour escape runs.  String.Insert counts RAW
# characters, so the line handed in must not carry an escape prefix yet -
# otherwise every run lands to the left of its column and slices the escape
# sequence itself apart, which is what used to shred the highway.
function Wrap-Runs {
    param([string]$Line, $Runs)
    if (-not $script:Ansi) { return $Line }
    if ($null -eq $Runs -or $Runs.Count -eq 0) { return $Line }
    for ($i = $Runs.Count - 1; $i -ge 0; $i--) {
        $r = $Runs[$i]
        $Line = $Line.Insert($r[0] + $r[1], $script:C.Dim)
        $Line = $Line.Insert($r[0], $r[2])
    }
    return $Line
}

function Set-Cell {
    # $Plain is kept for the call sites but no longer trusted: a wrong guess left
    # rows a few columns short or overlong, and an overlong row wraps and shakes
    # the console.
    param([string[]]$Lines, [int]$Row, [int]$X, [string]$Text, [int]$Plain, [int]$Width = 0)
    if ($Row -lt 0 -or $Row -ge $Lines.Count) { return }
    if ($Width -le 0) { $Width = $script:W }
    if ($X -lt 0) { $X = 0 }
    if ($X -gt $Width) { $X = $Width }
    # count what the console will really print: an escape run takes no column
    $vis = $Text.Length
    if ($Text.IndexOf([char]27) -ge 0) { $vis = ([regex]::Replace($Text, $script:AnsiRun, '')).Length }
    $pad = $Width - $X - $vis
    if ($pad -lt 0) { $pad = 0 }
    $Lines[$Row] = (' ' * $X) + $Text + (' ' * $pad)
}

function New-GameFrame {
    param($S, $Song, $Df, [double]$Pos, [double]$InvRow, [string]$AudioMode, $Meta)

    $w   = $script:W; $h = $script:H; $c = $script:C; $g = $script:G
    $hit = $script:HITROW; $top = $script:HWTOP
    # the hit row is cached from the last Set-Screen: a smaller screen (or a
    # resize) must not push it past the last line or the frame throws
    if ($hit -ge $h) { $hit = $h - 1 }
    if ($hit -lt 0)  { $hit = 0 }
    if ($top -ge $hit) { $top = $hit }
    if ($top -lt 0)   { $top = 0 }
    # panel seam: on a very narrow screen the highway would leave the panel with
    # no room at all, which used to compute a negative width and throw
    $px = $script:PANELX
    if ($px -gt ($w - 8)) { $px = [Math]::Max(0, $w - 8) }
    $pwTot = $w - $px
    if ($pwTot -lt 0) { $pwTot = 0 }
    $pw = $script:PANELW
    if ($pw -gt $pwTot) { $pw = $pwTot }
    if ($pw -lt 4)      { $pw = [Math]::Min(4, $pwTot) }
    $lines = New-BlankLines
    $chart = $S.Chart
    $count = $chart.Count
    $nRows = $hit - $top + 1
    if ($nRows -lt 1) { $nRows = 1 }
    $spr = 1.0 / $InvRow          # seconds per highway row

    # ---------------- highway ---------------------------------------------
    $bufs = New-Object 'char[][]' $nRows
    $runs = New-Object 'object[]' $nRows
    for ($i = 0; $i -lt $nRows; $i++) {
        $baseRow = [string](Get-BaseRow ($top + $i))
        # a cached base row can be empty (the hit row moved after the cache was
        # built) and writing a note into an empty array throws: never go narrower
        # than the highway seam
        if ($baseRow.Length -lt $px) { $baseRow = $baseRow.PadRight($px) }
        $bufs[$i] = [char[]]$baseRow
        $runs[$i] = $null
    }

    $winLo = $S.WinLo
    if ($winLo -lt 0) { $winLo = 0 }
    if ($winLo -gt $count) { $winLo = $count }

    # Walk the chart once and drop every note into the row it actually belongs
    # to.  The old loop went row by row and painted whatever note fell in that
    # row's time window, so notes never landed on their own row: they flashed
    # near the hit line and the highway looked empty.
    $reach = ($hit - 1 - $top) * $InvRow          # seconds a note is visible
    if ($reach -le 0) { $reach = 1.0 }
    $tShow = $Pos + $reach + $spr
    $tGone = $Pos - 0.35
    while ($winLo -lt $count -and $chart[$winLo].T -lt $tGone) { $winLo++ }

    $j = $winLo
    while ($j -lt $count -and $chart[$j].T -le $tShow) {
        $n = $chart[$j]; $j++
        if ($n.Lane -lt 0 -or $n.Lane -ge $script:LANES) { continue }
        $col = $script:HWLEFT + ($n.Lane * $script:LW) + 2
        if ($col + 1 -ge $w) { continue }
        $hr = [int][Math]::Round($hit - 1 - (($n.T - $Pos) * $InvRow))
        if ($hr -lt ($top - 1) -or $hr -gt ($hit + 3)) { continue }
        $idx = $hr - $top
        if ($idx -lt 0) { $idx = 0 }
        if ($idx -ge $nRows) { $idx = $nRows - 1 }
        $buf = $bufs[$idx]

        if ($n.Hold -gt 0.06) {
            $hr2 = [int][Math]::Round($hit - 1 - (($n.T + $n.Hold - $Pos) * $InvRow))
            if ($hr2 -lt $hr) { $hr2 = $hr }
            for ($q = $hr2; $q -le $hr; $q++) {
                $qi = $q - $top
                if ($qi -lt 0) { $qi = 0 }
                if ($qi -ge $nRows) { $qi = $nRows - 1 }
                $qb = $bufs[$qi]
                $qb[$col]     = [char]$g.hold[0]
                $qb[$col + 1] = [char]$g.hold[0]
            }
        }
        $past = ($n.T -lt ($Pos - 0.05))
        $ch = $g.hold[0]
        if (-not $past) { $ch = $g.note[0] }
        $buf[$col]     = [char]$ch[0]
        $buf[$col + 1] = [char]$ch[0]
        if (-not $n.Judged) {
            $col2 = $c.Nrm
            if ($past) { $col2 = $c.Miss }
            elseif ($n.Hold -gt 0.06) { $col2 = $c.Hold }
            if ($null -eq $runs[$idx]) { $runs[$idx] = New-Object System.Collections.ArrayList }
            [void]$runs[$idx].Add(@($col, 2, $col2))
        }
    }
    $S.WinLo = $winLo

    # receptor flash
    $recBuf = $bufs[$hit - $top]
    $recRuns = $null
    for ($l = 0; $l -lt $script:LANES; $l++) {
        $age = $Pos - $S.Flash[$l]
        if ($age -ge 0 -and $age -lt 0.17) {
            $x = $script:HWLEFT + ($l * $script:LW)
            for ($q = 1; $q -lt $script:LW; $q++) {
                if (($x + $q) -lt $w) { $recBuf[$x + $q] = [char]$g.note[0] }
            }
            if ($null -eq $recRuns) { $recRuns = New-Object System.Collections.ArrayList }
            [void]$recRuns.Add(@($x, $script:LW, $c.Od))
        }
    }

    for ($i = 0; $i -lt $nRows; $i++) {
        $r = $top + $i
        $content = -join $bufs[$i]
        $plain = $content.Length
        # the highway owns only the columns left of the panel: clamp to that
        # seam so the row can be concatenated with the panel row as it is
        if ($plain -gt $px) { $content = $content.Substring(0, $px) }
        elseif ($plain -lt $px) { $content = $content + (' ' * ($px - $plain)) }
        $rowRuns = $runs[$i]
        if ($r -eq $hit) { $rowRuns = $recRuns }
        $line = Wrap-Runs $content $rowRuns
        if ($script:Ansi) { $line = $c.Dim + $line + $c.R }
        $lines[$r] = $line
    }

    # ---------------- header -----------------------------------------------
    $band = $Song.Band; if ($band.Length -gt 24) { $band = $band.Substring(0, 24) }
    $ttl  = $Song.Title; if ($ttl.Length -gt 26) { $ttl = $ttl.Substring(0, 26) }
    $scoreTxt = '{0,9}' -f $S.Score
    # visible width of the header text: 'ROCK HERO' + '   ' + band + ' - ' + title
    $headPlain = 9 + 3 + $band.Length + 3 + $ttl.Length
    $headTxt = $c.Title + 'ROCK HERO' + $c.R + '   ' + $c.Val + $band + $c.R + ' - ' + $c.Nrm + $ttl + $c.R
    $set = $headTxt
    if ($headPlain + $scoreTxt.Length -lt $w) {
        $set = $headTxt + (' ' * ($w - $headPlain - $scoreTxt.Length)) + $c.Title + $scoreTxt + $c.R
    }
    Set-Cell $lines 0 0 $set $script:W
    Set-Cell $lines 1 0 ($c.Dim + ('  ' + ($g.top * [Math]::Max(0, $w - 4))) + $c.R) $script:W

    # ---------------- right panel ------------------------------------------
    # The panel gets its own buffer and its own local coordinates: Set-Cell
    # rewrites a whole row, so drawing the panel straight onto the frame used to
    # wipe the lanes and every note that scrolled past those rows.
    $prows = New-Object 'string[]' $h
    $pblank = ' '
    if ($pwTot -gt 0) { $pblank = ' ' * $pwTot }
    for ($i = 0; $i -lt $h; $i++) { $prows[$i] = $pblank }
    $mult = Get-Mult $S.Combo
    $acc  = Get-Accuracy $S.Perfect $S.Great $S.Good $S.Miss
    $leftN = $count - $S.Idx

    Set-Cell $prows 4  0 ($c.Label + 'SCORE' + $c.R) (6) $pwTot
    Set-Cell $prows 5  0 ($c.Val + ('{0,9}' -f $S.Score) + $c.R) (9) $pwTot

    $comboTxt = '    -'
    if ($S.Combo -gt 0) { $comboTxt = '{0,5}' -f $S.Combo }
    Set-Cell $prows 7  0 ($c.Label + 'COMBO' + $c.R) (5) $pwTot
    Set-Cell $prows 8  0 ($c.Val + $comboTxt + $c.R + '  ' + $c.Title + ('x{0}' -f $mult) + $c.R) (5 + 2 + 2) $pwTot
    Set-Cell $prows 9  0 ($c.Label + ('max {0,-5} acc {1,5:N1}%' -f $S.MaxCombo, ($acc * 100)) + $c.R) (21) $pwTot

    Set-Cell $prows 11 0 ($c.Label + 'ROCK' + $c.R) (4) $pwTot
    $barCol = $c.Bar
    if ($S.Od -gt 0) { $barCol = $c.Od }
    Set-Cell $prows 12 0 ($barCol + (Get-Bar $S.Meter $pw) + $c.R) $pw $pwTot
    Set-Cell $prows 13 0 ($c.Label + ('perfect {0,-5} great {1}' -f $S.Perfect, $S.Great) + $c.R) (20) $pwTot
    Set-Cell $prows 14 0 ($c.Label + ('good {0,-10} miss {1}' -f $S.Good, $S.Miss) + $c.R) (20) $pwTot
    Set-Cell $prows 15 0 ($c.Label + ('holds {0,-9} drops {1}' -f $S.Holds, $S.HoldDrop) + $c.R) (20) $pwTot

    Set-Cell $prows 17 0 ($c.Label + 'NOTES LEFT' + $c.R) (10) $pwTot
    Set-Cell $prows 18 0 ($c.Val + ('{0,6}' -f $leftN) + $c.R + '  ' + $c.Label + $Df.Pt + $c.R) (8 + $Df.Pt.Length) $pwTot

    # strikes left: how many more misses this song tolerates before the fail
    $used = $S.Miss + $S.HoldDrop
    if ($script:FailMisses -le 0) {
        Set-Cell $prows 19 0 ($c.Label + 'FAIL ON' + $c.R + '  ' + $c.Ok + 'never' + $c.R) (18) $pwTot
    } else {
        $leftStrikes = $script:FailMisses - $used
        if ($leftStrikes -lt 0) { $leftStrikes = 0 }
        $stCol = if ($leftStrikes -le 3) { $c.Warn } else { $c.Val }
        $stTxt = ('{0,4} of {1}' -f $leftStrikes, $script:FailMisses)
        Set-Cell $prows 19 0 ($c.Label + 'MISSES LEFT' + $c.R + '  ' + $stCol + $stTxt + $c.R) (11 + $stTxt.Length) $pwTot
    }

    if ($AudioMode -eq 'off' -or $AudioMode -eq 'none' -or $AudioMode -eq '') {
        Set-Cell $prows 20 0 ($c.Warn + 'AUDIO OFF' + $c.R) (9) $pwTot
    } elseif ($S.Od -gt 0) {
        Set-Cell $prows 20 0 ($c.Od + ('OVERDRIVE {0:N1}s' -f $S.Od) + $c.R) (15) $pwTot
    } elseif ($S.OdReady) {
        Set-Cell $prows 20 0 ($c.Ok + 'SPACE = OVERDRIVE' + $c.R) (18) $pwTot
    } else {
        Set-Cell $prows 20 0 ($c.Dim + ('audio: ' + $AudioMode) + $c.R) (6 + $AudioMode.Length) $pwTot
    }

    # ---------------- count-in ---------------------------------------------
    if ($Pos -lt $Meta.LeadIn -and $count -gt 0) {
        $beat = $Meta.Beat
        $left2 = [Math]::Ceiling(($Meta.LeadIn - $Pos) / $beat)
        $msg = 'GET READY'
        $col = $c.Title
        if ($left2 -le 0)      { $msg = 'ROCK!'; $col = $c.Od }
        elseif ($left2 -le 3) { $msg = [string][int]$left2; $col = $c.Sel }
        $block = $g.empty * $pw
        for ($k = $top; $k -le ($top + 4); $k++) {
            Set-Cell $prows $k 2 $block $pw $pwTot
        }
        $mid = $top + 2
        $mx = 2 + [int](($pw - $msg.Length) / 2)
        if ($mx -lt 0) { $mx = 0 }
        Set-Cell $prows $mid $mx ($col + $msg + $c.R) $msg.Length $pwTot
    }

    # ---- compose: lanes + notes on the left, panel on the right -------------
    # both halves are padded to a fixed visible width and carry no escape run
    # across the seam, so this is a plain concatenation: no per-frame scanning.
    for ($r = $top; $r -le $hit; $r++) {
        if ($r -lt 0 -or $r -ge $h) { continue }
        $lines[$r] = $lines[$r] + $prows[$r]
    }

    # ---------------- bottom rows ------------------------------------------
    $r1 = $hit + 1
    if ($r1 -lt $h) {
        $keysTxt = ''
        $keysPlain = 0
        for ($l = 0; $l -lt $script:LANES; $l++) {
            $keysTxt  += $c.Label + ([string]($l + 1)) + $c.R + $c.Val + $g.note + $c.R + '  '
            $keysPlain += 4
        }
        $keysTxt   += $c.Dim + 'or ' + $c.R + $c.Label + 'A S D F G' + $c.R
        $keysPlain += 12
        Set-Cell $lines $r1 $script:HWLEFT $keysTxt $keysPlain
    }

    $r2 = $hit + 2
    if ($r2 -lt $h) {
        $age = $Pos - $S.JudAt
        if ($age -ge 0 -and $age -lt 0.65 -and $S.Judgement -gt '') {
            $col = $c[$S.JudColor]
            if ($null -eq $col) { $col = $c.Nrm }
            $txt = $col + '  ' + $S.Judgement + '  ' + $c.R + $c.Dim + 'x' + $mult + $c.R
            Set-Cell $lines $r2 ($script:HWLEFT + 6) $txt (4 + $S.Judgement.Length + 2)
        } else {
            Set-Cell $lines $r2 0 '' 0
        }
    }

    $r3 = $hit + 3
    if ($r3 -lt $h) {
        $frac = 0.0
        if ($Meta.Total -gt 0) { $frac = $Pos / $Meta.Total }
        if ($frac -lt 0) { $frac = 0 }
        if ($frac -gt 1) { $frac = 1 }
        $bw = $w - 22
        if ($bw -lt 8) { $bw = 8 }
        $barCol = $c.Bar
        if ($S.Od -gt 0) { $barCol = $c.Od }
        $pct = '{0,4:N0}%' -f ($frac * 100)
        Set-Cell $lines $r3 2 ($barCol + (Get-Bar $frac $bw) + $c.R + ' ' + $c.Label + $pct + $c.R) ($bw + 1 + $pct.Length)
    }

    $r4 = $hit + 4
    if ($r4 -lt $h) {
        $t = $c.Dim + 'ESC pause' + $c.R + $c.Label + '    strike as a note touches the line' + $c.R
        Set-Cell $lines $r4 2 $t (9 + 4 + 34)
    }

    return $lines
}
