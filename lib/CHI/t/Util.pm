package CHI::t::Util;
use strict;
use warnings;
use CHI::Test;
use CHI::Util qw(unique_id);
use List::MoreUtils qw(uniq);
use base qw(CHI::Test::Class);

# The inevitably lame unique_id test
sub test_unique_id : Tests(1) {
    my @ids = map { unique_id } ( 0 .. 9 );
    cmp_deeply( \@ids, [ uniq(@ids) ], 'generated ten unique ids' );
}

1;
