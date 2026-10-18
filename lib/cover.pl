#!/usr/bin/perl
# lotus – album cover → terminal art (lib/art.zsh). Reads a BMP that sips made, writes one line
# per terminal row: two pixels per cell in the cover's own colors – never the theme's. The top
# pixel is the background, the bottom one the character ▄: terminals that draw ▄ with the font
# (Terminal.app) leave a thin gap above it, and that gap then has the top pixel's color.
#   perl cover.pl <file.bmp> <columns> <rows> <tc|256>
# The art is as big as fits into columns × rows and keeps the picture's shape. The BMP is a few
# times bigger than the art: every pixel of the art is the average of a block of image pixels
# (in linear light), so fine details blend instead of flickering.
use strict;
use warnings;

my ($file, $cols, $rows, $mode) = @ARGV;
open(my $fh, '<:raw', $file) or exit 1;
local $/;
my $bmp = <$fh>;
close $fh;
exit 1 if length($bmp) < 54 || substr($bmp, 0, 2) ne 'BM';

my ($offset) = unpack('V', substr($bmp, 10, 4));
my ($w, $h) = unpack('l<l<', substr($bmp, 18, 8));
my ($bpp) = unpack('v', substr($bmp, 28, 2));
exit 1 unless $bpp == 24 || $bpp == 32;
my $topdown = $h < 0;
$h = -$h if $topdown;
my $bytes = $bpp / 8;
my $stride = int(($w * $bytes + 3) / 4) * 4;
exit 1 if $w < 1 || $h < 1 || $cols < 1 || $rows < 1 || length($bmp) < $offset + $stride * $h;

# Fit the picture: a cell is one pixel wide and two pixels tall
my $scale = $cols / $w < 2 * $rows / $h ? $cols / $w : 2 * $rows / $h;
$cols = int($w * $scale + 0.5) || 1;
$rows = int($h * $scale / 2 + 0.5) || 1;
my $ph = $rows * 2;

# sRGB ↔ linear light
my @lin = map { my $c = $_ / 255; $c <= 0.04045 ? $c / 12.92 : (($c + 0.055) / 1.055) ** 2.4 } 0 .. 255;
sub srgb {
  my $v = shift;
  $v = $v <= 0.0031308 ? $v * 12.92 : 1.055 * $v ** (1 / 2.4) - 0.055;
  $v = int($v * 255 + 0.5);
  return $v < 0 ? 0 : $v > 255 ? 255 : $v;
}

# Average color of art pixel (x, y) → "r;g;b"
sub pixel {
  my ($x, $y) = @_;
  my ($x0, $x1) = (int($x * $w / $cols), int(($x + 1) * $w / $cols));
  my ($y0, $y1) = (int($y * $h / $ph), int(($y + 1) * $h / $ph));
  $x1 = $x0 + 1 if $x1 <= $x0;
  $y1 = $y0 + 1 if $y1 <= $y0;
  my ($r, $g, $b, $n) = (0, 0, 0, 0);
  for my $yy ($y0 .. $y1 - 1) {
    my $row = $offset + $stride * ($topdown ? $yy : $h - 1 - $yy);
    for my $xx ($x0 .. $x1 - 1) {
      my ($bb, $gg, $rr) = unpack('C3', substr($bmp, $row + $xx * $bytes, 3));
      $r += $lin[$rr]; $g += $lin[$gg]; $b += $lin[$bb]; $n++;
    }
  }
  return join(';', srgb($r / $n), srgb($g / $n), srgb($b / $n));
}

# "r;g;b" → color code: 24-bit, or the nearest of the 256 colors (same rule as lotus_sgr)
sub code {
  my ($rgb, $layer) = @_;
  return "$layer;2;$rgb" if $mode eq 'tc';
  my ($r, $g, $bl) = split /;/, $rgb;
  my ($hi, $lo) = ($r, $r);
  for ($g, $bl) { $hi = $_ if $_ > $hi; $lo = $_ if $_ < $lo }
  my $n = $hi - $lo < 12
    ? ($r < 8 ? 16 : $r > 238 ? 231 : 232 + int(($r - 8) / 10))
    : 16 + 36 * int(($r * 5 + 127) / 255) + 6 * int(($g * 5 + 127) / 255) + int(($bl * 5 + 127) / 255);
  return "$layer;5;$n";
}

binmode STDOUT, ':raw';
for my $r (0 .. $rows - 1) {
  my ($line, $fg, $bg) = ('', '', '');
  for my $c (0 .. $cols - 1) {
    my $top = code(pixel($c, 2 * $r), 48);
    my $bot = code(pixel($c, 2 * $r + 1), 38);
    my @set;
    push @set, $bot if $bot ne $fg;
    push @set, $top if $top ne $bg;
    $line .= "\e[" . join(';', @set) . 'm' if @set;
    ($fg, $bg) = ($bot, $top);
    $line .= "\xe2\x96\x84";    # ▄
  }
  print "$line\e[0m\n";
}
