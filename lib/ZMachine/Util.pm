use v6;
use experimental :pack;

module ZMachine::Util {
  proto mkword($) is export {*}
  multi sub mkword (Int $i) { pack 'n', $i }
  multi sub mkword (Any $i) { pack 'n', $i.Int }

  proto mkbyte($) is export {*}
  multi sub mkbyte (Int $i) { Buf.new( $i ) }
  multi sub mkbyte (Any $i) { Buf.new( $i.Int ) }
}
