package CHI::t::Driver::FastMmap;
use strict;
use warnings;
use CHI::Test;
use Encode;
use File::Temp qw(tempdir);
use base qw(CHI::t::Driver);

my $root_dir;

sub required_modules {
    return { 'Cache::FastMmap' => undef };
}

sub new_cache_options {
    my $self = shift;

    $root_dir ||=
      tempdir( "chi-driver-fastmmap-XXXX", TMPDIR => 1, CLEANUP => 1 );
    return ( $self->SUPER::new_cache_options(), root_dir => $root_dir );
}

sub test_fm_cache : Test(4) {
    my ($self) = @_;

    # Create brand new cache and check defaults
    my $cache =
      $self->new_cache( root_dir =>
          tempdir( "chi-driver-fastmmap-XXXX", TMPDIR => 1, CLEANUP => 1 ) );

    my $fm_cache = $cache->fm_cache();
    isa_ok( $fm_cache, 'Cache::FastMmap' );

    my %defaults = (
        unlink_on_exit => 0,
        empty_on_exit  => 0,
        raw_values     => 1,
    );
    while ( my ( $key, $value ) = each(%defaults) ) {
        is( $fm_cache->{$key} || 0, $value, "$key = $value by default" );
    }
}

sub test_parameter_passthrough : Test(2) {
    my ($self) = @_;

    my $cache = $self->new_cache( cache_size => '500k' );

    # The number gets munged by FastMmap so it's not equal to 500 * 1024
    is( $cache->fm_cache()->{cache_size},
        589824,
        'cache_size parameter is passed to Cache::FastMmap constructor' );

    $cache = $self->new_cache( page_size => 5000, num_pages => 11 );

    # Same here, it won't be equal to 5000 * 11
    is( $cache->fm_cache()->{cache_size}, 45056,
        'page_size and num_pages parameters are passed to Cache::FastMmap constructor'
    );
}

sub test_value_too_large : Tests(2) {
    my ($self) = @_;

    my $cache = $self->new_cache(
        page_size    => '4k',
        num_pages    => 11,
        on_set_error => 'die'
    );
    my %values;
    $values{small} = 'x' x 3 x 1024;
    $values{large} = 'x' x 10 x 1024;
    $cache->set( 'small', $values{small} );
    is( $cache->get('small'), $values{small}, "got small" );
    throws_ok { $cache->set( 'large', $values{large} ) }
    qr/error during cache set.*fastmmap set failed/;
}

# Copied from t/Driver.pm, but commented out "Key maps to same thing whether
# utf8 flag is off or on". This fails with FastMmap.pm because utf8 flag of
# key is apparently used as part of key.
#
sub test_encode : Test(11) {
    my $self  = shift;
    my $cache = $self->new_cleared_cache();

    my $utf8       = $self->{keys}->{utf8};
    my $encoded    = encode( utf8 => $utf8 );
    my $binary_off = $self->{keys}->{binary};
    my $binary_on  = substr( $binary_off . $utf8, 0, length($binary_off) );

    ok( $binary_off eq $binary_on, "binary_off eq binary_on" );
    ok( !Encode::is_utf8($binary_off), "!is_utf8(binary_off)" );
    ok( Encode::is_utf8($binary_on),   "is_utf8(binary_on)" );

    # Key maps to same thing whether encoded or non-encoded
    #
    my $value = time;
    $cache->set( $utf8, $value );
    is( $cache->get($utf8), $value, "get" );
    is( $cache->get($encoded), $value,
        "encoded and non-encoded map to same value" );

    # Key maps to same thing whether utf8 flag is off or on
    #
    # $cache->set( $binary_off, $value );
    # is( $cache->get($binary_off), $value, "get binary_off" );
    # is( $cache->get($binary_on),
    #     $value, "binary_off and binary_on map to same value" );
    # $cache->clear($binary_on);
    # ok( !$cache->get($binary_off), "cleared binary_off" );

    # Value is maintained as a utf8 or binary string, in scalar or in arrayref
    $cache->set( "utf8", $utf8 );
    is( $cache->get("utf8"), $utf8, "utf8 in scalar" );
    $cache->set( "utf8", [$utf8] );
    is( $cache->get("utf8")->[0], $utf8, "utf8 in arrayref" );

    $cache->set( "encoded", $encoded );
    is( $cache->get("encoded"), $encoded, "encoded in scalar" );
    $cache->set( "encoded", [$encoded] );
    is( $cache->get("encoded")->[0], $encoded, "encoded in arrayref" );

    # Value retrieves as same thing whether stored with utf8 flag off or on
    #
    $cache->set( "binary", $binary_off );
    is( $cache->get("binary"), $binary_on, "stored binary_off = binary_on" );
    $cache->set( "binary", $binary_on );
    is( $cache->get("binary"), $binary_off, "stored binary_on = binary_off" );
}

1;
