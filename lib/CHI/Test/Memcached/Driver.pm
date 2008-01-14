package CHI::Test::Memcached::Driver;
use strict;
use warnings;
use base qw(CHI::Driver::Memcached);

# Memcached doesn't support get_keys. For testing purposes, define get_keys
# by checking for all keys used during testing.
#

my @all_test_keys = (
    'space', 'a', 0, 1, 'medium', 'mixed', scalar( 'ab' x 100 ),
    'arrayref', 'hashref', map { "done$_" } ( 0 .. 2 ),
);

sub get_keys {
    my $self = shift;

    return map { defined $self->get($_) ? ($_) : () } @all_test_keys;
}

1;
