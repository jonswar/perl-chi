package CHI::t::Sanity;
use CHI::Test;
use strict;
use warnings;
use base qw(CHI::Test::Class);

sub test_ok : Test(1) {
    ok( 1, '1 is ok' );
}

1;
