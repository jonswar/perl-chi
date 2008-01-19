package CHI::t::Driver::Multilevel;
use strict;
use warnings;
use CHI::Test;
use CHI::Test::Util qw(is_between);
use File::Temp qw(tempdir);
use base qw(CHI::t::Driver);

my $root_dir;
my ( $key, $value, $cache, $memory_cache, $file_cache );

sub new_cache_options {
    my $self = shift;

    $root_dir ||=
      tempdir( "chi-driver-multilevel-XXXX", TMPDIR => 1, CLEANUP => 1 );
    return (
        $self->SUPER::new_cache_options(),
        subcaches => [
            { driver => 'Memory' },
            { driver => 'File', root_dir => $root_dir }
        ]
    );
}

sub setup_multilevel : Test(setup) {
    my $self = shift;
    $cache = $self->new_cache();
    ( $memory_cache, $file_cache ) = @{ $cache->subcaches };
    ( $key,          $value )      = $self->kvpair();
}

# This doesn't work because the gets() refresh the memory cache
sub test_expires_variance {
}

sub confirm_caches_empty {
    my ($desc) = @_;
    ok( $cache->is_empty(),        "cache is empty" );
    ok( $memory_cache->is_empty(), "memory cache is empty" );
    ok( $file_cache->is_empty(),   "file cache is empty" );
}

sub confirm_caches_populated {
    my ($desc) = @_;
    is( $cache->get($key),        $value, "cache is populated" );
    is( $memory_cache->get($key), $value, "memory cache is populated" );
    is( $file_cache->get($key),   $value, "file cache is populated" );
}

sub test_hit {
    my ($desc) = @_;
    is( $cache->get($key), $value, "hit: $desc" );
}

sub test_miss {
    my ($desc) = @_;
    ok( !defined $cache->get($key), "miss: $desc" );
}

sub test_multilevel_isolated_set : Test(5) {
    my $self = shift;

    # Just set memory cache
    #
    $memory_cache->set( $key, $value );
    test_hit("after memory set");
    $memory_cache->remove($key);
    test_miss("after memory remove");

    # Just set file cache
    #
    $file_cache->set( $key, $value );
    test_hit("after file set");
    $file_cache->remove($key);
    test_hit("after file remove, still in memory");
    $memory_cache->remove($key);
    test_miss("after file remove");
}

sub test_multilevel_isolated_clear : Test(26) {
    my $self = shift;

    # Caches start out empty
    #
    confirm_caches_empty("initial");
    test_miss("initial");

    # Set both, then remove from file cache
    #
    $cache->set( $key, $value );
    test_hit("after set 1");
    confirm_caches_populated("after set 1");
    $file_cache->clear();
    test_hit("after clear file cache 1");
    ok( $file_cache->is_empty(),
        "file cache still empty after memory cache hit" );
    $memory_cache->clear();
    test_miss("after clear both caches 1");
    confirm_caches_empty("after clear both caches 1");

    # Set both, then remove from memory cache
    #
    $cache->set( $key, $value );
    test_hit("after set 2");
    confirm_caches_populated("after set 2");
    $memory_cache->clear();
    test_hit("after clear memory cache 2");
    confirm_caches_populated("after test hit");
    $memory_cache->clear();
    $file_cache->clear();
    test_miss("after clear both caches 2");
    confirm_caches_empty("after clear both caches 2");
}

sub test_multilevel_auto_local_write : Test(5) {
    my $self = shift;

    $memory_cache->expires_in('5 sec');
    is( $memory_cache->expires_in(), '5 sec', "set expires_in" );
    $file_cache->set( $key, $value );
    ok( $memory_cache->is_empty(), "memory cache empty before file cache hit" );
    is( $cache->get($key), $value, "got hit from file cache" );
    is( $memory_cache->get($key),
        $value, "memory cache populated after file cache hit" );
    is_between(
        $memory_cache->get_expires_at($key),
        time() + 3,
        time() + 5,
        "memory cache expires time after file cache hit"
    );
}

sub test_zero_subcaches : Test(1) {
    my $self = shift;
    my $null_cache = $self->new_cache( subcaches => [] );
    my ( $key, $value ) = $self->kvpair();
    $null_cache->set( $key, $value );
    ok( !defined( $null_cache->get($key) ) );
}

sub test_many_subcaches : Test(12) {
    my $self = shift;

    my @ids = ( 0 .. 4 );
    my $cache =
      $self->new_cache( subcaches =>
          [ map { { driver => 'Memory', namespace => "namespace$_" } } @ids ] );
    my @subcaches = @{ $cache->subcaches() };

    $cache->set( $key, $value );
    is( $cache->get($key), $value, "hit for cache after set" );
    foreach my $i (@ids) {
        is( $subcaches[$i]->get($key), $value, "hit for $i after set" );
    }
    $cache->clear();

    $subcaches[2]->set( $key, $value );
    is( $cache->get($key), $value, "hit for cache after set 2" );
    foreach my $i ( 0 .. 2 ) {
        is( $subcaches[$i]->get($key), $value, "hit for $i after set 2" );
    }
    foreach my $i ( 3 .. 4 ) {
        ok( !defined( $subcaches[$i]->get($key) ), "miss for $i after set 2" );
    }
    $cache->clear();
}

sub test_expiration_options : Test(7) {
    my $self = shift;
    my $cache;

    my $test_expires_in = sub {
        my ( $desc, $parent_new_flags, $subcache_new_flags, $set_flags,
            $expected_expires_in )
          = @_;
        my $subcache_spec = {
            subcaches => [
                { driver => 'Memory', %$subcache_new_flags },
                { driver => 'File',   root_dir => $root_dir }
            ]
        };
        my $cache = $self->new_cache( %$parent_new_flags, %$subcache_spec );
        my $time = time();
        is( $cache->set( $key, $value, @$set_flags ), $value, "set ($desc)" );
        is_between(
            $cache->get_expires_at($key) - $time,
            $expected_expires_in,
            $expected_expires_in + 1,
            "expires_at ($desc)"
        );
    };

    $test_expires_in->(
        'parent option only',
        { expires_in => '5 sec' },
        {}, [], 5
    );
    $test_expires_in->(
        'parent and set option',
        { expires_in => '5 sec' },
        {}, ['15 sec'], 15
    );
    $test_expires_in->( 'set option only', {}, {}, ['15 sec'], 15 );

    throws_ok(
        sub {
            $test_expires_in->(
                'subcache option',
                {}, { expires_in => '10 sec' }, 0
            );
        },
        qr/expiration option 'expires_in' not supported in subcache/
    );

}

1;
