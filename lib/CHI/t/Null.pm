package CHI::t::Null;
use strict;
use warnings;
use CHI::Test;
use base qw(CHI::Test::Class);

sub test_basic : Tests {
    my ( $key, $value ) = ( 'medium', 'medium' );
    my $cache = CHI->new( driver => 'Null' );
    $cache->set( $key, $value );
    ok( !defined( $cache->get($key) ), "miss after set" );
    cmp_deeply( [ $cache->get_keys ],       [], "no keys after set" );
    cmp_deeply( [ $cache->get_namespaces ], [], "no namespaces after set" );
}

1;
