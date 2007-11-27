package CHI::NullLogger;
use strict;
use warnings;
use base qw(Class::Accessor::Fast);

foreach my $level (qw(fatal error warn info debug)) {
    no strict 'refs';
    *{ __PACKAGE__ . "::$level" }    = sub { };
    *{ __PACKAGE__ . "::is_$level" } = sub { undef };
}

1;
