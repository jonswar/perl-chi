package CHI::Test::Driver::Writeonly;
use strict;
use warnings;
use base qw(CHI::Driver::Memory);

sub fetch {
    my ( $self, $key ) = @_;

    die "write-only cache";
}

1;
