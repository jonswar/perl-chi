#!perl
#
# Tests that things work ok (with warning) without Data::Serializer installed
#
use strict;
use warnings;
use CHI::Test::InternalOnly;

use Test::More tests => 3;
use Test::Exception;
use Module::Mask;
use Module::Load::Conditional qw(can_load);
our $mask;
BEGIN { $mask = new Module::Mask ('Data::Serializer') }
use CHI;

require CHI::Driver;

my $cache;
throws_ok { $cache = CHI->new(driver => 'Memory', serializer => 'Data::Dumper') } qr/Data::Serializer not installed/, "dies with serializer";
lives_ok { $cache = CHI->new(driver => 'Memory') } "lives with no serializer";
$cache->set('foo', 5);
is($cache->get('foo'), 5, 'cache get ok');
