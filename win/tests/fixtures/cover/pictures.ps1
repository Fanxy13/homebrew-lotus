# The pictures the album cover tests draw, made here so that no binary file has to be kept: 24 and 32 bit BMPs, bottom-up
# and top-down. expected.tsv holds the SHA-256 of what lib/cover.pl makes of each (regenerate.ps1 writes it).

# A BMP of <Width> × <Height>: <Pixel> is called with x and y and gives (r, g, b)
function New-CoverBmp {
    param([int]$Width, [int]$Height, [scriptblock]$Pixel, [int]$Bits = 24, [switch]$TopDown)
    $bpp = $Bits / 8
    $stride = [int]([Math]::Floor(($Width * $bpp + 3) / 4) * 4)
    $data = [byte[]]::new($stride * $Height)
    for ($y = 0; $y -lt $Height; $y++) {
        $line = if ($TopDown) { $y } else { $Height - 1 - $y }
        for ($x = 0; $x -lt $Width; $x++) {
            $c = & $Pixel $x $y
            $o = $line * $stride + $x * $bpp
            $data[$o] = [byte]$c[2]; $data[$o + 1] = [byte]$c[1]; $data[$o + 2] = [byte]$c[0]
            if ($bpp -eq 4) { $data[$o + 3] = 255 }
        }
    }
    $ms = [System.IO.MemoryStream]::new()
    $w = [System.IO.BinaryWriter]::new($ms)
    $w.Write([byte[]](0x42, 0x4D)); $w.Write([uint32](54 + $data.Length)); $w.Write([uint32]0); $w.Write([uint32]54)
    $w.Write([uint32]40); $w.Write([int32]$Width); $w.Write([int32]$(if ($TopDown) { -$Height } else { $Height }))
    $w.Write([uint16]1); $w.Write([uint16]$Bits); $w.Write([uint32]0); $w.Write([uint32]$data.Length)
    $w.Write([int32]2835); $w.Write([int32]2835); $w.Write([uint32]0); $w.Write([uint32]0)
    $w.Write($data); $w.Flush()
    , $ms.ToArray()
}

# name → the BMP
function Get-CoverPictures {
    $p = [ordered]@{}
    # an orange disc on a gradient (the test picture of Remove BG)
    $p['disc'] = New-CoverBmp 96 64 { param($x, $y) if ((($x - 48) * ($x - 48) + ($y - 32) * ($y - 32)) -lt 400) { 230, 120, 60 } else { (40 + [int]($y * 0.9)), (60 + [int]($x * 0.5)), 90 } }
    # four colors in four quarters
    $p['quarters'] = New-CoverBmp 64 64 { param($x, $y) if ($y -lt 32) { if ($x -lt 32) { 200, 30, 30 } else { 30, 200, 30 } } else { if ($x -lt 32) { 30, 30, 200 } else { 220, 220, 30 } } }
    # 32 bit, top-down, a tall one
    $p['stripes'] = New-CoverBmp 37 53 { param($x, $y) (($x * 7) % 256), (255 - ($x * 7) % 256), (($y * 5) % 256) } -Bits 32 -TopDown
    # almost nothing
    $p['tiny'] = New-CoverBmp 3 2 { param($x, $y) (($x * 90) % 256), (($y * 120) % 256), 77 }
    $p
}

# name, columns, rows, mode → what is drawn
function Get-CoverCases {
    @(
        @('disc', 20, 10, 'tc'), @('disc', 20, 10, '256'), @('disc', 44, 22, 'tc'), @('disc', 6, 3, 'tc')
        @('quarters', 16, 8, 'tc'), @('quarters', 16, 8, '256'), @('quarters', 40, 5, 'tc')
        @('stripes', 20, 10, 'tc'), @('stripes', 20, 10, '256'), @('stripes', 8, 20, 'tc')
        @('tiny', 12, 6, 'tc'), @('tiny', 12, 6, '256')
    )
}
