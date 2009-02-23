package CHI::t::Driver::Paired::l1_cache;
use strict;
use warnings;
use CHI::Test;
use File::Temp qw(tempdir);
use base qw(CHI::t::Driver::Paired);

my ( $root_dir, $cache, $l1_cache, @keys, @values );

sub setup_l1_cache : Test(setup) {
    my $self = shift;
    $cache    = $self->new_cache();
    $cache    = $self->{cache};
    $l1_cache = $cache->l1_cache;
    @keys     = map { "key$_" } ( 0 .. 2 );
    @values   = map { "value$_" } ( 0 .. 2 );
}

sub new_cache_options {
    my $self = shift;

    $root_dir ||=
      tempdir( "chi-driver-paired-XXXX", TMPDIR => 1, CLEANUP => 1 );
    return (
        $self->SUPER::new_cache_options(),
        driver   => 'File',
        root_dir => $root_dir,
        l1_cache => { driver => 'Memory' },
    );
}

sub test_basic : Tests(8) {
    my ($self) = @_;

    isa_ok( $cache,    'CHI::Driver::File' );
    isa_ok( $cache,    'CHI::Driver::Paired' );
    isa_ok( $l1_cache, 'CHI::Driver::Memory' );

    # Get on cache should populate l1 cache
    #
    $cache->set( $keys[0], $values[0] );
    $l1_cache->clear();
    ok( !$l1_cache->get( $keys[0] ), "l1 miss after clear" );
    is( $cache->get( $keys[0] ), $values[0], "primary hit after primary set" );
    is( $l1_cache->get( $keys[0] ), $values[0], "l1 hit after primary get" );

    # Primary cache should be reading l1 cache first
    #
    $l1_cache->set( $keys[0], $values[1] );
    is( $cache->get( $keys[0] ),
        $values[1], "got new value set explicitly in l1 cache" );
    $l1_cache->remove( $keys[0] );
    is( $cache->get( $keys[0] ), $values[0], "got old value again" );

    $cache->clear();
}

sub test_multi : Tests(3) {

    # get_multi_* - one from l1 cache, one from primary cache, one miss
    #
    $cache->set( $keys[0], $values[0] );
    $cache->set( $keys[1], $values[0] );
    $l1_cache->remove( $keys[0] );
    $l1_cache->set( $keys[1], $values[1] );
    cmp_deeply(
        $cache->get_multi_arrayref( [ $keys[0], $keys[1], $keys[2] ] ),
        [ $values[0], $values[1], undef ],
        "get_multi_arrayref"
    );
    cmp_deeply(
        [ $cache->get_multi_array( [ $keys[0], $keys[1], $keys[2] ] ) ],
        [ $values[0], $values[1], undef ],
        "get_multi_array"
    );
    cmp_deeply(
        [ $cache->get_multi_hashref( [ $keys[0], $keys[1], $keys[2] ] ) ],
        { $keys[0] => $values[0], $keys[1] => $values[1], $keys[2] => undef },
        "get_multi_array"
    );
}

1;
