package CHI::t::SetError;
use strict;
use warnings;
use CHI::Test;
use base qw(CHI::Test::Class);

sub readonly_cache {
    my ($on_set_error) = @_;

    return CHI->new(
        driver_class => 'CHI::Test::Driver::Readonly',
        on_set_error => $on_set_error,
        global       => 1
    );
}

sub test_set_errors : Test(14) {
    my ( $key, $value ) = ( 'medium', 'medium' );

    my $error_pattern =
      qr/error during cache set for namespace='.*', key='medium', size=\d+.*: read-only cache/;
    my $log = CHI::Test::Logger->new();
    CHI->logger($log);

    my $cache;

    $cache = readonly_cache('ignore');
    lives_ok( sub { $cache->set( $key, $value ) }, "ignore - lives" );
    ok( !defined( $cache->get($key) ), "ignore - miss" );

    $cache = readonly_cache('die');
    throws_ok( sub { $cache->set( $key, $value ) },
        $error_pattern, "die - dies" );
    ok( !defined( $cache->get($key) ), "die - miss" );

    $log->clear();
    $cache = readonly_cache('log');
    lives_ok( sub { $cache->set( $key, $value ) }, "log - lives" );
    ok( !defined( $cache->get($key) ), "log - miss" );
    $log->contains_ok(qr/cache get for .* key='medium', .*: MISS/);
    $log->contains_ok($error_pattern);
    $log->empty_ok();

    my ( $err_msg, $err_key );
    $cache = readonly_cache(
        sub {
            ( $err_msg, $err_key ) = @_;
        }
    );
    lives_ok( sub { $cache->set( $key, $value ) }, "custom - lives" );
    ok( !defined( $cache->get($key) ), "custom - miss" );
    like( $err_msg, $error_pattern, "custom - got msg" );
    is( $err_key, $key, "custom - got key" );

    throws_ok(
        sub { readonly_cache('bad') },
        qr/Attribute .* does not pass the type constraint/,
        "bad - dies"
    );
}

1;
