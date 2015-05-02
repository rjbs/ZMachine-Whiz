use v6;

class ZMachine::ZSCII {
  use ZMachine::Util;

  my %for = (
    ' '  => [ 0x20 ],
    '.'  => [ 0x05, 0x12 ],
    ','  => [ 0x05, 0x13 ],
    '!'  => [ 0x05, 0x14 ],
    "\n" => [ 0x05, 0x07 ],
    (map { chr(ord('a') + $_) => [       6 + $_ ] } <== (0 .. 25)),
    (map { chr(ord('A') + $_) => [ 0x04, 6 + $_ ] } <== (0 .. 25)),
  );

  method to-zscii (Str $string) {
    my $result = Buf.new();

    my @zchars = map { die "unknown char $_" unless %for{$_}; %for{ $_ }.list },
                 $string.comb;

    my @values = map -> $c0 = 5, $c1 = 5, $c2 = 5 {
         $c0 +< 10
      +| $c1 +<  5
      +| $c2;
    }, @zchars;

    @values[*-1] +|= 0x8000;

    $result = [~] map { mkword($_) }, @values;

    return $result;
  }
}
