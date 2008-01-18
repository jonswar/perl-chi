package CHI::t::RequiredModules;
use strict;
use warnings;
use CHI::Test;
use base qw(CHI::Test::Class);

sub internal_only { 1 }

sub required_modules { return { 'Data::Dumper' => undef, 'blarg' => undef } }

sub test_blarg : Test(1) {
    require Blarg;
    Blarg->funny();
}

1;
