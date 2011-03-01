#!/usr/bin/perl
#
# Compare various cache backends
#
use Cwd qw(realpath);
use Data::Dump qw(dump);
use DBI;
use DBD::mysql;
use File::Basename;
use File::Path;
use Getopt::Long;
use Hash::MoreUtils qw(slice_def);
use Pod::Usage;
use Text::Table;
use YAML::Any qw(DumpFile);
use warnings;
use strict;

my %cache_generators = cache_generators();

# Load local version of Cache::Benchmark until we get changes into CPAN
# version
#
my $cwd = dirname( realpath($0) );
unshift( @INC, "$cwd/lib" );
require Cache::Benchmark;

sub usage {
    pod2usage( -verbose => 1, -exitval => "NOEXIT" );
    print "Valid drivers: " . join( ", ", sort keys(%cache_generators) ) . "\n";
    exit(1);
}

my $count         = 10000;
my $set_frequency = 0.05;
my ( $complex, $drivers_pattern, $help, $incs, $sort_by_name );
usage() if !@ARGV;
GetOptions(
    'c|count=i'         => \$count,
    'h|help'            => \$help,
    'n'                 => \$sort_by_name,
    's|set_frequency=s' => \$set_frequency,
    'd|drivers=s'       => \$drivers_pattern,
    'x|complex'         => \$complex,
    'I=s'               => \$incs,
) or usage();
usage() if $help || !$drivers_pattern;

my $value =
  $complex
  ? { map { ( $_, scalar( $_ x 100 ) ) } qw(a b c d e) }
  : scalar( 'x' x 500 );
my $sets = int( $count * $set_frequency );

unshift( @INC, split( /,/, $incs ) ) if $incs;
require CHI;

print "running $count iterations\n";
print "CHI version $CHI::VERSION\n" if $CHI::VERSION;

my $data = "$cwd/data";
rmtree($data);
mkpath( $data, 0, 0775 );

my %common_chi_opts = ( on_get_error => 'die', on_set_error => 'die' );

my @drivers = grep { /$drivers_pattern/ } keys(%cache_generators);
my %caches = map { ( $_, $cache_generators{$_}->{code}->($count) ) } @drivers;
print "Drivers: " . join( ", ", @drivers ) . "\n";

my $cb = new Cache::Benchmark();
$cb->init( keys => $sets, access_counter => $count, value => $value );

my @names = sort keys(%caches);
my %results;
foreach my $name (@names) {
    print "Running $name...\n";
    my $cache = $caches{$name};
    $cb->run($cache);
    my $result    = $cb->get_raw_result;
    my @colvalues = (
        $name,
        $result->{reads},
        $result->{writes},
        sprintf( "%.2fms", $result->{get_time} * 1000 / $result->{reads} ),
        sprintf( "%.2fms", $result->{set_time} * 1000 / $result->{writes} ),
        sprintf( "%.2fs",  $result->{runtime} )
    );
    $results{$name} = \@colvalues;
}

my $tb = Text::Table->new( 'Cache', 'Gets', 'Sets', 'Get time', 'Set time',
    'Run time' );
my $sort_field = $sort_by_name ? 0 : 3;
my @rows =
  sort { $results{$a}->[$sort_field] cmp $results{$b}->[$sort_field] }
  keys(%results);
$tb->add( @{ $results{$_} } ) for @rows;

print $tb;
DumpFile( 'results.dat', \%results );

sub cache_generators {
    return (
        cache_cache_file => {
            desc => 'Cache::FileCache',
            code => sub {
                require Cache::FileCache;
                Cache::FileCache->new(
                    {
                        cache_root  => "$data/cachecache/file",
                        cache_depth => 2,
                    }
                );
              }
        },
        cache_cache_memory => {
            desc => 'Cache::MemoryCache',
            code => sub {
                require Cache::MemoryCache;
                Cache::MemoryCache->new();
              }
        },
        cache_fastmmap => {
            desc => 'Cache::FastMmap',
            code => sub {
                require Cache::FastMmap;
                my $fastmmap_file = "$data/fastmmap.fm";
                Cache::FastMmap->new( share_file => $fastmmap_file, );
              }
        },
        cache_memcached_lib => {
            desc => 'Cache::Memcached::libmemcached',
            code => sub {
                Cache::Memcached::libmemcached->new(
                    servers => ["localhost:11211"], );
              }
        },
        cache_memcached_fast => {
            desc => 'Cache::Memcached::Fast',
            code => sub {
                Cache::Memcached::Fast->new( servers => ["localhost:11211"], );
              }
        },
        cache_memcached_std => {
            desc => 'Cache::Memcached',
            code => sub {
                Cache::Memcached->new( servers => ["localhost:11211"], );
              }
        },
        cache_ref => {
            desc => 'Cache::Ref',
            code => sub {
                my $count = shift;
                require Cache::Ref::CART;
                Cache::Ref::CART->new( size => $count * 2 );
              }
        },
        chi_berkeleydb => {
            desc => 'CHI::Driver::BerkeleyDB',
            code => sub {
                CHI->new(
                    %common_chi_opts,
                    driver   => 'BerkeleyDB',
                    root_dir => "$data/chi/berkeleydb",
                );
              }
        },
        chi_dbi_mysql => {
            desc => 'CHI::Driver::DBI (mysql)',
            code => sub {
                my $mysql_dbh =
                  DBI->connect( "DBI:mysql:database=chibench;host=localhost",
                    "chibench", "chibench" );
                CHI->new(
                    %common_chi_opts,
                    driver       => 'DBI',
                    dbh          => $mysql_dbh,
                    create_table => 1,
                );
              }
        },
        chi_dbi_sqlite => {
            desc => 'CHI::Driver::DBI (sqlite)',
            code => sub {
                my $sqlite_dbh =
                  DBI->connect( "DBI:SQLite:dbname=$data/sqlite.db",
                    "chibench", "chibench" );
                CHI->new(
                    %common_chi_opts,
                    driver       => 'DBI',
                    dbh          => $sqlite_dbh,
                    create_table => 1,
                );
              }
        },
        chi_fastmmap => {
            desc => 'CHI::Driver::FastMmap',
            code => sub {
                CHI->new(
                    %common_chi_opts,
                    driver   => 'FastMmap',
                    root_dir => "$data/chi/fastmmap",
                );
              }
        },
        chi_file => {
            desc => 'CHI::Driver::File',
            code => sub {
                CHI->new(
                    %common_chi_opts,
                    driver   => 'File',
                    root_dir => "$data/chi/file",
                    depth    => 2
                );
              }
        },
        chi_memcached_fast => {
            desc => 'CHI::Driver::Memcached::Fast',
            code => sub {
                CHI->new(
                    %common_chi_opts,
                    driver  => 'Memcached::Fast',
                    servers => ["localhost:11211"],
                );
              }
        },
        chi_memcached_lib => {
            desc => 'CHI::Driver::Memcached::libmemcached',
            code => sub {
                CHI->new(
                    %common_chi_opts,
                    driver  => 'Memcached::libmemcached',
                    servers => ["localhost:11211"],
                );
              }
        },
        chi_memcached_std => {
            desc => 'CHI::Driver::Memcached',
            code => sub {
                CHI->new(
                    %common_chi_opts,
                    driver  => 'Memcached',
                    servers => ["localhost:11211"],
                );
              }
        },
        chi_memory => {
            desc => 'CHI::Driver::Memory',
            code => sub {
                CHI->new(
                    %common_chi_opts,
                    driver    => 'Memory',
                    datastore => {},
                );
              }
        },
        chi_memory_raw => {
            desc => 'CHI::Driver::MemoryRaw',
            code => sub {
                CHI->new(
                    %common_chi_opts,
                    driver    => 'RawMemory',
                    datastore => {},
                );
            },
        },
    );
}

__END__

=head1 NAME

bench.pl -- Benchmark cache modules against each other

=head1 DESCRIPTION

Uses Cache::Benchmark to compare a variety of CHI and non-CHI caches in terms
of raw reading and writing speed. Sorts results by read performance. Does not
attempt to test discard policies.

=head1 SYNOPSIS

bench.pl -d driver_regex [options]

=head1 OPTIONS

  -d driver_regex    Run drivers matching this regex (required)
  -I path,...        Add one or more comma-separated paths to @INC
  -c count           Run this many iterations (default 10000)
  -n                 Sort results by name instead of by read performance
  -s set_frequency   Run this many sets as a percentage of gets (default 0.05)
  -x|--complex       Use a complex data structure instead of a scalar

=cut
