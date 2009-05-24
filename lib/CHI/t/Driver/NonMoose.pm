package CHI::t::Driver::NonMoose;
use strict;
use warnings;
use CHI::Test;
use base qw(CHI::t::Driver::Memory);

sub testing_driver_class { 'CHI::Test::Driver::NonMoose' }

# These won't work without Moose
sub test_custom_discard_policy         { }
sub test_discard_timeout               { }
sub test_l1_cache                      { }
sub test_lru_discard                   { }
sub test_max_size                      { }
sub test_mirror_cache                  { }
sub test_size_awareness                { }
sub test_size_awareness_with_subcaches { }
sub test_short_driver_name             { }

sub test_apply_role : Tests(1) {
    my ($self) = @_;

    throws_ok { $self->new_cache( max_size => 100 ) }
    qr/cannot apply role to non-Moose driver/;
}

1;
