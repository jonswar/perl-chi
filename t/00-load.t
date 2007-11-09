#!perl -T

use Test::More tests => 1;

BEGIN {
	use_ok( 'CHI' );
}

diag( "Testing CHI $CHI::VERSION, Perl $], $^X" );
