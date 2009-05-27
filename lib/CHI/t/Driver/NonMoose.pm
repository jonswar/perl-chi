package CHI::t::Driver::NonMoose;
use strict;
use warnings;
use CHI::Test;
use base qw(CHI::t::Driver::Memory);

sub testing_driver_class   { 'CHI::Test::Driver::NonMoose' }
sub test_short_driver_name { }

1;
