use v6;
use lib 'lib';
use ZMachine::File;
use ZMachine::Util;
use ZMachine::Story;
use ZMachine::ZSCII;

my $story = ZMachine::Story.new(
  serial => '150502',
);

$story.write-to-file('a-out.z5');
