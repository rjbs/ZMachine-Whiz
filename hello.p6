use v6;
use lib 'lib';
use ZMachine::File;
use ZMachine::Util;
use ZMachine::Story;
use ZMachine::ZSCII;

my $string = q:to/END/;
# hello.zasm  --  Hello world for zasm
routine _start 0 {
  print "Hello, world.\n"
  quit 0
}
END

say $string;
say '-' x 70;

grammar zasm {
  rule TOP {
    <.ws>
    <routine>
  }

  rule routine {
    'routine' <routinename> <arity> '{' "\n"
      <statement>* %% "\n"+ # that %% is saying "each 
    '}' "\n"
  }

  token routinename {
    '_start' | 'start'
  }

  token arity {
   '0'
  }

  rule statement {
    <op> <oparg>
  }

  token op {
    'print' | 'ret' | 'quit'
  }

  token oparg { <zero> | <heya> }

  token zero { '0' }
  token heya { '"Hello, world.\n"' }

  token ws {
    <!ww>
    [
    | \h
    | '#' \N* \n
    ]*
  }
}

class Actions {
  method op ($/) {
    state %opcode-for = (
      print => 0xb2,
      quit  => 186,
    );

    # ¿¿who said perl has too much punctuation??
    $/.make( mkbyte(%opcode-for{ ~$/ }) );
  }

  method heya ($/) { $/.make( $.story.encode-string(~$/) ) }
  method zero ($/) { $/.make( mkbyte(0) ) }

  method oparg ($/) { $/.make($<heya>.?made // $<zero>.?made) }

  has $.story is required;

  method statement ($/) {
    # if oparg is zero -> make opcode ~ byte(0)
    # if oparg is heya -> make opcode ~ encode-str(heya)

    say $<op>.made;
    say $<oparg>.made;
    $/.make( $<op>.made ~ $<oparg>.made );
  }

  method TOP ($/) {
    $/.make($<routine>.made);
  }

  method routine ($/) {
    $/.make({
      name => ~ $<routinename>,
      body => [~] $/<statement>.map(*.made)
    });
  }
}

my $start = q:to/END/;
# What up, dog?
routine start 0 {
  print "Hello, world.\n"
  quit 0
}
END

my $story = ZMachine::Story.new;
my $actions = Actions.new(:$story);

my $routine = zasm.parse($start, :$actions).?made;

$routine.say;

!!! "* * * You have died. * * *" unless $routine;

$story.add-routine($routine<name>, $routine<body>);
$story.write-to-file('a-out.z5');
