package CHI::t::Driver::Subcache;
use strict;
use warnings;
use CHI::Test;
use base qw(CHI::t::Driver);

sub set_standard_keys_and_values {
    my ($self) = @_;

    my ( $keys, $values ) = $self->SUPER::set_standard_keys_and_values();

    # keys for file driver have max length of 255 or so
    # but on windows xp, the full pathname is limited to 255 chars as well
    $keys->{'large'} = scalar( 'ab' x ( $^O eq 'MSWin32' ? 64 : 120 ) );

    return ( $keys, $values );
}

# Skip these tests - the logging will be wrong
#
sub test_l1_cache : Tests {
    ok(1);
}

sub test_mirror_cache : Tests {
    ok(1);
}

sub test_logging : Tests {
    ok(1);
}

1;
