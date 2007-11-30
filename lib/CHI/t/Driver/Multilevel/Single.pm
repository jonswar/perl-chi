package CHI::t::Driver::Multilevel::Single;
use strict;
use warnings;
use CHI::Test;
use base qw(CHI::t::Driver);

# Test multilevel driver with a single subcache.

sub new_cache_options {
    my $self = shift;

    return (
        $self->SUPER::new_cache_options(),
        driver    => 'Multilevel',
        subcaches => [ { driver => 'File' } ]
    );
}

1;
