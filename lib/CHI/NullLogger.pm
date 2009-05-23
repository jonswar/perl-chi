package CHI::NullLogger;
use Moose;
use strict;
use warnings;

foreach my $level (qw(fatal error warn info debug)) {
    __PACKAGE__->meta->add_method( $level      => sub { } );
    __PACKAGE__->meta->add_method( "is_$level" => sub { undef } );
}

__PACKAGE__->meta->make_immutable();

1;
