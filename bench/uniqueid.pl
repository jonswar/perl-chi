#!/usr/bin/perl
use Benchmark qw(:all);
use Data::UUID;
use Sys::HostIP;
use warnings;
use strict;

my $ug = Data::UUID->new();

my $idnum = 0;
my $netaddr = sprintf( '%02X%02X%02X%02X', split( /\./, Sys::HostIP->ip ) );

my $plusctr = 0;
my $uuid = $ug->create_hex;

timethese(400000, {
    'uuid'          => sub { my $hex = $ug->create_hex },
    'uuid_plus'     => sub { if (!$plusctr) { $uuid = $ug->create_hex }; my $hex = sprintf('%s%04x', $uuid, $plusctr++); $plusctr &= 0xffff },
    'sys::uniqueid' => sub { my $hex = sprintf '%012X.%s.%08X.%08X', time, $netaddr, $$, ++$idnum },
          });
