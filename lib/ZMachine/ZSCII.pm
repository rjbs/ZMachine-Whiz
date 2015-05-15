use v6;

class ZMachine::ZSCII {
  use ZMachine::Util;

  # The ZSCII codecs truck in these types:
  # * Unicode strings of input.  We need to be able to handle denormalized
  #   forms, in case people plan on doing really bizarre stuff with their
  #   Z-Machine's memory.
  # * ZSCII characters, which we represent as unsigned integers in ten bit
  #   space, and ZSCII buffers.
  # * Zchars, represented by bytes with values in five bit space
  # * Packed Zchars, in which a sequence of Zchars are packed three to a word,
  #   with the final word having its high bit set

  # XXX I'd like to subset the type to disallow things that won't fit in ten
  # bits, but when I do that, I get this error:
  #   MVMArray: bindpos expected object register
  # ...so I'm leaving it unconstrainted for now. -- rjbs, 2015-05-15
  #
  # subset ZSCII-Char of uint16 where * < 2 ** 10;

  my constant ZSCII-Char = uint16;
  my constant ZSCII-Buf  = Buf[ZSCII-Char];

  # subset Zchar of uint8 where * < 2 ** 5;
  my constant Zchar = uint8;
  my constant Zchars = Buf[Zchar];
  my constant PackedZchars = Buf[uint8];

  # This maps ZSCII-Char to Unicode character, and is defined in the spec.
  #
  # XXX I would have made this a hash over ZSCII-Char keys, but got the error:
  # Type check failed in binding key; expected 'uint16' but got 'Int'
  # -- rjbs, 2015-05-15
  #
  # XXX I also wanted to say "my constant %DEFAULT-ZSCII{Int}" but got the
  # error:
  # Missing initializer on constant declaration
  # -- rjbs, 2015-05-15
  my constant %DEFAULT-ZSCII := Hash[Str, Int].new(
    0x00 => "\c[NULL]",
    0x08 => "\c[DELETE]",
    0x0D => "\x0D",
    0x1B => "\c[ESCAPE]",

    (0x20 .. 0x7E).map({ $_ => .chr }), # ASCII maps over

    # 0x09B - 0x0FB are the "extra characters"; need Unicode translation table
    # 0x0FF - 0x3FF are undefined and never (?) used
  );

  # The "alphabet" is a codec-specific character set.  Most of the time, a
  # Zchar is a direct index into alphabet zero, the first 26 characters in the
  # alphabet.  Shift Zchars cause the next Zchar to pick from alphabet one or
  # two.  These 78 characters are stored in a sequence to pick from later.
  # -- rjbs, 2015-05-15
  #
  # XXX Since this stores ZSCII characters, probably it should be ZSCII-Buf and
  # not a Str, so I should look at redoing this later.  Probably what I want is
  # for the user to supply a Str or Uni, but for the alphabet to be immediately
  # translated to a ZSCII-Buf for storage. -- rjbs, 2015-05-15
  my constant $DEFAULT-ALPHABET = join('',
    'a' .. 'z', # A0
    'A' .. 'Z', # A1
    (           # A2
      "\0", # special: read 2 chars for 10-bit zscii character
      "\x0D",
      (0 .. 9),
      < . , ! ? _ # ' " / \ - : ( ) >,
    ),
  );

  # These are the default contents of the "Unicode translation table," which
  # enumerates the characters that can be used even though they are not in the
  # alphabet.  They are explicitly Unicode codepoints between 0 and 0xFFFF.
  my @DEFAULT-EXTRA = <
    E4 F6 FC C4 D6 DC DF BB       AB EB EF FF CB CF E1 E9
    ED F3 FA FD C1 C9 CD D3       DA DD E0 E8 EC F2 F9 C0
    C8 CC D2 D9

    E2 EA EE F4 FB C2 CA CE       D4 DB E5 C5 F8 D8 E3 F1
    F5 C3 D1 D5 E6 C6 E7 C7       FE F0 DE D0 A3 153 152 A1
    BF
  >.map({ :16($_).chr });

  # Making ZMachineVersion an Enum required using a constructor like
  # ZMachineVersion(5).  That seemed like a PITA. -- rjbs, 2015-05-15
  subset ZMachineVersion of Int where * == any(5,7,8);
  has ZMachineVersion $.version = 5;

  has %!zscii = %DEFAULT-ZSCII;

  has %!shortcut-for;

  # Why is this an arrayref and not, like alphabets, a string?
  # Alphabets are strings because they're guaranteed to fit in bytestrings.
  # You can't put a ZSCII character over 0xFF in the alphabet, because it can't
  # be put in the story file's alphabet table!  By using a string, it's easy to
  # just pass in the alphabet from memory to/from the codec.  On the other
  # hand, the Unicode translation table stores Unicode codepoint values packed
  # into words, and it's not a good fit for use in the codec.  Maybe a
  # ZMachine::Util will be useful for packing/unpacking Unicode translation
  # tables.
  has $!extra = @DEFAULT-EXTRA;

  has %!zscii-for;

  has $!alphabet = $DEFAULT-ALPHABET;

  sub validate-alphabet ($alphabet)  {
    return !!! "alphabet table was not 78 entries long"
      unless $alphabet.chars == 78;

    return !!! "alphabet character 52 not set to 0x000"
      unless $alphabet.substr(52, 1) eq 0.chr;

    return !!! "alphabet table contains characters over 0xFF"
      if $alphabet ~~ /<-[\x00..\xFF]>/;
  }

  sub shortcuts-for ($alphabet) {
    validate-alphabet($alphabet);

    my %shortcut = (q{ }.ord => Zchars.new(0));

    for (0 .. 2) -> $i {
      my $offset = $i * 26;

      for (0 .. 25) -> $j {
        next if $i == 2 and $j == 0; # that guy is magic! -- rjbs, 2013-01-18

        my $res = Zchars.new;
        $res[0] = 0x03 + $i if $i;

        $res[ +* ] = $j + 6;
        %shortcut{ $alphabet.substr($offset + $j, 1).ord } = $res;
      }
    }

    return %shortcut;
  }

  submethod BUILD {
    die "Unicode translation table exceeds maximum length of 97"
      if $!extra.elems > 97;

    # Why is this needed? -- rjbs, 2015-05-14
    %!zscii ||= %DEFAULT-ZSCII;

    for (0 .. $!extra.elems - 1) {
      die "tried to add ambiguous Z->U mapping"
        if %!zscii{ chr(155 + $_) }:exists;

      my $u-char = $!extra[$_];

      # Extra characters must go into the Unicode substitution table, which can
      # only represent characters with codepoints between 0 and 0xFFFF.  See
      # Z-Machine Spec v1.1 § 3.8.4.2.1
      die "tried to add Unicode codepoint greater than U+FFFF"
        if $u-char.ord > 0xFFFF;

      %!zscii{ 155 + $_ } = $u-char;
    }

    for %!zscii.keys.sort -> $zscii-char {
      my $unicode-char = %!zscii{$zscii-char};

      die "tried to add ambiguous U->Z mapping"
        if %!zscii-for{ $unicode-char }:exists;

      %!zscii-for{ $unicode-char } = $zscii-char;
    }

    # The default alphabet is entirely made up of characters that are the same
    # in Unicode and ZSCII.  If a user wants to put "extra characters" into the
    # alphabet table, though, the alphabet should contain ZSCII values.  When
    # we're building a ZMachine::ZSCII using the contents of the story file's
    # alphabet table, that's easy.  If we're building a codec to *produce* a
    # story file, it's less trivial, because we don't want to think about the
    # specific ZSCII codepoints for the Unicode text we'll encode.
    #
    # We provide alphabet_is_unicode to let the user say "my alphabet is
    # supplied in Unicode, please convert it to ZSCII during construction."
    # -- rjbs, 2013-01-19
    # my $alphabet = %arg<alphabet> || $DEFAULT-ALPHABET;

    # # It's okay if the user supplies alphabet_is_unicode but not alphabet,
    # # because the default alphabet is all characters with the same value in
    # # both character sets! -- rjbs, 2013-01-20
    # $alphabet = .unicode-to-zscii($alphabet)
    #   if $arg<alphabet_is_unicode>;

    %!shortcut-for = shortcuts-for($!alphabet || $DEFAULT-ALPHABET);
  }

# =method encode
#
#   my $packed_zchars = $z->encode( $unicode_text );
#
# This method takes a string of text and encodes it to a bytestring of packed
# Z-characters.
#
# Internally, it converts the Unicode text to ZSCII, then to Z-characters, and
# then packs them.  Before this processing, any native newline characters (the
# value of C<\n>) are converted to C<U+000D> to match the Z-Machine's use of
# character 0x00D for newline.
#
# =cut

  method encode (Str $string is copy) {
    $string ~~ s:g/\n/\x0D/;

    my $zscii  = $.unicode-to-zscii($string);
    my $zchars = $.zscii-to-zchars($zscii);

    return $.pack-zchars($zchars);
  }

# =method decode
#
#   my $text = $z->decode( $packed_zchars );
#
# This method takes a bytestring of packed Z-characters and returns a string of
# text.
#
# Internally, it unpacks the Z-characters, converts them to ZSCII, and then
# converts those to Unicode.  Any ZSCII characters 0x00D are converted to the
# value of C<\n>.
#
# =cut

  method decode (Buf $bytestring) {
    my $zchars  = $.unpack-zchars( $bytestring );
    my $zscii   = $.zchars-to-zscii( $zchars );
    my $unicode = $.zscii-to-unicode( $zscii );

    $unicode ~~ s:g/\x0D/\n/;

    return $unicode;
  }

# =method unicode_to_zscii
#
#   my $zscii_string = $z->unicode_to_zscii( $unicode_string );
#
# This method converts a Unicode string to a ZSCII string, using the dialect of
# ZSCII for the ZMachine::ZSCII's configuration.
#
# If the Unicode input contains any characters that cannot be mapped to ZSCII, an
# exception is raised.
#
# =cut

  multi method unicode-to-zscii (Str $unicode-text) {
    # This means that we will normalize your input!  Maybe very important!
    # -- rjbs, 2015-05-14
    $.unicode-to-zscii($unicode-text.NFC)
  }

  multi method unicode-to-zscii (Uni $unicode-text) {
    my $zscii = ZSCII-Buf.new;

    for $unicode-text.list>>.chr -> $char {
      die(
        sprintf "no ZSCII character available for Unicode U+%05X <%s>",
          $char.ord,
          uniname($char),
      ) unless defined( my $zscii-char = %!zscii-for{ $char } );

      $zscii[ +* ] = 0 + $zscii-char; # XXX want Buf.push
    }

    return $zscii;
  }

# =method zscii_to_unicode
#
#   my $unicode_string = $z->zscii_to_unicode( $zscii_string );
#
# This method converts a ZSCII string to a Unicode string, using the dialect of
# ZSCII for the ZMachine::ZSCII's configuration.
#
# If the ZSCII input contains any characters that cannot be mapped to Unicode, an
# exception is raised.  I<In the future, it may be possible to request a Unicode
# replacement character instead.>
#
# =cut

  method zscii-to-unicode(buf16 $zscii) {
    my $unicode = '';
    for (0 .. $zscii.elems - 1) {
      my $char = $zscii[$_];

      Carp::croak(
        sprintf "no Unicode character available for ZSCII %#v05x", $char,
      ) unless defined(my $unicode-char = %!zscii{ $char });

      $unicode ~= $unicode-char;
    }

    return $unicode;
  }

# =method zscii_to_zchars
#
#   my $zchars = $z->zscii_to_zchars( $zscii_string );
#
# Given a string of ZSCII characters, this method will return a (unpacked) string
# of Z-characters.
#
# It will raise an exception on ZSCII codepoints that cannot be represented as
# Z-characters, which should not be possible with legal ZSCII.
#
# =cut

  method zscii-to-zchars (ZSCII-Buf $zscii) {
    my $zchars = Zchars.new;
    return $zchars unless $zscii.elems;

    for $zscii.list -> $zscii-char {
      if (defined (my $shortcut = %!shortcut-for{ $zscii-char })) {
        $zchars[ +* .. * ] = $shortcut.list; # XXX want Buf.push or ~=
        next;
      }

      my $top = ($zscii-char +& 0b1111100000) +> 5;
      my $bot = ($zscii-char +& 0b0000011111);

      # XXX this +*..* construction is a bit beyond the pale
      $zchars[ +* .. * ] = (5, 6, $top, $bot); # The escape code for a ten-bit ZSCII character.
    }

    return $zchars;
  }

# =method zchars_to_zscii
#
#   my $zscii = $z->zchars_to_zscii( $zchars_string, \%arg );
#
# Given a string of (unpacked) Z-characters, this method will return a string of
# ZSCII characters.
#
# It will raise an exception when the right thing to do can't be determined.
# Right now, that could mean lots of things.
#
# Valid arguments are:
#
# =begin :list
#
# = allow_early_termination
#
# If C<allow_early_termination> is true, no exception is thrown if the
# Z-character string ends in the middle of a four z-character sequence.  This is
# useful when dealing with dictionary words.
#
# =end :list
#
# =cut

  # XXX surely this is not how to do named args
  method zchars-to-zscii (Zchars $zchars, $arg = {}) {
    my $zscii = ZSCII-Buf.new;
    my $alphabet = 0;

    my $pos = 0;
    while ($pos < $zchars.elems) {
      NEXT { $pos++ }

      my $zchar = $zchars[$pos];

      if ($zchar == 0) { $zscii[ +* ] = 0x20; next; } # XXX want Buf.push

      if    ($zchar == 0x04) { $alphabet = 1; next }
      elsif ($zchar == 0x05) { $alphabet = 2; next }

      if ($alphabet == 2 && $zchar == 0x06) {
        if ($zchars.elems < $pos + 2) {
          last if $arg<allow_early_termination>;
          die("ten-bit ZSCII encoding segment terminated early")
        }

        my $next_two = $zchars[ ++$pos, ++$pos ];

        my $value = $next_two[0] +< 5
                  | $next_two[1];

        $zscii[ +* ] = $value;
        $alphabet = 0;
        next;
      }

      if ($zchar >= 0x06 && $zchar <= 0x1F) {
        $!alphabet = $DEFAULT-ALPHABET; # XXX <-- due to init being hosed
        my $index = 26 * $alphabet + $zchar - 6;
        $zscii[ +* ] = $!alphabet.substr($index, 1).ord;
        $alphabet = 0;
        next;
      }

      die("unknown zchar <{$zchar}> encountered in alphabet <{$alphabet}>");
    }

    return $zscii;
  }

# =method make_dict_length
#
#   my $zchars = $z->make_dict_length( $zchars_string )
#
# This method returns the Z-character string fit to dictionary length for the
# Z-machine version being handled.  It will trim excess characters or pad with
# Z-character 5 to be the right length.
#
# When converting such strings back to ZSCII, you should pass the
# C<allow_early_termination> to C<zchars_to_zscii>, as a four-Z-character
# sequence may have been terminated early.
#
# =cut
#
# sub make_dict_length {
#   my ($self, $zchars) = @_;
#
#   my $length = $self->{version} >= 5 ? 9 : 6;
#   $zchars = substr $zchars, 0, $length;
#   $zchars .= "\x05" x ($length - length($zchars));
#
#   return $zchars;
# }

# =method pack_zchars
#
#   my $packed_zchars = $z->pack_zchars( $zchars_string );
#
# This method takes a string of unpacked Z-characters and packs them into a
# bytestring with three Z-characters per word.  The final word will have its top
# bit set.
#
# =cut

  method pack-zchars(Zchars $zchars) {
    my $packed = PackedZchars.new;

    my $loops = 0;
    for $zchars.rotor(3, :partial) -> @input {
      $loops++;
      my @triple is default(5) = @input;

      my $value = @triple[0] +< 10
               +| @triple[1] +<  5
               +| @triple[2];

      $value +|= (0x8000) if $loops * 3 >= $zchars.elems;

      my $top    = $value +> 8;
      my $bottom = $value +& 255;
      $packed[ +* .. * ] = ($top, $bottom); # XXX desperately wanting Buf.push
    }

    return $packed;
  }

# =method unpack_zchars
#
#   my $zchars_string = $z->pack_zchars( $packed_zchars );
#
# Given a bytestring of packed Z-characters, this method will unpack them into a
# string of unpacked Z-characters that aren't packed anymore because they're
# unpacked instead of packed.
#
# Exceptions are raised if the input bytestring isn't made of an even number of
# octets, or if the string continues past the first word with its top bit set.
#
# =cut

  method unpack-zchars (PackedZchars $packed) {
    die "bytestring of packed zchars is not an even number of bytes"
      unless $packed.elems %% 2;

    my $terminate;
    my $zchars = Zchars.new;
    for $packed.rotor(2) -> $word {
      # XXX: Probably allow this to warn and `last` -- rjbs, 2013-01-18
      die "input continues after terminating byte" if $terminate;

      my $n = $word[0] +< 8
            + $word[1];
      $terminate = $n +& 0x8000;

      my $c1 = ($n +& 0b0111110000000000) +> 10;
      my $c2 = ($n +& 0b0000001111100000) +>  5;
      my $c3 = ($n +& 0b0000000000011111)      ;

      $zchars ~= Zchars.new($c1, $c2, $c3);
    }

    return $zchars;
  }

}
