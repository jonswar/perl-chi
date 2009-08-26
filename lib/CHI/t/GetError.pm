package CHI::t::GetError;
use strict;
use warnings;
use CHI::Test;
use CHI::Test::Util qw(activate_test_logger);
use base qw(CHI::Test::Class);

sub writeonly_cache {
    my ($on_get_error) = @_;

    return CHI->new(
        driver_class => 'CHI::Test::Driver::Writeonly',
        on_get_error => $on_get_error,
        global       => 1,
    );
}

sub test_get_errors : Test(10) {
    my ( $key, $value ) = ( 'medium', 'medium' );

    my $error_pattern =
      qr/error during cache get for namespace='.*', key='medium'.*: write-only cache/;
    my $log = activate_test_logger();

    my $cache;

    $cache = writeonly_cache('ignore');
    $cache->set( $key, $value );
    ok( !defined( $cache->get($key) ), "ignore - miss" );

    $cache = writeonly_cache('die');
    $cache->set( $key, $value );
    throws_ok( sub { $cache->get($key) }, $error_pattern, "die - dies" );

    $log->clear();
    $cache = writeonly_cache('log');
    $cache->set( $key, $value );
    ok( !defined( $cache->get($key) ), "log - miss" );
    $log->contains_ok(qr/cache set for .* key='medium'/);
    $log->contains_ok($error_pattern);
    $log->empty_ok();

    my ( $err_msg, $err_key );
    $cache = writeonly_cache(
        sub {
            ( $err_msg, $err_key ) = @_;
        }
    );
    $cache->set( $key, $value );
    ok( !defined( $cache->get($key) ), "custom - miss" );
    like( $err_msg, $error_pattern, "custom - got msg" );
    is( $err_key, $key, "custom - got key" );

    throws_ok(
        sub { writeonly_cache('bad') },
        qr/Attribute .* does not pass the type constraint/,
        "bad - dies"
    );
}

1;
