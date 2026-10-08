# ============================================================================
#  CONSOLE / SCREEN LAYOUT
# ============================================================================
function Get-ScreenSize {
    $w = 0; $h = 0
    try { $w = [Console]::WindowWidth; $h = [Console]::WindowHeight } catch { }
    if ($w -le 0 -or $h -le 0) {
        try { $sz = $Host.UI.RawUI.WindowSize; $w = $sz.Width; $h = $sz.Height } catch { }
    }
    if ($w -lt 20) { $w = $script:IDEALW }
    if ($h -lt 10) { $h = $script:IDEALH }
    return [pscustomobject]@{ W = $w; H = $h }
}

function Set-Screen {
    param([switch]$Ideal)
    try {
        $ws = $Host.UI.RawUI.WindowSize
        $nw = [Math]::Max($ws.Width,  $script:IDEALW)
        $nh = [Math]::Max($ws.Height, $script:IDEALH)
        if ($nw -ne $ws.Width -or $nh -ne $ws.Height) {
            $Host.UI.RawUI.WindowSize = New-Object System.Management.Automation.Host.Size($nw, $nh)
        }
    } catch { }
    if ($Ideal) { }

    $sz = Get-ScreenSize
    $script:W = $sz.W
    $script:H = $sz.H
    $script:HITROW = [Math]::Max($script:HWTOP + 8, $script:H - 6)
    # a short window must not push the hit row off the bottom of the screen
    if ($script:HITROW -gt ($script:H - 1)) { $script:HITROW = $script:H - 1 }
    if ($script:HITROW -lt 0) { $script:HITROW = 0 }
    $script:PANELX = $script:HWLEFT + ($script:LANES * $script:LW) + 4
    $script:PANELW = [Math]::Max(12, $script:W - $script:PANELX - 1)
    if ($script:PANELW -gt 32) { $script:PANELW = 32 }
    Update-Base
}

function Update-Base {
    $w = $script:W; $h = $script:H
    if ($script:Base -and $w -eq $script:BaseW -and $h -eq $script:BaseH) { return }
    $script:BaseW = $w; $script:BaseH = $h

    $base = New-Object 'string[]' $h
    $rail = $script:G.rail
    $rep  = $script:G.receptor
    $hit  = $script:HITROW
    $lanesTail = $script:LW - 1

    for ($r = 0; $r -lt $h; $r++) {
        if ($r -eq ($script:HWTOP - 1)) {
            $sb = New-Object Text.StringBuilder
            [void]$sb.Append(' ' * $script:HWLEFT)
            for ($l = 0; $l -lt $script:LANES; $l++) { [void]$sb.Append($script:G.top * $script:LW) }
            $base[$r] = $sb.ToString()
            continue
        }
        if ($r -lt $script:HWTOP -or $r -gt $hit) { $base[$r] = ''; continue }
        $sb = New-Object Text.StringBuilder
        [void]$sb.Append(' ' * $script:HWLEFT)
        for ($l = 0; $l -lt $script:LANES; $l++) {
            [void]$sb.Append($rail)
            if ($r -eq $hit) { [void]$sb.Append($rep * $lanesTail) } else { [void]$sb.Append(' ' * $lanesTail) }
        }
        $line = $sb.ToString()
        if ($line.Length -gt $w) { $line = $line.Substring(0, $w) }
        $base[$r] = $line
    }
    $script:Base = $base
}

function Get-BaseRow {
    param([int]$Index)
    if ($script:Base -and $Index -ge 0 -and $Index -lt $script:Base.Count) {
        if ($null -ne $script:Base[$Index]) { return $script:Base[$Index] }
    }
    return ' ' * $script:W
}

# Copy a line keeping only printable columns: an escape sequence occupies no
# space on screen, so counting raw characters chopped the right hand side off
# every coloured line (and cut colours in half) on a real console.
function Copy-Visible {
    param([string]$Line, [int]$Skip = 0, [int]$Take = -1)
    if ($null -eq $Line) { return '' }
    if ($Line.Length -eq 0) { return '' }
    $sb = New-Object Text.StringBuilder
    $vis = 0
    $i = 0
    $n = $Line.Length
    while ($i -lt $n) {
        $cp = [int]$Line[$i]
        if ($cp -eq 27) {
            [void]$sb.Append($Line[$i]); $i++
            while ($i -lt $n) {
                $c2 = [int]$Line[$i]
                [void]$sb.Append($Line[$i]); $i++
                if (($c2 -ge 65 -and $c2 -le 90) -or ($c2 -ge 97 -and $c2 -le 122)) { break }
            }
            continue
        }
        if ($vis -lt $Skip) { $i++; continue }
        if ($Take -ge 0 -and $vis -ge ($Skip + $Take)) { break }
        [void]$sb.Append($Line[$i])
        $vis++
        $i++
    }
    return $sb.ToString()
}

# Fast path used every frame: colour runs are removed by the regex engine and
# only a genuinely too wide line falls back to the character walk. Short rows
# are padded too, otherwise the columns they leave behind keep an older frame.
$script:AnsiRun = [string][char]27 + '\[[0-9;]*[A-Za-z]'
function Limit-Line {
    param([string]$Line)
    if ($null -eq $Line -or $script:W -le 0) { return $Line }
    if ($Line.IndexOf([char]27) -lt 0) {
        if ($Line.Length -gt $script:W) { return $Line.Substring(0, $script:W) }
        return $Line + (' ' * ($script:W - $Line.Length))
    }
    $plain = [regex]::Replace($Line, $script:AnsiRun, '')
    if ($plain.Length -eq $script:W) { return $Line }
    if ($plain.Length -gt $script:W) { return Copy-Visible $Line 0 $script:W }
    return $Line + (' ' * ($script:W - $plain.Length))
}

function New-BlankLines {
    $lines = New-Object 'string[]' $script:H
    $blank = ' ' * $script:W
    for ($i = 0; $i -lt $script:H; $i++) { $lines[$i] = $blank }
    # the comma keeps the array intact: without it PowerShell unrolls it into
    # the pipeline and Set-Cell would later be handed a copy it cannot write to
    return ,$lines
}

function Write-Screen {
    param([string[]]$Lines)
    $sb = New-Object Text.StringBuilder (($script:W * ($script:H + 2)) + 256)
    for ($i = 0; $i -lt $script:H; $i++) {
        $l = ''
        if ($i -lt $Lines.Count -and $null -ne $Lines[$i]) { $l = $Lines[$i] }
        $l = $l.Replace("`r", '').Replace("`n", '')
        # never wider than the console: a longer line wraps and smears the screen
        # (counting columns, not the escape bytes hidden between them)
        $l = Limit-Line $l
        # only between rows: a line feed after the last visible row scrolls the
        # window down by one on every frame, which makes the game shake
        if ($i -gt 0) { [void]$sb.Append("`r`n") }
        [void]$sb.Append($l)
    }
    $txt = $sb.ToString()
    try {
        [Console]::SetCursorPosition(0, 0)
        [Console]::Out.Write($txt)
        [Console]::Out.Flush()
    } catch {
        try { [Console]::Write($txt) } catch { }
    }
}

# ============================================================================
#  HIGH SCORES
# ============================================================================
function Load-Scores {
    $script:High = @{}
    if (-not $script:ScoreFile) { return }
    try {
        if (Test-Path -LiteralPath $script:ScoreFile) {
            $d = Import-Clixml -LiteralPath $script:ScoreFile -ErrorAction Stop
            if ($d -is [System.Collections.IDictionary]) {
                foreach ($k in $d.Keys) { $script:High[[string]$k] = $d[$k] }
            }
        }
    } catch { $script:High = @{} }
}

function Save-Scores {
    param([string]$Path)
    $target = $Path
    if (-not $target) { $target = $script:ScoreFile }
    if (-not $target) { return $false }
    try {
        $script:High | Export-Clixml -LiteralPath $target -Depth 4 -ErrorAction Stop
        return $true
    } catch { return $false }
}

function Get-ScoreKey { param([int]$Idx, [string]$Diff) return ('{0}|{1}' -f $Idx, $Diff) }

function Get-ScoreFor {
    param([int]$Idx, [string]$Diff)
    $k = Get-ScoreKey $Idx $Diff
    if ($script:High.ContainsKey($k)) { return $script:High[$k] }
    return $null
}

function Set-ScoreFor {
    param([int]$Idx, [string]$Diff, $Rec)
    $k = Get-ScoreKey $Idx $Diff
    $old = Get-ScoreFor $Idx $Diff
    if ($null -eq $old -or $Rec.Score -gt $old.Score) { $script:High[$k] = $Rec; return $true }
    return $false
}

# ============================================================================
#  GENERIC MENU
# ============================================================================
function Show-Menu {
    param(
        [string]$Title,
        [string]$Sub = '',
        [string[]]$Items,
        [scriptblock]$DrawRow,
        [scriptblock]$DrawFoot = $null,
        [int]$Sel = 0,
        [switch]$NoNumber
    )
    $sel = $Sel
    if ($sel -lt 0) { $sel = 0 }
    if ($Items.Count -gt 0 -and $sel -ge $Items.Count) { $sel = $Items.Count - 1 }
    $top = 0

    while ($true) {
        $lines = New-BlankLines
        $c = $script:C
        # a long list (the song catalogue) has to scroll, otherwise the cursor
        # can sit on a row the screen never drew
        $rows = $script:H - 6
        if ($rows -lt 1) { $rows = 1 }
        if ($sel -lt $top) { $top = $sel }
        if ($sel -ge ($top + $rows)) { $top = $sel - $rows + 1 }
        $last = $Items.Count - $rows
        if ($top -gt $last) { $top = $last }
        if ($top -lt 0) { $top = 0 }
        if ($Title -gt '') {
            $t = $Title
            if ($t.Length -gt $script:W) { $t = $t.Substring(0, $script:W) }
            $pad = ' ' * [Math]::Max(0, [int](($script:W - $t.Length) / 2))
            $lines[1] = $pad + $c.Title + $t + $c.R
        }
        if ($Sub -gt '') {
            $s = $Sub
            if ($s.Length -gt $script:W) { $s = $s.Substring(0, $script:W) }
            $pad = ' ' * [Math]::Max(0, [int](($script:W - $s.Length) / 2))
            $lines[2] = $pad + $c.Label + $s + $c.R
        }
        for ($i = $top; $i -lt $Items.Count; $i++) {
            $row = 4 + ($i - $top)
            if ($row -ge ($script:H - 2)) { break }
            $lines[$row] = '  ' + (& $DrawRow $i ($i -eq $sel))
        }
        if ($null -ne $DrawFoot) {
            $lines[$script:H - 2] = '  ' + (& $DrawFoot)
        } else {
            $hint = 'UP/DOWN or W/S to move    ENTER confirm    ESC back'
            if ($NoNumber) { $hint = 'UP/DOWN or W/S to move    ENTER confirm    ESC back' }
            $lines[$script:H - 2] = '  ' + $c.Label + $hint + $c.R
        }
        Write-Screen $lines

        $k = Wait-Key
        if ($null -eq $k) { return -1 }
        $kc = $k.Key
        $ch = [string]$k.KeyChar
        $move = 0; $act = $false; $back = $false
        if ($kc -eq 'UpArrow' -or $kc -eq 'LeftArrow') { $move = -1 }
        elseif ($kc -eq 'DownArrow' -or $kc -eq 'RightArrow') { $move = 1 }
        elseif ($kc -eq 'Home') { $move = -999 }
        elseif ($kc -eq 'End') { $move = 999 }
        elseif ($kc -eq 'Enter' -or $kc -eq 'Space') { $act = $true }
        elseif ($kc -eq 'Escape' -or $kc -eq 'Backspace') { $back = $true }
        elseif ($ch -match '^[wW]$') { $move = -1 }
        elseif ($ch -match '^[sS]$') { $move = 1 }
        elseif (-not $NoNumber -and $ch -match '^[1-9]$') {
            $i = [int]$ch - 1
            if ($i -lt $Items.Count) { $sel = $i; $act = $true }
        }
        if ($move -ne 0 -and $Items.Count -gt 0) {
            $ns = $sel + $move
            if ($ns -lt 0) { $ns = 0 }
            if ($ns -ge $Items.Count) { $ns = $Items.Count - 1 }
            if ($ns -ne $sel) { Play-Blip 0; $sel = $ns }
        }
        if ($back) { Play-Blip 2; return -1 }
        if ($act)  { Play-Blip 1; return $sel }
    }
}
