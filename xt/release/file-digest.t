#!perl
#
# Test file_digest and file_extension parameter
#
use strict;
use warnings;
use File::Basename;
use File::Temp qw(tempdir);
use Test::More tests => 1;
use CHI;

my $root_dir = tempdir( "file-digest-XXXX", TMPDIR => 1, CLEANUP => 1 );
my $cache = CHI->new(
    driver         => 'File',
    root_dir       => $root_dir,
    key_digest    => 'SHA-1',
    file_extension => '.sha'
);
my $key  = scalar( 'ab' x 256 );
my $file = basename( $cache->path_to_key($key) );
is( $file, 'db62ffe116024a7a4e1bd949c0e30dbae9b5db77.sha', 'SHA-1 digest' );
