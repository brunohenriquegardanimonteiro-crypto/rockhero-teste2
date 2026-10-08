# ============================================================================
#  SCREENS
# ============================================================================
$script:SplashLines = @(
    'A GUITAR-HERO-STYLE RHYTHM GAME  -  100% PURE POWERSHELL',
    '',
    'The guitar, the bass, the drums and every note you hit are synthesised',
    'at runtime by an engine compiled inside this script.  No samples, no',
    'downloads, no dependencies.',
    '',
    'KEYS',
    '   1 2 3 4 5        strike lane 1 to 5',
    '   A S D F G        the same five lanes, left hand',
    '   SPACE            activate OVERDRIVE when the ROCK meter is full',
    '   ESC              pause / go back          ENTER  confirm',
    '',
    'SCORING',
    '   PERFECT 300    GREAT 200    GOOD 100    x1 .. x5 combo multiplier',
    '   Long notes: keep the lane pressed for the whole tail or you lose the combo.',
    '   The ROCK meter fills on hits and drains on misses.  Fill it, then press',
    '   SPACE: OVERDRIVE doubles your score for eight seconds.  Let it hit zero',
    '   and you rock out.',
    '',
    'THE MUSIC',
    '   Every riff is an original composition written in the style of the band',
    '   it is credited to - a playable tribute, not a recording.',
    '',
    'PRESS ENTER to continue...'
)

function Show-Splash {
    Set-Screen
    $title = 'R O C K   H E R O'
    while ($true) {
        $lines = New-BlankLines
        $c = $script:C
        $pad = [int][Math]::Max(0, [int](($script:W - $title.Length) / 2))
        Set-Cell $lines 1 $pad ($c.Title + $title + $c.R) $title.Length
        $i = 0
        foreach ($l in $script:SplashLines) {
            $col = $c.Label
            if ($l -match '^(KEYS|SCORING|THE MUSIC)$') { $col = $c.Nrm }
            if ($l -match '^PRESS ENTER') { $col = $c.Ok }
            Set-Cell $lines (4 + $i) 4 ($col + $l + $c.R) $l.Length
            $i++
        }
        Write-Screen $lines
        $k = Wait-Key
        if ($null -eq $k) { return }
        if ($k.Key -eq 'Enter' -or $k.Key -eq 'Space') { return }
        $ch = [string]$k.KeyChar
        if ($ch -match '^[qQ]$') { return }
        if ($ch -match '^[sS]$') { return }
    }
}

function Show-SongListScreen {
    Show-SongTable
}

function Show-SongTable {
    # full scrollable song table
    Set-Screen
    $n = $script:Catalog.Count
    $perPage = [Math]::Max(6, $script:H - 9)
    $top = 0
    while ($true) {
        $lines = New-BlankLines
        $c = $script:C
        Set-Cell $lines 1 0 ($c.Title + '  ALL SONGS' + $c.R) 13
        Set-Cell $lines 2 0 ($c.Label + ('  {0} songs from {1} bands      page {2}/{3}' -f $n, (Get-BandCount), ([int]($top / $perPage) + 1), ([int][Math]::Ceiling($n / $perPage))) + $c.R) 60
        Set-Cell $lines 4 2 ($c.Label + ('  {0,3}  {1,-18} {2,-22} {3,4}  {4}' -f '#', 'BAND', 'TITLE', 'BPM', 'STYLE') + $c.R) 56
        for ($i = 0; $i -lt $perPage; $i++) {
            $idx = $top + $i
            if ($idx -ge $n) { break }
            $s = $script:Catalog[$idx]
            $txt = '  ' + ('{0,3}  {1,-18} {2,-22} {3,4}  {4}' -f ($idx + 1), $s.Band, $s.Title, $s.Bpm, $s.Style)
            Set-Cell $lines (5 + $i) 2 ($c.Nrm + $txt + $c.R) 55
        }
        Set-Cell $lines ($script:H - 2) 2 ($c.Label + 'UP/DOWN scroll   HOME/END jump   ESC back' + $c.R) 44
        Write-Screen $lines
        $k = Wait-Key
        if ($null -eq $k) { return }
        $kc = $k.Key
        if ($kc -eq 'Escape' -or $kc -eq 'Enter') { return }
        $ch = [string]$k.KeyChar
        if ($kc -eq 'DownArrow' -or $ch -match '^[sS]$') { $top++ }
        elseif ($kc -eq 'UpArrow' -or $ch -match '^[wW]$') { $top-- }
        elseif ($kc -eq 'PageDown') { $top += $perPage }
        elseif ($kc -eq 'PageUp')   { $top -= $perPage }
        elseif ($kc -eq 'Home') { $top = 0 }
        elseif ($kc -eq 'End')  { $top = $n }
        if ($top -lt 0) { $top = 0 }
        if ($top -gt $n) { $top = $n }
    }
}

function Show-Options {
    while ($true) {
        Set-Screen
        $items = @('Volume', 'Note speed', 'Misses to fail', 'Colour mode', 'Delete high scores', 'Back')
        $sel = Show-Menu -Title 'OPTIONS' -Sub 'LEFT / RIGHT to change a value' -Items $items `
            -DrawRow {
                param($i, $s)
                $mark = if ($s) { $script:C.Sel + $script:G.arrow + ' ' } else { '   ' }
                $col  = if ($s) { $script:C.Sel } else { $script:C.Nrm }
                $name = $items[$i]
                switch ($i) {
                    0 { return $mark + $col + ('{0,-20}' -f $name) + ' ' + $script:C.Bar + (Get-Bar ($script:Vol / 100.0) 20) + $script:C.R + '  ' + $script:C.Val + ('{0,3}' -f $script:Vol) + $script:C.R }
                    1 { return $mark + $col + ('{0,-20}' -f $name) + ' ' + $script:C.Bar + (Get-Bar (($script:SpScale - 0.5) / 1.5) 20) + $script:C.R + '  ' + $script:C.Val + ('{0,4:N2}x' -f $script:SpScale) + $script:C.R }
                    2 { return $mark + $col + ('{0,-20}' -f $name) + '   ' + $script:C.Val + (Get-FailLabel $script:FailMisses) + $script:C.R }
                    3 {
                        $m = 'no colour (ASCII)'
                        if (-not $script:Ascii) {
                            if ($script:Ansi) { $m = 'ANSI 256 colour' } else { $m = 'plain (console has no VT)' }
                        }
                        return $mark + $col + ('{0,-20}' -f $name) + '   ' + $script:C.Val + $m + $script:C.R
                    }
                    4 {
                        $cnt = $script:High.Count
                        return $mark + $col + ('{0,-20}' -f $name) + '   ' + $script:C.Dim + ('{0} record(s) stored' -f $cnt) + $script:C.R + $script:C.Warn + ' ENTER to wipe' + $script:C.R
                    }
                    default { return $mark + $col + $name + $script:C.R }
                }
            } `
            -DrawFoot {
                $t = 'ESC also leaves options'
                $d = Get-AudioDiag
                $room = $script:W - (2 + $t.Length + 3) - 1
                if ($room -lt 12) { $room = 12 }
                if ($d.Length -gt $room) { $d = $d.Substring(0, $room) }
                return $script:C.Label + $t + $script:C.R + '   ' + $script:C.Warn + $d + $script:C.R
            }
        if ($sel -eq -1 -or $sel -eq 5) { return }

        switch ($sel) {
            0 {
                $v = $script:Vol
                while ($true) {
                    $k = Wait-Key; if ($null -eq $k) { break }
                    $ch = [string]$k.KeyChar
                    if ($k.Key -eq 'LeftArrow' -or $ch -eq '[') { $v = [Math]::Max(0, $v - 5) }
                    elseif ($k.Key -eq 'RightArrow' -or $ch -eq ']') { $v = [Math]::Min(100, $v + 5) }
                    else { break }
                    $script:Vol = $v; Apply-Volume; Play-Blip 0
                    $done = Show-OptionsBar $sel $v
                    if ($done) { break }
                }
                return
            }
            1 {
                $v = $script:SpScale
                while ($true) {
                    $k = Wait-Key; if ($null -eq $k) { break }
                    $ch = [string]$k.KeyChar
                    if ($k.Key -eq 'LeftArrow' -or $ch -eq '[') { $v = [Math]::Max(0.5, $v - 0.05) }
                    elseif ($k.Key -eq 'RightArrow' -or $ch -eq ']') { $v = [Math]::Min(2.0, $v + 0.05) }
                    else { break }
                    $script:SpScale = [Math]::Round($v, 2); Play-Blip 0
                    if (Show-OptionsBar $sel $v) { break }
                }
                return
            }
            2 {
                # cycle the strike budget: fewer misses left = harder
                $lad = $script:FailLadder
                $v = $script:FailMisses
                while ($true) {
                    $k = Wait-Key; if ($null -eq $k) { break }
                    $ch = [string]$k.KeyChar
                    if ($k.Key -eq 'LeftArrow' -or $ch -eq '[') {
                        $i2 = $lad.IndexOf($v); if ($i2 -lt 0) { $i2 = 0 }
                        $v = $lad[[Math]::Max(0, $i2 - 1)]
                    } elseif ($k.Key -eq 'RightArrow' -or $ch -eq ']') {
                        $i2 = $lad.IndexOf($v); if ($i2 -lt 0) { $i2 = 0 }
                        $v = $lad[[Math]::Min($lad.Count - 1, $i2 + 1)]
                    } else { break }
                    $script:FailMisses = $v; Save-Settings | Out-Null
                    if ($v -le 3) { Play-Blip 2 } else { Play-Blip 0 }
                    if (Show-OptionsBar $sel $v) { break }
                }
                return
            }
            3 {
                $script:Ascii = -not $script:Ascii
                New-GlyphTable; New-ColorTable; Set-Screen
                continue
            }
            4 {
                $items2 = @('CANCEL', 'YES - ERASE EVERY RECORD')
                $r2 = Show-Menu -Title 'ERASE SCORES?' -Sub 'this cannot be undone' -Items $items2 `
                    -DrawRow {
                        param($i, $s)
                        $mark = if ($s) { $script:C.Sel + $script:G.arrow + ' ' } else { '   ' }
                        $col = if ($s) { $script:C.Sel } else { $script:C.Nrm }
                        return $mark + $col + $items2[$i] + $script:C.R
                    }
                if ($r2 -eq 1) { $script:High = @{}; Save-Scores | Out-Null; Play-Blip 2 }
                continue
            }
        }
    }
}

function Show-OptionsBar {
    param([int]$Which, [double]$Value)
    Set-Screen
    $items = @('Volume', 'Note speed', 'Misses to fail', 'Colour mode', 'Delete high scores', 'Back')
    $lines = New-BlankLines
    $c = $script:C
    Set-Cell $lines 1 0 ($c.Title + '  OPTIONS' + $c.R) 13
    Set-Cell $lines 2 0 ($c.Label + 'LEFT / RIGHT to change, ENTER to accept' + $c.R) 44
    for ($i = 0; $i -lt $items.Count; $i++) {
        $mark = if ($i -eq $Which) { $c.Sel + $c.R + $script:G.arrow + ' ' } else { '   ' }
        $col = if ($i -eq $Which) { $c.Sel } else { $c.Nrm }
        $val = ''
        switch ($i) {
            0 { $val = ' ' + $c.Bar + (Get-Bar ($script:Vol / 100.0) 20) + $c.R + '  ' + $c.Val + ('{0,3}' -f $script:Vol) + $c.R; $pl = 26 }
            1 { $val = ' ' + $c.Bar + (Get-Bar (($script:SpScale - 0.5) / 1.5) 20) + $c.R + '  ' + $c.Val + ('{0,4:N2}x' -f $script:SpScale) + $c.R; $pl = 27 }
            2 { $val = '   ' + $c.Val + (Get-FailLabel $script:FailMisses) + $c.R; $pl = 30 }
            3 { $val = '   ' + $c.Val + $(if ($script:Ascii) { 'no colour (ASCII)' } else { 'ANSI 256 colour' }) + $c.R; $pl = 20 }
            4 { $val = '   ' + $c.Warn + 'ENTER to wipe' + $c.R; $pl = 15 }
            default { $val = ''; $pl = 0 }
        }
        Set-Cell $lines (4 + $i) 2 ($mark + $col + ('{0,-20}' -f $items[$i]) + $val + $c.R) (22 + $pl)
    }
    Write-Screen $lines
    return $false
}

function Show-SongSelect {
    while ($true) {
        Set-Screen
        $n = $script:Catalog.Count
        $items = New-Object 'string[]' $n
        for ($i = 0; $i -lt $n; $i++) { $items[$i] = 'x' }
        $sel = Show-Menu -Title 'CHOOSE A SONG' -Sub 'UP/DOWN pick    ENTER play    ESC back' -Items $items `
            -DrawRow {
                param($i, $s)
                $sg = $script:Catalog[$i]
                $mark = if ($s) { $script:C.Sel + $script:G.arrow + ' ' } else { '   ' }
                $col  = if ($s) { $script:C.Sel } else { $script:C.Nrm }
                $band = $sg.Band;  if ($band.Length -gt 18) { $band = $band.Substring(0, 18) }
                $ttl  = $sg.Title; if ($ttl.Length -gt 24) { $ttl = $ttl.Substring(0, 24) }
                $rec = Get-ScoreFor $i $script:Difficulty[0].Name
                $rt = '     -   '
                if ($null -ne $rec) { $rt = ('{0,7} {1,-3}' -f $rec.Score, $rec.Rank) }
                return $mark + $col + ('{0,3} ' -f ($i + 1)) + ('{0,-18} ' -f $band) + ('{0,-24} ' -f $ttl) +
                       $script:C.Label + ('{0,4} ' -f $sg.Bpm) + $script:C.Dim + ('{0,-7}' -f $sg.Style) +
                       $script:C.Val + ('  ' + $rt + ' ') + $script:C.R
            } `
            -DrawFoot { $script:C.Label + 'ESC returns to the main menu' + $script:C.R }
        if ($sel -lt 0) { return 'back' }

        $diff = Show-Difficulty $sel
        if ($null -eq $diff) { continue }
        $r = Invoke-Game $sel $diff
        if ($r -eq 'main') { $script:ForceMain = $false; return 'main' }
        if ($r -eq 'restart') { $r = Invoke-Game $sel $diff }
        if ($r -eq 'main') { return 'main' }
    }
}

function Show-Difficulty {
    param([int]$SongIndex)
    while ($true) {
        Set-Screen
        $items = New-Object 'string[]' $script:Difficulty.Count
        for ($i = 0; $i -lt $script:Difficulty.Count; $i++) { $items[$i] = $script:Difficulty[$i].Name }
        $sg = $script:Catalog[$SongIndex]
        $sel = Show-Menu -Title 'DIFFICULTY' -Sub ('{0} - {1}' -f $sg.Band, $sg.Title) -Items $items `
            -DrawRow {
                param($i, $s)
                $df = $script:Difficulty[$i]
                $mark = if ($s) { $script:C.Sel + $script:G.arrow + ' ' } else { '   ' }
                $col  = if ($s) { $script:C.Sel } else { $script:C.Nrm }
                $rec = Get-ScoreFor $SongIndex $df.Name
                $rt = '   -  '
                if ($null -ne $rec) { $rt = ('{0,7} {1,-3}' -f $rec.Score, $rec.Rank) }
                return $mark + $col + ('{0,-7}' -f $df.Pt) + $script:C.Label + ('{0,-32}' -f $df.Desc) +
                       $script:C.Val + ('  {0}' -f $rt) + $script:C.R
            } `
            -DrawFoot { $script:C.Label + 'ESC goes back to the song list' + $script:C.R }
        if ($sel -lt 0) { return $null }
        return $script:Difficulty[$sel].Name
    }
}

function Invoke-MainMenu {
    while ($true) {
        $script:ForceMain = $false
        Set-Screen
        $items = @('PLAY', 'HOW TO PLAY', 'ALL SONGS', 'OPTIONS', 'RUN SELF-TEST', 'QUIT')
        $sel = Show-Menu -Title 'R O C K   H E R O' -Sub 'a PowerShell tribute' -Items $items `
            -DrawRow {
                param($i, $s)
                $mark = if ($s) { $script:C.Sel + $script:G.arrow + ' ' } else { '   ' }
                $col  = if ($s) { $script:C.Sel } else { $script:C.Nrm }
                $extra = ''
                if ($i -eq 0) { $extra = $script:C.Label + ('   {0} songs / {1} bands' -f $script:Catalog.Count, (Get-BandCount)) + $script:C.R }
                if ($i -eq 5) { $extra = $script:C.Dim + '   ESC' + $script:C.R }
                return $mark + $col + ('{0,-20}' -f $items[$i]) + $extra + $script:C.R
            } `
            -DrawFoot { $script:C.Label + 'ESC or Q to quit' + $script:C.R }

        if ($sel -lt 0 -or $sel -eq 5) { return 'quit' }
        switch ($sel) {
            0 {
                $r = Show-SongSelect
                if ($r -eq 'main') { return 'menu' }
            }
            1 { Show-Splash }
            2 { Show-SongTable }
            3 { Show-Options }
            4 { Run-SelfTestScreen }
        }
    }
}
