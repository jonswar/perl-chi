package CHI::t::Util;
use strict;
use warnings;
use CHI::Test;
use CHI::Util qw(unique_id);
use CHI::Test::Util qw(random_string);
use List::MoreUtils qw(uniq);
use base qw(CHI::Test::Class);

# The inevitably lame unique_id test
sub test_unique_id : Tests(1) {
    my @ids = map { unique_id } ( 0 .. 9 );
    cmp_deeply( \@ids, [ uniq(@ids) ], 'generated ten unique ids' );
}

sub test_random_string : Tests(2) {
    my @strings = map { random_string(100) } ( 0 .. 2 );
    cmp_deeply(
        \@strings,
        [ uniq(@strings) ],
        'generated three unique strings'
    );
    cmp_deeply(
        [ map { length($_) } @strings ],
        [ 100, 100, 100 ],
        'lengths are 100'
    );
}

sub test_non_common_constructor_params : Tests(1) {
    my $params =
      { map { ( $_, 1 ) } qw( foo expires_in bar baz on_get_error ) };
    my $non_common_params = CHI::Driver->non_common_constructor_params($params);
    cmp_deeply( $non_common_params, { map { ( $_, 1 ) } qw(foo bar baz) } );
}

1;
