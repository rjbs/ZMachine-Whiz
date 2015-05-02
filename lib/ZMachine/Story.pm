use v6;
class ZMachine::Story {
  use ZMachine::File;
  use ZMachine::Util;
  use ZMachine::ZSCII;

  has $.serial;

  method write-to-file($filename) {
    my $file  = ZMachine::File.new(filename => $filename);

    my $zscii = ZMachine::ZSCII.new;

    $file.fh.print( chr(0) x $file.filesize );

    ## START HEADER
    $file.write-at(0x00, mkbyte(5));      # story file version
    $file.write-at(0x04, mkword(0x1230)); # base address of high memory
    $file.write-at(0x06, mkword(0x4500)); # PC initial value
    $file.write-at(0x08, mkword(0x1000)); # address of dictionary
    $file.write-at(0x0A, mkword(0x2000)); # address of object table
    $file.write-at(0x0C, mkword(0x3000)); # address of global variables table
    $file.write-at(0x0E, mkword(0x4000)); # base address of static memory
    $file.write-at(0x12, '130116'.encode('ascii'));    # serial number
    $file.write-at(0x18, mkword(0x5000)); # address of abbreviations table
    $file.write-at(0x1A, mkword($file.filesize / 4)); # length of file (divided by 4, in v5)

    $file.write-at(0x28, mkword(0x6000 / 8)); # routines offset (divided by 8)
    $file.write-at(0x2A, mkword(0x7000 / 8)); # static strings offset (divided by 8)

    $file.write-at(0x2C, mkbyte(0));      # default bg
    $file.write-at(0x2D, mkbyte(1));      # default fg

    $file.write-at(0x2E, mkword(0x8000)); # address of terminating characters table

    $file.write-at(0x34, mkword(0x0000)); # address of alphabet table (0 = default)

    $file.write-at(0x36, mkword(0x0000)); # address of header extension table; (0 = none)
    ## END HEADER

    $file.write-at(0x4000, $zscii.to-zscii("Goodbye!\n"));

    my $hello = $zscii.to-zscii("Hello, world.\n");

    $file.write-at(0x4500,
      mkbyte(0xb2), $hello,       # print
      mkbyte(0x87), mkword(0x4000), # print_addr
      mkbyte(186),                  # quit
    );

    $file.close;
  }
}
