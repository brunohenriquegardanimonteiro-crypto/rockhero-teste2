# ============================================================================
#  SONG CATALOG  -  original riffs written in the style of each band
#
#  Riff  : 16 chars per bar.  0-4 = fret (mapped onto chord tones),
#          '.' = rest, '-' = let ring
#  Prog  : semitone offset of each bar's chord root (one per riff bar)
#  Drums : 16 chars per bar.  K crash, k kick, s snare, h hat, H open hat
#  Lead  : 16 chars per bar, 0-9 = degree in the scale
# ============================================================================
function New-Song {
    param(
        [string]$Band, [string]$Title, [string]$Style, [int]$Bpm,
        [int]$Root = 40, [bool]$Minor = $true,
        [string[]]$Prog, [string[]]$Riff, [string[]]$Drums, [string[]]$Lead
    )
    [pscustomobject]@{
        Band = $Band; Title = $Title; Style = $Style; Bpm = $Bpm
        Root = $Root; Minor = $Minor
        Prog = $Prog; Riff = $Riff; Drums = $Drums; Lead = $Lead
    }
}

function Get-Catalog {
    $c = New-Object System.Collections.Generic.List[object]

    # -------------------------------------------------------- BLACK SABBATH
    $c.Add((New-Song -Band 'Black Sabbath' -Title 'Iron Man' -Style 'doom' -Bpm 100 -Root 40 -Minor $true -Prog @('0','0','0','0') `
        -Riff  @('0.1.2.3.4.3.2.1.', '2.2.3.3.4.4.3.3.', '0.1.2.3.4.3.2.1.', '0.0.4.4.0.0.4.4.') `
        -Drums @('K..ks...k..ks...', 'K...s...k.kks.kk', 'K..hs..hk..ks..h', 'Khhks...k.khk.kk') `
        -Lead  @('4.4.3.3.2.2.0.0.', '0...4...3...2...', '7...7...4...4...', '0.0.4.4.0.0.7.7.')))

    $c.Add((New-Song -Band 'Black Sabbath' -Title 'Paranoid' -Style 'blues' -Bpm 92 -Root 40 -Minor $true -Prog @('0','0','3','5') `
        -Riff  @('0.0.1.0.0.1.0.0.', '4.4.3.4.4.3.4.3.', '0.0.1.1.0.0.4.4.', '2.2.1.1.0.0.4.4.') `
        -Drums @('K.k.s.k.k.ks.k.s', 'K..ks...k..ks...', 'K.hhs..hk.hhs.kh', 'K..hs..hsKks..hs') `
        -Lead  @('4.4.7.7.4.4.2.2.', '7.6.4.3.2.1.0.0.', '0...7...4...2...', '4...4...7...7...')))

    $c.Add((New-Song -Band 'Black Sabbath' -Title 'War Pigs' -Style 'doom' -Bpm 90 -Root 40 -Minor $true -Prog @('0','0','8','0') `
        -Riff  @('0.0.0.0.0.0.0.0.', '0.0.0.0.1.1.1.1.', '0.0.0.0.0.0.4.4.', '0.0.0.0.2.2.2.2.') `
        -Drums @('K...s...K...s...', 'K...s.k.k...s.k.', 'K...s...K...s...', 'K.k.s.k.k.ks.k.s') `
        -Lead  @('0...0...4...4...', '4...4...0...0...', '0...0...7...7...', '4.4.4.4.2.2.2.2.')))

    $c.Add((New-Song -Band 'Black Sabbath' -Title 'N.I.B.' -Style 'doom' -Bpm 100 -Root 40 -Minor $true -Prog @('0','0','0','0') `
        -Riff  @('0...0...0...0...', '0...0...4...4...', '0...0...3...3...', '4...3...2...1...') `
        -Drums @('K...............', 'K...s...K...s...', 'K...............', 'K...s...K...s...') `
        -Lead  @('0...0...4...4...', '4...4...7...7...', '7...7...4...4...', '4.4.3.3.2.2.0.0.')))

    $c.Add((New-Song -Band 'Black Sabbath' -Title 'Children of the Grave' -Style 'proto-metal' -Bpm 90 -Root 43 -Minor $false -Prog @('0','0','5','3') `
        -Riff  @('0.0.0.0.1.1.0.0.', '0.0.1.1.1.1.0.0.', '2.2.1.1.0.0.0.0.', '1.1.0.0.4.4.0.0.') `
        -Drums @('K..ks...k..ks...', 'K.k.s.k.k.ks.k.s', 'K..hs..hk..hs.kk', 'K...s.k.k...s.k.') `
        -Lead  @('0.2.3.4.3.2.0...', '4.4.4.4.2.2.2.2.', '0...7...4...2...', '7...7...4...4...')))

    $c.Add((New-Song -Band 'Black Sabbath' -Title 'Loner' -Style 'proto-metal' -Bpm 128 -Root 40 -Minor $true -Prog @('0','0','5','3') `
        -Riff  @('0.1.2.1.0.1.2.1.', '4.3.2.1.0.1.2.3.', '2.1.0.1.2.3.4.3.', '0.0.2.2.4.4.2.2.') `
        -Drums @('K.ks.hKh.ks.hKh.', 'K.k.s.k.k.ks.k.s', 'K.ks.hKh.ks.hKh.', 'Kh.h.s.hKh.h.s.h') `
        -Lead  @('4.4.3.3.2.2.0.0.', '9.8.7.6.4.3.2.0.', '7.7.9.9.7.7.4.4.', '0.2.3.4.3.2.0...')))

    $c.Add((New-Song -Band 'Black Sabbath' -Title 'Age of Reason' -Style 'ballad' -Bpm 96 -Root 40 -Minor $true -Prog @('0','5','3','0') `
        -Riff  @('0...0...4...4...', '0.0.2.2.0.0.1.1.', '2.2.1.1.0.0.4.4.', '0.0.0.0.4.4.2.2.') `
        -Drums @('K...s...K...s...', 'K..hs..hk..hs.kk', 'K...s.k.k...s.k.', 'K.ks.hKh.ks.hKh.') `
        -Lead  @('0...7...4...2...', '4...4...7...7...', '7.6.4.3.2.1.0.0.', '0...4...3...2...')))

    # -------------------------------------------------------- LED ZEPPELIN
    $c.Add((New-Song -Band 'Led Zeppelin' -Title 'Stairway to Heaven' -Style 'prog' -Bpm 82 -Root 45 -Minor $true -Prog @('0','0','5','3') `
        -Riff  @('0...0...4...4...', '0.2.2.0.2.2.0.2.', '0.0.4.4.0.0.4.4.', '2.2.4.4.0.0.1.1.') `
        -Drums @('K...s...K...s...', 'K..hs..hk..hs.kk', 'K...s...K...s...', 'Kh.h.s.hKh.h.s.h') `
        -Lead  @('0...2...4...5...', '7.7.9.9.7.7.4.4.', '0...7...4...2...', '4.4.7.7.9.9.0.0.')))

    $c.Add((New-Song -Band 'Led Zeppelin' -Title 'Whole Lotta Love' -Style 'riff' -Bpm 116 -Root 40 -Minor $true -Prog @('0','0','0','0') `
        -Riff  @('0.0.4.0.0.4.0.0.', '2.2.4.2.2.4.2.2.', '0.0.4.4.0.0.4.4.', '1.1.4.4.1.1.4.4.') `
        -Drums @('K...s...K...s...', 'K..ks...k..ks...', 'K.hhs..hk.hhs.kh', 'K.k.s.k.k.ks.k.s') `
        -Lead  @('4...4...7...7...', '0.2.3.4.3.2.0...', '7.6.4.3.2.1.0.0.', '0.0.7.7.9.9.7.7.')))

    # -------------------------------------------------------- GUNS N' ROSES
    $c.Add((New-Song -Band "Guns N' Roses" -Title 'Sweet Child o Mine' -Style 'arena' -Bpm 126 -Root 40 -Minor $true -Prog @('0','0','0','0') `
        -Riff  @('0.2.0.2.0.2.0.2.', '0.2.0.2.1.3.1.3.', '0.0.4.4.0.0.4.4.', '2.2.4.4.3.3.1.1.') `
        -Drums @('K...s...K...s...', 'K...s.k.k...s.k.', 'K...s...K...s...', 'K.kks.k.kks.kks.') `
        -Lead  @('4.4.7.7.9.9.7.7.', '7.7.9.9.7.7.4.4.', '9.8.7.6.4.3.2.0.', '4...4...7...7...')))

    $c.Add((New-Song -Band "Guns N' Roses" -Title 'Paradise City' -Style 'ballad' -Bpm 104 -Root 43 -Minor $true -Prog @('0','5','3','0') `
        -Riff  @('0.0.0.0.0.0.4.4.', '0.0.2.2.0.0.1.1.', '2.2.1.1.0.0.4.4.', '0.0.0.0.4.4.2.2.') `
        -Drums @('K...s...K...s...', 'K..hs..hk..hs.kk', 'K...s...K...s...', 'K.ks.hKh.ks.hKh.') `
        -Lead  @('0...7...4...2...', '4.4.7.7.9.9.7.7.', '7.6.4.3.2.1.0.0.', '0...4...3...2...')))

    # -------------------------------------------------------- METALLICA
    $c.Add((New-Song -Band 'Metallica' -Title 'Enter Sandman' -Style 'thrash' -Bpm 120 -Root 40 -Minor $true -Prog @('0','0','0','0') `
        -Riff  @('0.0.0.0.0...0.0.', '4.4.4.4.4...4.4.', '0.0.0.0.0.0.0.0.', '0.0.0.0.1.1.1.1.') `
        -Drums @('K...s...K...s...', 'Kkkk.s...kkk.s.k', 'K...s...K...s...', 'Kkkksssskkkkssss') `
        -Lead  @('4...3...2...1...', '0...4...3...2...', '7...7...4...4...', '4.4.3.3.2.2.0.0.')))

    $c.Add((New-Song -Band 'Metallica' -Title 'Master of Puppets' -Style 'thrash' -Bpm 136 -Root 38 -Minor $true -Prog @('0','0','8','7') `
        -Riff  @('0.1.2.1.0.1.2.1.', '0.0.0.0.4.4.0.0.', '1.1.2.2.3.3.2.2.', '0.0.4.4.0.0.2.2.') `
        -Drums @('K.kks.k.kks.kks.', 'K.k.s.k.k.ks.k.s', 'Kkkk.s...kkk.s.k', 'K.kks.k.kks.kks.') `
        -Lead  @('9.8.7.6.4.3.2.0.', '7.7.9.9.7.7.4.4.', '4...4...7...7...', '0.2.3.4.3.2.0...')))

    # -------------------------------------------------------- NIRVANA
    $c.Add((New-Song -Band 'Nirvana' -Title 'Smells Like Teen Spirit' -Style 'grunge' -Bpm 147 -Root 38 -Minor $true -Prog @('0','0','8','7') `
        -Riff  @('0.0.0.0.0.0.0.0.', '4.4.4.4.4.4.4.4.', '1.1.1.1.1.1.1.1.', '0.0.0.0.0.0.0.4.') `
        -Drums @('K...s...K...s...', 'Kh.h.s.hKh.h.s.h', 'K.k.s.k.k.ks.k.s', 'K.h.h.s.h.h.s.hK') `
        -Lead  @('4.4.4.4.2.2.2.2.', '0...4...3...2...', '7.6.4.3.2.1.0.0.', '4...4...7...7...')))

    $c.Add((New-Song -Band 'Nirvana' -Title 'Come as You Are' -Style 'grunge' -Bpm 118 -Root 40 -Minor $true -Prog @('0','0','3','5') `
        -Riff  @('0.0.4.4.0.0.1.1.', '2.2.1.1.0.0.4.4.', '0.1.2.1.0.1.2.1.', '0.0.2.2.4.4.2.2.') `
        -Drums @('K..hs..hsKks..hs', 'K...s...K...s...', 'K.ks.hKh.ks.hKh.', 'K...s.k.k...s.k.') `
        -Lead  @('0.0.7.7.9.9.7.7.', '4...4...7...7...', '7.6.4.3.2.1.0.0.', '0...2...4...5...')))

    # -------------------------------------------------------- AC/DC
    $c.Add((New-Song -Band 'AC/DC' -Title 'Back in Black' -Style 'funk-metal' -Bpm 168 -Root 45 -Minor $false -Prog @('0','0','0','0') `
        -Riff  @('0.0.0.0.0.0.0.0.', '1.1.1.1.1.1.1.1.', '0.0.0.0.4.4.4.4.', '2.2.2.2.2.2.2.2.') `
        -Drums @('K.k.s.k.k.ks.k.s', 'K.kks.k.kks.kks.', 'K.k.s.k.k.ks.k.s', 'Kkkksssskkkkssss') `
        -Lead  @('4.4.4.4.7.7.7.7.', '4...4...7...7...', '7.7.9.9.7.7.4.4.', '9.8.7.6.4.3.2.0.')))

    $c.Add((New-Song -Band 'AC/DC' -Title 'Highway to Hell' -Style 'funk-metal' -Bpm 118 -Root 45 -Minor $false -Prog @('0','0','0','0') `
        -Riff  @('0.0.0.0.0.0.0.0.', '1.1.1.1.1.1.1.1.', '4.4.4.4.0.0.0.0.', '0.1.2.1.0.1.2.1.') `
        -Drums @('K..ks...k..ks...', 'K.k.s.k.k.ks.k.s', 'K...s...K...s...', 'K.kks.k.kks.kks.') `
        -Lead  @('0.2.3.4.3.2.0...', '4...4...7...7...', '7.6.4.3.2.1.0.0.', '4.4.4.4.2.2.2.2.')))

    # -------------------------------------------------------- DEEP PURPLE
    $c.Add((New-Song -Band 'Deep Purple' -Title 'Smoke on the Water' -Style 'classic' -Bpm 105 -Root 43 -Minor $false -Prog @('0','0','0','0') `
        -Riff  @('0.1.2.1.0.1.2.1.', '4.4.3.3.2.2.1.1.', '0.1.2.1.0.1.2.1.', '4.3.2.1.0.1.2.3.') `
        -Drums @('K..ks...k..ks...', 'K...s...K...s...', 'K..hs..hk..hs.kk', 'K...s.k.k...s.k.') `
        -Lead  @('0.0.4.4.7.7.9.9.', '4...4...7...7...', '7.6.4.3.2.1.0.0.', '0.2.3.4.3.2.0...')))

    $c.Add((New-Song -Band 'Deep Purple' -Title 'High Ball Shooter' -Style 'classic' -Bpm 132 -Root 40 -Minor $false -Prog @('0','5','3','0') `
        -Riff  @('0.0.0.0.0.0.0.0.', '4.4.4.4.4.4.4.4.', '0.1.2.1.0.1.2.1.', '2.2.4.4.3.3.1.1.') `
        -Drums @('K.k.s.k.k.ks.k.s', 'K...s...K...s...', 'K.kks.k.kks.kks.', 'K.hhs..hk.hhs.kh') `
        -Lead  @('4.4.7.7.9.9.7.7.', '0...7...4...2...', '7...7...4...4...', '9.8.7.6.4.3.2.0.')))

    # -------------------------------------------------------- QUEEN
    $c.Add((New-Song -Band 'Queen' -Title 'Bohemian Rhapsody' -Style 'opera' -Bpm 112 -Root 40 -Minor $true -Prog @('0','0','3','5') `
        -Riff  @('0.2.0.2.0.2.0.2.', '0.0.4.4.0.0.4.4.', '4.4.0.0.2.2.0.0.', '0.0.2.2.4.4.2.2.') `
        -Drums @('K...s...K...s...', 'K..hs..hk..hs.kk', 'K...s...K...s...', 'K.kks.k.kks.kks.') `
        -Lead  @('0...4...3...2...', '4.4.7.7.9.9.7.7.', '7.7.9.9.7.7.4.4.', '0.2.3.4.3.2.0...')))

    $c.Add((New-Song -Band 'Queen' -Title 'We Will Rock You' -Style 'anthem' -Bpm 81 -Root 45 -Minor $false -Prog @('0','0','0','0') `
        -Riff  @('0...0...4...4...', '0.0.0.0.0.0.0.0.', '2...2...1...1...', '0.0.1.1.2.2.4.4.') `
        -Drums @('K...s...K...s...', 'K..ks...k..ks...', 'K...s...K...s...', 'Kkkksssskkkkssss') `
        -Lead  @('0...7...4...2...', '4.4.7.7.9.9.7.7.', '7...7...4...4...', '9.8.7.6.4.3.2.0.')))

    # -------------------------------------------------------- OZZY
    $c.Add((New-Song -Band 'Ozzy Osbourne' -Title 'Crazy Train' -Style 'funk-metal' -Bpm 157 -Root 40 -Minor $true -Prog @('0','0','0','0') `
        -Riff  @('0..0.0..0.0.0...', '0.0.0.0.0..0.0..', '4.4.0.0.4.4.0.0.', '0.0.4.4.0.0.4.4.') `
        -Drums @('K.ks.hKh.ks.hKh.', 'K.k.s.k.k.ks.k.s', 'K.ks.hKh.ks.hKh.', 'K.h.h.s.h.h.s.hK') `
        -Lead  @('4.4.3.3.2.2.0.0.', '9.8.7.6.4.3.2.0.', '0...7...4...2...', '4...4...7...7...')))

    # -------------------------------------------------------- MOTORHEAD
    $c.Add((New-Song -Band 'Motorhead' -Title 'Ace of Spades' -Style 'speed' -Bpm 170 -Root 40 -Minor $true -Prog @('0','0','8','0') `
        -Riff  @('0.0.0.0.4.4.4.4.', '0.0.0.0.0.0.0.0.', '1.1.1.1.4.4.4.4.', '0.0.0.0.2.2.2.2.') `
        -Drums @('Kkkk.s...kkk.s.k', 'K.k.s.k.k.ks.k.s', 'Kkkk.s...kkk.s.k', 'Kkkksssskkkkssss') `
        -Lead  @('4.4.4.4.7.7.7.7.', '7.6.4.3.2.1.0.0.', '9.8.7.6.4.3.2.0.', '4...4...7...7...')))

    # -------------------------------------------------------- THE WHO
    $c.Add((New-Song -Band 'The Who' -Title "Won't Get Fooled Again" -Style 'mod-punk' -Bpm 172 -Root 45 -Minor $false -Prog @('0','0','0','0') `
        -Riff  @('0.0.0.0.1.1.1.1.', '2.2.1.1.0.0.4.4.', '0.1.2.1.0.1.2.1.', '0.0.0.0.0.0.0.0.') `
        -Drums @('K.k.s.k.k.ks.k.s', 'Kkkk.s...kkk.s.k', 'K.k.s.k.k.ks.k.s', 'Kkkksssskkkkssss') `
        -Lead  @('4.4.4.4.2.2.2.2.', '0.2.3.4.3.2.0...', '7.7.9.9.7.7.4.4.', '4...4...7...7...')))

    # -------------------------------------------------------- LYNYRD SKYNYRD
    $c.Add((New-Song -Band 'Lynyrd Skynyrd' -Title 'Sweet Home Alabama' -Style 'southern' -Bpm 98 -Root 40 -Minor $true -Prog @('0','0','8','7') `
        -Riff  @('0..0.0..0.0.0...', '0.0.0.0.4.0.4.0.', '2.2.2.2.1.1.1.1.', '0.0.4.4.0.0.4.4.') `
        -Drums @('K..hs..hk..hs.kk', 'K...s...K...s...', 'K.ks.hKh.ks.hKh.', 'K...s.k.k...s.k.') `
        -Lead  @('0...4...3...2...', '4.4.7.7.9.9.7.7.', '7.6.4.3.2.1.0.0.', '0.2.3.4.3.2.0...')))

    # -------------------------------------------------------- JIMI HENDRIX
    $c.Add((New-Song -Band 'Jimi Hendrix' -Title 'Purple Haze' -Style 'funk' -Bpm 130 -Root 40 -Minor $true -Prog @('0','0','3','5') `
        -Riff  @('0.0.4.0.0.4.0.0.', '2.2.4.2.2.4.2.2.', '0.0.2.2.0.0.2.2.', '1.1.4.4.1.1.4.4.') `
        -Drums @('K...s...K...s...', 'K.ks.hKh.ks.hKh.', 'K.k.s.k.k.ks.k.s', 'K...s.k.k...s.k.') `
        -Lead  @('4.4.7.7.9.9.7.7.', '0...7...4...2...', '7.7.9.9.7.7.4.4.', '9.8.7.6.4.3.2.0.')))

    # -------------------------------------------------------- RUSH
    $c.Add((New-Song -Band 'Rush' -Title 'Tom Sawyer' -Style 'prog' -Bpm 120 -Root 45 -Minor $false -Prog @('0','0','5','3') `
        -Riff  @('0.0.0.0.4.4.0.0.', '2.2.2.2.3.3.1.1.', '0.1.2.3.4.3.2.1.', '0.0.4.4.2.2.1.1.') `
        -Drums @('K.hhs..hk.hhs.kh', 'K.k.s.k.k.ks.k.s', 'K.kks.k.kks.kks.', 'K...s...K...s...') `
        -Lead  @('0...2...4...5...', '4...4...7...7...', '7.6.4.3.2.1.0.0.', '0.0.7.7.9.9.7.7.')))

    # -------------------------------------------------------- ZZ TOP
    $c.Add((New-Song -Band 'ZZ Top' -Title 'La Grange' -Style 'blues-rock' -Bpm 122 -Root 40 -Minor $false -Prog @('0','0','0','0') `
        -Riff  @('0.0.1.0.1.0.4.0.', '0.0.4.0.4.0.1.0.', '2.2.1.2.1.2.4.2.', '0.0.1.1.0.0.4.4.') `
        -Drums @('K...s...K...s...', 'K.hhs..hk.hhs.kh', 'K...s.k.k...s.k.', 'K.k.s.k.k.ks.k.s') `
        -Lead  @('0...4...3...2...', '4.4.7.7.9.9.7.7.', '7...7...4...4...', '0.2.3.4.3.2.0...')))

    # -------------------------------------------------------- AEROSMITH
    $c.Add((New-Song -Band 'Aerosmith' -Title 'Dream On' -Style 'ballad' -Bpm 96 -Root 40 -Minor $true -Prog @('0','5','3','0') `
        -Riff  @('0...0...0...4...', '0.0.2.2.0.0.4.4.', '2.2.1.1.0.0.4.4.', '0.0.0.0.4.4.2.2.') `
        -Drums @('K...s...K...s...', 'K..hs..hk..hs.kk', 'K...s...K...s...', 'K.ks.hKh.ks.hKh.') `
        -Lead  @('0...7...4...2...', '4...4...7...7...', '7.6.4.3.2.1.0.0.', '0...4...3...2...')))

    return $c.ToArray()
}

function Get-BandCount {
    $h = @{}
    foreach ($s in $script:Catalog) { $h[$s.Band] = 1 }
    $h.Count
}
