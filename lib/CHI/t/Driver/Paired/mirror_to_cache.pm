package CHI::t::Driver::Paired::mirror_to_cache;
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
        driver          => 'File',
        depth           => 2,
        root_dir        => $root_dir,
        mirror_to_cache => { driver => 'File', depth => 3 },
    );
}

sub test_basic : Tests(2) {
    my ($self)          = @_;
    my $cache           = $self->{cache};
    my $mirror_to_cache = $cache->mirror_to_cache;
    my ( $key, $value ) = $self->kvpair();

    # Get on either cache should not populate the other, and should not be able to see
    # mirror keys from regular cache
    #
    $cache->set( $key, $value );
    $mirror_to_cache->remove($key);
    $cache->get($key);
    ok( !$mirror_to_cache->get($key), "key not in mirror_to_cache" );

    $mirror_to_cache->set( $key2, $value2 );
    ok( !$cache->get($key2), "key2 not in cache" );
}

1;
