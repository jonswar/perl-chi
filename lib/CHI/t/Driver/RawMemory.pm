package CHI::t::Driver::RawMemory;
use strict;
use warnings;
use CHI::Test;
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
sub test_custom_discard_policy         { }
sub test_deep_copy                     { }
sub test_lru_discard                   { }
sub test_max_size                      { }
sub test_scalar_return_values          { }
sub test_serialize                     { }
sub test_serializers                   { }
sub test_size_awareness                { }
sub test_size_awareness_with_subcaches { }
sub test_subcache_overridable_params   { }

sub test_short_driver_name : Tests(1) {
    my ($self) = @_;

    my $cache = $self->{cache};
    is( $cache->short_driver_name, 'RawMemory' );
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

1;
