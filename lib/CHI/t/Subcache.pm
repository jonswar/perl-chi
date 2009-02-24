package CHI::t::Paired;
use CHI::Test;
use base qw(CHI::Test::Class);
use strict;
use warnings;

sub test_option_inheritance : Tests(8) {
    my $self = shift;

    my %params = (
        expires_variance => 0.2,
        namespace        => 'Blurg',
        on_get_error     => 'warn',
        on_set_error     => 'warn',
        serializer       => 'Data::Dumper',
        depth            => 4,
    );
    my $cache =
      CHI->new( driver => 'File', %params, l1_cache => { driver => 'File' } );
    foreach my $field (qw(expires_variance namespace on_get_error on_set_error))
    {
        is( $cache->$field, $cache->l1_cache->$field, "$field matches" );
    }
    is( $cache->serializer->serializer, 'Data::Dumper', 'cache serializer' );
    is( $cache->l1_cache->serializer->serializer,
        'Storable', 'l1 cache serializer' );
    is( $cache->depth,           4, 'cache depth' );
    is( $cache->l1_cache->depth, 2, 'l1 cache depth' );
}

1;
