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

sub set_standard_keys_and_values {
    my ($self) = @_;

    my ( $keys, $values ) = $self->SUPER::set_standard_keys_and_values();

    # File keys have max length of 255 or so
    $keys->{'large'} = scalar( 'ab' x 125 );

    return ( $keys, $values );
}

1;
