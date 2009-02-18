package CHI::t::Driver::Paired::l1_cache;
use strict;
use warnings;
use CHI::Test;
use File::Temp qw(tempdir);
use base qw(CHI::t::Driver::Paired);

my $root_dir;

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
    my ($self)   = @_;
    my $cache    = $self->{cache};
    my $l1_cache = $cache->l1_cache;
    my ( $key, $value ) = $self->kvpair();
    my $value2 = $value . "2";

    isa_ok( $cache,    'CHI::Driver::File' );
    isa_ok( $cache,    'CHI::Driver::Paired' );
    isa_ok( $l1_cache, 'CHI::Driver::Memory' );

    # Get on cache should populate l1 cache
    #
    $cache->primary_subcache->set( $key, $value );
    ok( !$l1_cache->get($key), "l1 miss after primary set" );
    is( $cache->get($key),    $value, "primary hit after primary set" );
    is( $l1_cache->get($key), $value, "l1 hit after primary get" );

    # Primary cache should be reading l1 cache first
    #
    $l1_cache->set( $key, $value2 );
    is( $cache->get($key), $value2,
        "got new value set explicitly in l1 cache" );
    $l1_cache->remove($key);
    is( $cache->get($key), $value, "got old value again" );
}

1;
