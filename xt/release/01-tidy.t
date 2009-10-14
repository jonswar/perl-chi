#!perl
#
# Tests that files are tidied, and tidies them if they are not
# Uses cache so that files are only checked when modified
#
use strict;
use warnings;
use CHI;
use Cwd qw(realpath);
use File::Basename;
use File::Find;
use File::Signature;
use File::Slurp;
use Test::More tests => 1;

# Ensure a standard version of Perl::Tidy and Pod::Tidy
use Perl::Tidy 20071205;
use Pod::Tidy 0.10;

my $root   = dirname( dirname( dirname( realpath($0) ) ) );
my $rcfile = "$root/.perltidyrc";

my @files;
find(
    {
        wanted => sub { push( @files, $_ ) if /CHI/ && /\.pm$/ },
        no_chdir => 1
    },
    "$root/lib",
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
    namespace => '01-tidy.t',
);

my $tidied = 0;
foreach my $file (@files) {
    if ( ( $cache->get($file) || '' ) ne sig($file) ) {
        my $source_contents = read_file($file);
        Perl::Tidy::perltidy(
            source      => \$source_contents,
            destination => \my $result,
            perltidyrc  => $rcfile
        );
        write_file( $file, $result );
        Pod::Tidy::tidy_files(
            files    => [$file],
            inplace  => 1,
            nobackup => 1
        );
        if ( read_file($file) ne $source_contents ) {
            diag "$file was not tidy (tidying now)\n";
            $tidied++;
        }
        $cache->set( $file, sig($file) );
    }
}
ok( !$tidied, "$tidied files tidied" );
