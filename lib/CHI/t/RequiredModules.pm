package CHI::t::RequiredModules;
use strict;
use warnings;
use CHI::Test;
use base qw(CHI::Test::Class);

sub required_modules { return { 'Data::Dumper' => undef, 'blarg' => undef } }

sub test_blarg : Tests {
    require Blarg;
    Blarg->funny();
}

1;
