package CHI::NullLogger;
use Mouse;
use strict;
use warnings;

foreach my $level (qw(fatal error warn info debug)) {
    no strict 'refs';
    *{ __PACKAGE__ . "::$level" }    = sub { };
    *{ __PACKAGE__ . "::is_$level" } = sub { undef };
}

__PACKAGE__->meta->make_immutable();

1;
