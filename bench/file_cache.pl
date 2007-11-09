#!/usr/bin/perl
use FindBin::libs;
use Benchmark qw(:all);
use Cache::FileCache;
use CHI;
use Cwd qw(realpath);
use Data::Dump qw(dump);
use File::Basename;
use File::Path qw(rmtree);
use File::Temp qw(tempdir);
use Getopt::Long;
use String::Random qw(random_string);
use warnings;
use strict;

my $cwd = dirname(realpath($0));

my $only_chi = '';
my $test_writes = 0;
GetOptions(
    'only-chi' => \$only_chi,
    'test-writes' => \$test_writes,
    );

my @keys = map { random_string(scalar("c" x ($_ * 2))) } (1..100);

sub temp_dir
{
    return tempdir('name-XXXX', TMPDIR => 1, CLEANUP => 1);
}

sub test_cache
{
    my ($cache) = @_;

    if ($test_writes) {
        foreach my $key (@keys) {
            $cache->set($key, $key);
        }
    }
    else {
        foreach my $key (@keys) {
            $cache->get($key);
        }
    }
}

rmtree("$cwd/caches");
my $chi_cache = CHI->new(driver => 'File', root_dir => "$cwd/caches/chi_cache");
my $cache_cache;
$cache_cache = Cache::FileCache->new({cache_root => "$cwd/caches/cache_cache"}) unless $only_chi;
unless ($test_writes) {
    foreach my $key (@keys) {
        $chi_cache->set($key, $key);
    }
    unless ($only_chi) {
        foreach my $key (@keys) {
            $cache_cache->set($key, $key);
        }
    }
}

sub bench
{
    my $iter = $test_writes ? 20 : 100;
    timethese($iter, {
        'CHI::Driver::File' => sub { test_cache($chi_cache) },
        ($only_chi ? () : ('Cache::FileCache'  => sub { test_cache($cache_cache) })),
              });
}

bench();
