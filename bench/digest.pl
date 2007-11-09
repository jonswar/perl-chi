#!/usr/bin/perl
use Benchmark qw(:all);
use Digest::JHash;
use Digest::MD5 qw(md5_hex);
use String::Random qw(random_string);
use warnings;
use strict;

my @keys = map { random_string(scalar("c" x ($_ * 10))) } (1..20);

sub md5
{
    foreach my $key (@keys) {
        my $hash = substr(md5_hex($key), 0, 3);
    }
}

sub jhash
{
    foreach my $key (@keys) {
        my $hash = substr(sprintf("%x", Digest::JHash::jhash($key)), 0, 3);
    }
}

timethese(10000, {
    'MD5'  => \&md5,
    'JHash' => \&jhash,
         });
