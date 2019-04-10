use v6;
# vim: ft=perl6

class ZMachine::File {
  has $.filename = !!! "filename not specified";
  has $.filesize = 0xF000;

  # has $.fh = lazy { say 123 };
  has $!fh;
  method fh {
    return $!fh if $!fh;
    $!fh = open $.filename, :w;
    $!fh.print( chr(0) x $.filesize );
    return $!fh;
  }

  method seek-to (Int $pos) {
    $.fh.seek($pos, SeekFromBeginning);
  }

  method close { $.fh.close }

  method write-at ($pos, *@bufs) {
    $.seek-to($pos);
    my $written = 0;
    $written += $.fh.write($_) for @bufs;
    return $written ?? $written !! fail("nothing got written");
  }
}
