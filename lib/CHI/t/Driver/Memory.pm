package CHI::t::Driver::Memory;
use strict;
use warnings;
use CHI::Test;
use base qw(CHI::t::Driver);

# Skip multiple process test
sub test_multiple_procs { }

sub test_short_driver_name : Tests(1) {
    my ($self) = @_;

    my $cache = $self->{cache};
    is( $cache->short_driver_name, 'Memory' );
}

1;
