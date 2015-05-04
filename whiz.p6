use v6;
use lib 'lib';
use ZMachine::File;
use ZMachine::Util;
use ZMachine::Story;
use ZMachine::ZSCII;

my $story = ZMachine::Story.new;

my $pos = $story.add-string('goodbye', "Goodbye!\n");

my $hello = $story.encode-string("Hello, world.\n");

my $start-routine = mkbyte(0xb2) ~ $hello       # print
                  ~ mkbyte(0x87) ~ mkword($pos) # print_addr
                  ~ mkbyte(186);                # quit

$story.add-routine('start', $start-routine);

$story.write-to-file('a-out.z5');
