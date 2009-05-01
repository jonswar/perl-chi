package CHI::t::Subclass;
use strict;
use warnings;
use CHI::Test;
use base qw(CHI::Test::Class);

# Test declare_unsupported_methods
#
{

    package CHI::t::Subclass::Driver::HasUnsupported;
    use Mouse;
    extends 'CHI::Driver::Memory';
    __PACKAGE__->declare_unsupported_methods(qw(get_namespaces));
    __PACKAGE__->meta->make_immutable;
}

sub test_unsupported : Tests(2) {
    my $cache = CHI->new(
        driver_class => 'CHI::t::Subclass::Driver::HasUnsupported',
        global       => 1
    );
    lives_ok( sub { $cache->get_keys }, 'get_keys lives' );
    throws_ok(
        sub { $cache->get_namespaces },
        qr/method 'get_namespaces' not supported by 'CHI::t::Subclass::Driver::HasUnsupported'/,
        'get_namespaces dies'
    );
}

1;
