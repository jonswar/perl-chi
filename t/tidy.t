#!perl
#
# Tests that files are tidied, and tidies them if they are not
# Uses cache so that files are only checked when modified
#
use strict;
use warnings;
use CHI::Test::InternalOnly;

use CHI;
use Cwd qw(realpath);
use File::Basename;
use File::Find;
use File::Signature;
use File::Slurp;
use Test::More tests => 1;

# Ensure a standard version of Perl::Tidy
use Perl::Tidy 20071205;

my $root   = dirname( dirname( realpath($0) ) );
my $rcfile = "$root/perltidyrc";

my @files;
find(
    {
        wanted => sub { push( @files, $_ ) if /CHI/ && /\.pm$/ },
        no_chdir => 1
    },
    "$root/lib",
    "$root/t/lib"
);
my $base_sig = join( '; ',
    map { File::Signature->new($_) } ( $rcfile, $INC{'Perl/Tidy.pm'} ) );

sub sig {
    my ($file) = @_;

    return join( '; ', $base_sig, File::Signature->new($file) );
}

my $cache = CHI->new(
    driver    => 'FastMmap',
    root_dir  => "$root/data/cache",
    namespace => 'tidy',
);

my $tidied = 0;
foreach my $file (@files) {
    if ( ( $cache->get($file) || '' ) ne sig($file) ) {
        Perl::Tidy::perltidy(
            source      => $file,
            destination => \my $result,
            perltidyrc  => $rcfile
        );
        if ( read_file($file) ne $result ) {
            diag "$file was not tidy (tidying now)\n";
            write_file( $file, $result );
            $tidied++;
        }
        $cache->set( $file, sig($file) );
    }
}
ok( !$tidied, "$tidied files tidied" );
