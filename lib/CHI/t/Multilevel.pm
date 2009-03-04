package CHI::t::Multilevel;
use strict;
use warnings;
use CHI::Test;
use Module::Load::Conditional qw(can_load);
use base qw(CHI::Test::Class);

sub test_multilevel_with_serializer : Tests(1) {
    my ($self) = @_;

    return 'Data::Serializer not installed'
      unless can_load( modules => { 'Data::Serializer' => undef } );

    my $cache = CHI->new(
        driver     => 'Multilevel',
        serializer => 'Data::Dumper',
        subcaches  => [ { driver => 'Memory' } ]
    );

    my $key = 'arrayref';
    my $value = [ 3, 4, 5 ];
    $cache->set( $key, $value );
    cmp_deeply( $cache->get($key), $value );
}

1;
