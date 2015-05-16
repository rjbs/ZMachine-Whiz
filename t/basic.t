use v6;
use Test;

use ZMachine::ZSCII;

sub four-zchars ($zscii-chr) {
  my $top = ($zscii-chr +& 0b1111100000) +> 5;
  my $bot = ($zscii-chr +& 0b0000011111);

  return (5, 6, $top, $bot);
}

sub mkbuf ($buf-type, @hex-digits) { return Buf[$buf-type].new(@hex-digits.map: { :16($_) }); }

my $z = ZMachine::ZSCII.new(version => 5);
ok(1, "this ran");

{
  my $text = "Hello, world.\n";

  {
    my $string = $text;
    $string ~~ s:g/\n/\x0D/;
    my $zscii = $z.unicode-to-zscii($string);

    is-deeply(
      $zscii,
      mkbuf(uint16, <48 65 6c 6c 6f 2c 20 77 6f 72 6c 64 2E 0D>),
      "unicode-to-zscii works on a trivial string",
    );

    my $zchars = $z.zscii-to-zchars($zscii);

    is-deeply(
      $zchars,
                 #      H  e  l  l  o     , __  w  o  r  l  d     .    \n
      mkbuf(uint8, <04 0D 0A 11 11 14 05 13 00 1C 14 17 11 09 05 12 05 07>),
      "zscii-to-zchars on a trivial string",
    );

    my $packed = $z.pack-zchars($zchars);
    is-deeply(
      $packed,
      mkbuf(uint8, <11 AA 46 34 16 60 72 97 45 25 C8 A7>),
      "pack-zchars on a trivial string"
    );
  }

  my $ztext = $z.encode($text);

  is-deeply(
    $ztext,
    mkbuf(uint8, <11 AA 46 34 16 60 72 97 45 25 C8 A7>),
    "compared"
  );

  my $zchars = $z.unpack-zchars( $ztext );
  my $want   = mkbuf(uint8,
                #      H  e  l  l  o     , __  w  o  r  l  d     .    \n
                <  04 0D 0A 11 11 14 05 13 00 1C 14 17 11 09 05 12 05 07>);

  # XXX: Make a patch to eq_or_diff to let me tell it to sprintf the results.
  # -- rjbs, 2013-01-18
  is-deeply(
    $zchars,
    $want,
    "zchars from encoded 'Hello, World.'",
  );

  my $have_text = $z.decode($ztext);

  is($have_text, $text, q{we round-tripped "Hello, world.\n"!});
}

subtest {
  is(
    $z.unicode-to-zscii("\c[LEFT-POINTING DOUBLE ANGLE QUOTATION MARK]"), # «
    buf16.new(163),
    "naughty French opening quote: U+00AB, Z+0A3",
  );

  is(
    $z.unicode-to-zscii("\c[RIGHT-POINTING DOUBLE ANGLE QUOTATION MARK]"), # »
    buf16.new(162),
    "naughty French opening quote: U+00AB, Z+0A2",
  );

  my $orig    = "«¡Gruß Gott!»";

  my $zscii   = $z.unicode-to-zscii( $orig );
  is-deeply(
    $zscii,
    mkbuf(uint16, <a3 de 47 72 75 a1 20 47 6f 74 74 21 a2>),
                 #  «  ¡  G  R  u  ß __  G  o  t  t  !  »
    "converted Unicode string of Latin-1 chars to ZSCII",
  );

  is($zscii.elems, 13, "the string is 13 ZSCII characters");

  my $zchars  = $z.zscii-to-zchars( $zscii );

  my $want-zchars = buf8.new(
    four-zchars(163),      # ten-bit char 163
    four-zchars(222),      # ten-bit char 222
    <04 0C 17 1A>>>.map({ :16($_) }),         # G r u
    four-zchars(161),      # ten-bit char 161
    <00 04 0C 14 19 19 05 14>>>.map({ :16($_) }), # _ G o t t !
    four-zchars(162), # ten-bit char 162
  );

  is_deeply(
    $zchars,
    $want-zchars,
    "...then the ZSCII to Z-characters",
  );

  is($zchars.elems, 28, "...there are 28 Z-characters for the 14 ZSCII");

  my $packed  = $z.pack-zchars($zchars);
  is($packed.elems, 20, "28 Z-characters pack to 10 words (20 bytes)");

  # 20 bytes could, at maximum, encode 30 zchars, which means we'll expect two
  # padding zchars at the end

  my $unpacked = $z.unpack-zchars($packed);
  is($unpacked.elems, 30, "once unpacked, we've got 30; 2 are padding");

  is-deeply(
    $unpacked,
    buf8.new( $want-zchars.list, 5, 5),
    "we use Z+005 for padding",
  );

  my $zscii-again = $z.zchars-to-zscii($unpacked);
  is($zscii-again.elems, 13, "paddings ignored; as ZSCII, 13 chars again");

  my $unicode = $z.zscii-to-unicode($zscii-again);
  is($unicode, $orig, "...and we finish the round trip!");

  {
    my $ztext   = $z.encode($orig);
    my $unicode = $z.decode($ztext);
    is($unicode, $orig, "it round trips in isolation, too");
  }
}, "default extra characters in use";

subtest {
  dies-ok(
    sub { my $zscii = $z.unicode-to-zscii("Ameri☭ans") },
    "we have no HAMMER AND SICKLE (☭) by default",
  );

  my $soviet-z = ZMachine::ZSCII.new(
    :version(5),
    :unicode-table( < Ж ÿ ☭ > ),
  );

  my $zscii = $soviet-z.unicode-to-zscii("Ameri☭ans");
  ok($zscii, "we can encode HAMMER AND SICKLE if we make it an extra");

  is($zscii[5], 157, "the H&S is ZSCII 157");
  is($zscii.elems, 9, "there are 8 ZSCII charactrs");
  is-deeply(
    $zscii,
    Buf[uint16].new("Ameri\x[9D]ans".split('')>>.ord),
    "...and they're what we expect too",
  );

  my $zchars = $soviet-z.zscii-to-zchars($zscii);

  my $want-zchars = buf8.new(
    <04 06 12 0A 17 0E>>>.map({ :16($_) }),
    four-zchars(157),
    <06 13 18>>>.map({ :16($_) }),
  );

  is-deeply(
    $zchars,
    $want-zchars,
     "...then the ZSCII to Z-characters",
  );

  my $zscii-again = $soviet-z.zchars-to-zscii($zchars);

  is-deeply($zscii-again, $zscii, "ZSCII->zchars->ZSCII round tripped");

  is(
    $soviet-z.decode( $soviet-z.encode("Ameri☭ans") ),
    "Ameri☭ans",
    "...and we can round trip it",
  );
}, "custom extra characters";

subtest {
  my $a2_19   = "☭";
  my $ussr-z  = ZMachine::ZSCII.new(
    :version(5),
    :unicode-table(< Ж ÿ ☭ >),
    alphabet => "ABCDEFGHIJLKMNOPQRSTUVWXYZ"
              ~ "zyxwvutsrqponmlkjihgfedcba"
              ~ "\0\x[0D]0123456789.,!?_#'{$a2_19}/\\-:()",
  );

  my $zscii = $ussr-z.unicode-to-zscii("Ameri☭ans");

  is($zscii[5], 157, "the H&C is ZSCII 157");
  is($zscii.elems, 9, "there are 8 ZSCII charactrs");
  is-deeply(
    $zscii,
    Buf[uint16].new("Ameri\x[9D]ans".split('')>>.ord),
    "...and they're what we expect too",
  );

  my $zchars = $ussr-z.zscii-to-zchars($zscii);

  is-deeply(
    $zchars,
    buf8.new(
      <06 04 13 04 1B 04 0E 04 17>>>.map({ :16($_) }),
      <05 19 >>>.map({ :16($_) }), # not four_zchars because we put it at A2-19
      <04 1F 04 12 04 0D>>>.map({ :16($_) }),
    );
    "...then the ZSCII to Z-characters",
  );
}, "custom alphabet";

subtest {
  {
    my $word = "cable";
    my $zchars = $z.zscii-to-zchars( $z.unicode-to-zscii( $word ) );

    is($zchars.elems, 5, "as zchars, 'cable' is 5 chars");

    my $dict-cable = $z.make-dict-length($zchars);
    is($dict-cable.elems, 9, "trimmed to length, it is nine");

    is-deeply(
      $dict-cable.subbuf(0, 5),
      $zchars,
      "the first five are the word"
    );

    is-deeply(
      $dict-cable.subbuf(6, 3),
      Buf[uint8].new(5,5,5),
      "the rest are x05",
    );
  }

  {
    my $word = "twelve-inch"; # You know, like the cable.
    my $zchars = $z.zscii-to-zchars( $z.unicode-to-zscii( $word ) );

    is($zchars.elems, 12, "as zchars, 'twelve-inch' is 12 chars");

    my $dict_12i = $z.make-dict-length($zchars);
    is($dict_12i.elems, 9, "trimmed to length, it is nine");
  }

  {
    my $word = "queensrÿche";
             #  12345678CDE
    my $zchars = $z.zscii-to-zchars( $z.unicode-to-zscii( $word ) );

    is($zchars.elems, 14, "as zchars, band name is 14 chars");

    my $dict-ryche = $z.make-dict-length($zchars);
    is($dict-ryche.elems, 9, "trimmed to length, it is nine");

    {
      throws-like(
        sub { my $zscii = $z.zchars-to-zscii( $dict-ryche ); },
        X::AdHoc,
        message => /terminated.early/,
        "we can't normally decode a word terminated mid-sequence",
      );
    }

    {
      my $zscii = $z.zchars-to-zscii($dict-ryche, :allow-early-termination);
      is-deeply(
        $zscii,
        Buf[uint16].new("queensr".encode('ASCII').list),
        "...but we can if we pass allow_early_termination",
      )
    }
  }
}, "test dictionary words";

{
  throws-like(
    sub { my $fail-z = ZMachine::ZSCII.new(version => 1); },
    X::AdHoc,
    message => /version/,
    "can't make a v1 ZSCII codec (yet?)",
  );
}
