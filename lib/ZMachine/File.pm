use v6;

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

  method close { $.fh.close }

  method write-at ($pos, *@bufs) {
    $.fh.seek($pos, 0);
    my $written = 0;
    $written += $.fh.write($_) for @bufs;
    return $written ?? $written !! fail("nothing got written");
  }
}
