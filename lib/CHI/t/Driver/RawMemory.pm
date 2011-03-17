package CHI::t::Driver::RawMemory;
use strict;
use warnings;
use CHI::Test;
use CHI::Test::Util qw(is_between);
use base qw(CHI::t::Driver::Memory);

sub new_cache {
    my $self   = shift;
    my %params = @_;

    # If new_cache called with datastore, ignore global flag (otherwise would be an error)
    #
    if ( $params{datastore} ) {
        $params{global} = 0;
    }

    my $cache = CHI->new( $self->new_cache_options(), %params );
    return $cache;
}

# Not applicable to raw memory
#
sub test_deep_copy            { }
sub test_scalar_return_values { }
sub test_serialize            { }
sub test_serializers          { }

# Would need tweaking to pass
#
sub test_compress_threshold            { }
sub test_custom_discard_policy         { }
sub test_lru_discard                   { }
sub test_size_awareness_with_subcaches { }
sub test_stats                         { }
sub test_subcache_overridable_params   { }

# Size of all items = 1 in this driver
#
sub test_size_awareness : Tests {
    my $self = shift;
    my ( $key, $value ) = $self->kvpair();

    ok( !$self->new_cleared_cache()->is_size_aware(),
        "not size aware by default" );
    ok( $self->new_cleared_cache( is_size_aware => 1 )->is_size_aware(),
        "is_size_aware turns on size awareness" );
    ok( $self->new_cleared_cache( max_size => 10 )->is_size_aware(),
        "max_size turns on size awareness" );

    my $cache = $self->new_cleared_cache( is_size_aware => 1 );
    is( $cache->get_size(), 0, "size is 0 for empty" );
    $cache->set( $key, $value );
    is( $cache->get_size, 1, "size is 1 with one value" );
    $cache->set( $key, scalar( $value x 5 ) );
    is( $cache->get_size, 1, "size is still 1 after override" );
    $cache->set( $key, scalar( $value x 5 ) );
    is( $cache->get_size, 1, "size is still 1 after same overwrite" );
    $cache->set( $key, scalar( $value x 2 ) );
    is( $cache->get_size, 1, "size is 1 after overwrite" );
    $cache->set( $key . "2", $value );
    is( $cache->get_size, 2, "size is 2 after second key" );
    $cache->remove($key);
    is( $cache->get_size, 1, "size is 1 again after removing key" );
    $cache->remove( $key . "2" );
    is( $cache->get_size, 0, "size is 0 again after removing keys" );
    $cache->set( $key, $value );
    is( $cache->get_size, 1, "size is 1 with one value" );
    $cache->clear();
    is( $cache->get_size, 0, "size is 0 again after clear" );

    my $time = time() + 10;
    $cache->set( $key, $value, { expires_at => $time } );
    is( $cache->get_expires_at($key),
        $time, "set options respected by size aware cache" );
}

sub test_max_size : Tests {
    my $self = shift;

    my $cache = $self->new_cleared_cache( max_size => 5 );
    ok( $cache->is_size_aware, "is size aware when max_size specified" );
    my $value = 'x';

    for ( my $i = 0 ; $i < 5 ; $i++ ) {
        $cache->set( "key$i", $value );
    }
    for ( my $i = 0 ; $i < 10 ; $i++ ) {
        $cache->set( "key" . int( rand(10) ), $value );
        is_between( $cache->get_size, 3, 5,
            "after iteration $i, size = " . $cache->get_size );
        is_between( scalar( $cache->get_keys ),
            3, 5, "after iteration $i, keys = " . scalar( $cache->get_keys ) );
    }
}

# Test that we're caching a reference, not a deep copy
#
sub test_cache_ref : Tests {
    my $self  = shift;
    my $cache = $self->{cache};
    my $lst   = ['foo'];
    $cache->set( 'key1' => $lst );
    $cache->set( 'key2' => $lst );
    is( $cache->get('key1'), $lst, "got same reference" );
    is( $cache->get('key2'), $lst, "got same reference" );
    $lst->[0] = 'bar';
    is( $cache->get('key1')->[0], 'bar', "changed value in cache" );
}

sub test_short_driver_name : Tests {
    my ($self) = @_;

    my $cache = $self->{cache};
    is( $cache->short_driver_name, 'RawMemory' );
}

1;
