use v6;

my $fh = open q{a-out.z5}, :w;

my $FILESIZE = 0xF000;

$fh.print( chr(0) x $FILESIZE );

multi sub mkword (Int $i) { pack 'n', $i }
multi sub mkword (Any $i) { pack 'n', $i.Int }
multi sub mkbyte (Int $i) { Buf.new( $i ) }
multi sub mkbyte (Any $i) { Buf.new( $i.Int ) }

sub write-at ($pos, *@bufs) {
  $fh.seek($pos, 0);
  my $written = 0;
  $written += $fh.write($_) for @bufs;
  return $written ?? $written !! fail("nothing got written");
}

my %for = (
  ' '  => [ 0x20 ],
  '.'  => [ 0x05, 0x12 ],
  ','  => [ 0x05, 0x13 ],
  '!'  => [ 0x05, 0x14 ],
  "\n" => [ 0x05, 0x07 ],
  (map { chr(ord('a') + $_) => [       6 + $_ ] } <== (0 .. 25)),
  (map { chr(ord('A') + $_) => [ 0x04, 6 + $_ ] } <== (0 .. 25)),
);

sub to-zscii (Str $string) {
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

## START HEADER
mkbyte(5);

write-at(0x00, mkbyte(5));      # story file version
write-at(0x04, mkword(0x1230)); # base address of high memory
write-at(0x06, mkword(0x4500)); # PC initial value
write-at(0x08, mkword(0x1000)); # address of dictionary
write-at(0x0A, mkword(0x2000)); # address of object table
write-at(0x0C, mkword(0x3000)); # address of global variables table
write-at(0x0E, mkword(0x4000)); # base address of static memory
write-at(0x12, '130116'.encode('ascii'));    # serial number
write-at(0x18, mkword(0x5000)); # address of abbreviations table
write-at(0x1A, mkword($FILESIZE / 4)); # length of file (divided by 4, in v5)

write-at(0x28, mkword(0x6000 / 8)); # routines offset (divided by 8)
write-at(0x2A, mkword(0x7000 / 8)); # static strings offset (divided by 8)

write-at(0x2C, mkbyte(0));      # default bg
write-at(0x2D, mkbyte(1));      # default fg

write-at(0x2E, mkword(0x8000)); # address of terminating characters table

write-at(0x34, mkword(0x0000)); # address of alphabet table (0 = default)

write-at(0x36, mkword(0x0000)); # address of header extension table; (0 = none)

## END HEADER

write-at(0x4000, to-zscii("Goodbye!\n"));

my $hello = to-zscii("Hello, world.\n");

write-at(0x4500,
  mkbyte(0xb2), $hello,       # print
  mkbyte(0x87), mkword(0x4000), # print_addr
  mkbyte(186),                  # quit
);

$fh.close;
