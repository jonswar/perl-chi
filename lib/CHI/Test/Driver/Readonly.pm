package CHI::Test::Driver::Readonly;
use Carp;
use strict;
use warnings;
use base qw(CHI::Driver::Memory);

sub store {
    my ( $self, $key, $data ) = @_;

    croak "read-only cache";
}

1;
