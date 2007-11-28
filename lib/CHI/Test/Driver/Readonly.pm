package CHI::Test::Driver::Readonly;
use strict;
use warnings;
use base qw(CHI::Driver::Memory);

sub store {
    my ( $self, $key, $data, $options ) = @_;

    die "read-only cache";
}

1;
