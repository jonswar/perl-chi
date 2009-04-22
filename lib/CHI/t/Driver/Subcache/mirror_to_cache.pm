package CHI::t::Driver::Subcache::mirror_to_cache;
use strict;
use warnings;
use CHI::Test;
use File::Temp qw(tempdir);
use base qw(CHI::t::Driver::Subcache);

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
    my ( $key, $value, $key2, $value2 ) = $self->kvpair(2);

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

sub test_logging : Test(11) {
    my $self  = shift;
    my $cache = $self->{cache};

    my $log = CHI::Test::Logger->new();
    CHI->logger($log);
    my ( $key, $value ) = $self->kvpair();

    my $driver = $cache->short_driver_name;

    my $miss_not_in_cache = 'MISS \(not in cache\)';
    my $miss_expired      = 'MISS \(expired\)';

    my $start_time = time();

    $cache->get($key);
    $log->contains_ok(
        qr/cache get for .* key='$key', cache='$driver': $miss_not_in_cache/);
    $log->empty_ok();

    $cache->set( $key, $value, 80 );
    my $length = length($value);
    $log->contains_ok(
        qr/cache set for .* key='$key', size=$length, expires='1m20s', cache='$driver'/
    );
    $log->contains_ok(
        qr/cache set for .* key='$key', size=$length, expires='1m20s', cache='.*mirror.*'/
    );
    $log->empty_ok();

    $cache->get($key);
    $log->contains_ok(qr/cache get for .* key='$key', cache='$driver': HIT/);
    $log->empty_ok();

    local $CHI::Driver::Test_Time = $start_time + 120;
    $cache->get($key);
    $log->contains_ok(
        qr/cache get for .* key='$key', cache='$driver': $miss_expired/);
    $log->empty_ok();

    $cache->remove($key);
    $cache->get($key);
    $log->contains_ok(
        qr/cache get for .* key='$key', cache='$driver': $miss_not_in_cache/);
    $log->empty_ok();
}

1;
