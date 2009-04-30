package CHI::t::Driver::Memory;
use strict;
use warnings;
use CHI::Test;
use base qw(CHI::t::Driver);

# Skip multiple process test
sub test_multiple_procs { }

sub new_cache_options {
    my $self = shift;

    return ( $self->SUPER::new_cache_options(), global => 1 );
}

sub test_short_driver_name : Tests(1) {
    my ($self) = @_;

    my $cache = $self->{cache};
    is( $cache->short_driver_name, 'Memory' );
}

sub test_global_or_default_required : Tests(1) {
    throws_ok( sub { my $cache = CHI->new( driver => 'Memory' ) },
        qr/must specify either/ );
}

sub test_different_datastores : Tests(1) {
    my $self   = shift;
    my $cache1 = CHI->new( driver => 'Memory', datastore => {} );
    my $cache2 = CHI->new( driver => 'Memory', datastore => {} );
    $self->set_some_keys($cache1);
    ok( $cache2->is_empty() );
}

1;
