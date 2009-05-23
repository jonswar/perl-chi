package CHI::Test::Driver::Readonly;
use Carp;
use Moose;
use strict;
use warnings;
extends 'CHI::Driver::Memory';
__PACKAGE__->meta->make_immutable();

sub store {
    my ( $self, $key, $data ) = @_;

    croak "read-only cache";
}

1;
