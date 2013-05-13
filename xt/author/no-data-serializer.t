#!/usr/bin/perl
#
# Tests that things work ok (with warning) without Data::Serializer installed
#
use strict;
use warnings;
use Test::More tests => 3;
use Test::Exception;
use Module::Load::Conditional qw(can_load);
BEGIN {
    package
        MaskNativeMessage;
    use base qw(Module::Mask);
    my $test_module = "NonExistantModule" . time;
    my $native_message = do { eval "require $test_module"; $@ };
    sub message {
        my ($class, $filename) = @_;
        (my $message = $native_message) =~ s/\Q$test_module.pm/$filename/;
        return $message;
    }
    $::mask = $::mask = MaskNativeMessage->new('Data::Serializer');
}
use CHI;

require CHI::Driver;

my $cache;
throws_ok {
    $cache =
      CHI->new( driver => 'Memory', serializer => 'Data::Dumper', global => 1 );
}
qr/Could not load/, "dies with serializer";
lives_ok { $cache = CHI->new( driver => 'Memory', global => 1 ) }
"lives with no serializer";
$cache->set( 'foo', 5 );
is( $cache->get('foo'), 5, 'cache get ok' );
