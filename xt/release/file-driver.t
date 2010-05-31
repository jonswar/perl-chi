#!perl
#
use strict;
use warnings;
use File::Basename;
use File::Temp qw(tempdir);
use Test::More tests => 6;
use Test::Exception;
use CHI;

my $root_dir = tempdir( "file-digest-XXXX", TMPDIR => 1, CLEANUP => 1 );
my $cache;

# Test key_digest (old name for key_digester) and file_extension
#
$cache = CHI->new(
    driver         => 'File',
    root_dir       => $root_dir,
    key_digest     => 'SHA-1',
    file_extension => '.sha'
);
my $key  = scalar( 'ab' x 256 );
my $file = basename( $cache->path_to_key($cache->transform_key($key)) );
is( $file, 'db62ffe116024a7a4e1bd949c0e30dbae9b5db77.sha', 'SHA-1 digest' );

# These tests will break if the path_to_key algorithm changes.  We want
# to avoid this if possible and otherwise warn users about it.
#
$cache = CHI->new(
    driver         => 'File',
    root_dir       => $root_dir
    );
my @pairs =
    ([0, '6/3/0'],
     [1, '0/4/1'],
     ['medium', 'b/6/medium'],
     ['$20.00 plus 5% = $25.00', '+2420+2e00+20plus+205+25+20=+20+2425+2e00'],
     ["!@#" x 100, '2/d/2d30ab2394c82169942247a2c9583d9d']);
foreach my $pair (@pairs) {
    my ($key, $expected) = @$pair;
    like($cache->path_to_key($cache->transform_key($key)), qr/\Q$expected\E\.dat/, "path for key '$key'");
}
