package CHI::t::Driver::Memcached;
use strict;
use warnings;
use CHI::Test;
use base qw(CHI::t::Driver);

my $testaddr = "127.0.0.1:11211";

# Making this internal only for now, since test success depends on presence and configuration
# of an external server.
#
# When CHI::Driver::Memcached is pulled out into a separate distribution, it'll make
# sense to test externally again.
#
sub internal_only { 1 }

sub required_modules {
    return { 'Cache::Memcached' => undef, 'IO::Socket::INET' => undef };
}

sub connect_to_memcached : Test(startup) {
    require IO::Socket::INET;
    my $msock = IO::Socket::INET->new(
        PeerAddr => $testaddr,
        Timeout  => 3
    );
    if ( !$msock ) {
        die "No memcached instance running at $testaddr\n";
    }
}

sub clear_memcached : Test(setup) {
    my ($self) = @_;

    my $cache = $self->new_cache();
    $cache->memd->flush_all();
}

sub new_cache_options {
    my $self = shift;

    # CHI::Test::Memcached::Driver defines get_keys for testing purposes
    return (
        $self->SUPER::new_cache_options(),
        driver       => undef,
        driver_class => 'CHI::Test::Memcached::Driver',
        servers      => [$testaddr]
    );
}

sub set_standard_keys_and_values {
    my ($self) = @_;

    my ( $keys, $values ) = $self->SUPER::set_standard_keys_and_values();

    # memcached keys have max length of 250, plus we're adding namespace
    $keys->{'large'} = scalar( 'ab' x 100 );

    # memcached keys must not include control characters or whitespace
    $keys->{'space'} = 'space';
    $keys->{'mixed'} = 'mixed';

    return ( $keys, $values );
}

sub test_get_keys : Test(1) {
    my $self = shift;

    # Make sure we get a 'not supported' error with regular memcached driver
    my $cache =
      $self->SUPER::new_cache( driver => 'Memcached', servers => [$testaddr] );
    throws_ok(
        sub { $cache->get_keys() },
        qr/not supported/,
        "get_keys not supported"
    );
}

1;
