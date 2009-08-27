#!perl
#
# Tests that files pass critic
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

# Ensure a standard version of Perl::Critic
use Perl::Critic 1.080;

my $root   = dirname(dirname( dirname( realpath($0) ) ));
my $rcfile = "$root/perlcriticrc";

my @files;
find(
    {
        wanted => sub { push( @files, $_ ) if /CHI/ && /\.pm$/ },
        no_chdir => 1
    },
    "$root/lib",
);
my $base_sig = join( '; ',
    map { File::Signature->new($_) } ( $rcfile, $INC{'Perl/Critic.pm'} ) );

sub sig {
    my ($file) = @_;

    return join( '; ', $base_sig, File::Signature->new($file) );
}

my $cache = CHI->new(
    driver    => 'FastMmap',
    root_dir  => "$root/data/cache",
    namespace => 'critic',
);

my $critic = Perl::Critic->new( -profile => $rcfile );
Perl::Critic::Violation::set_format(
    "%m at %f line %l. %e. Perl::Critic::Policy::%p.\n");

my $violation_count = 0;
foreach my $file (@files) {
    if ( ( $cache->get($file) || '' ) ne sig($file) ) {
        diag "checking $file\n";
        if ( my @violations = $critic->critique($file) ) {
            diag( map { "** $_" } @violations );
            $violation_count += @violations;
        }
        else {
            $cache->set( $file, sig($file) );
        }
    }
}
ok( !$violation_count, "$violation_count violations found");
