#!/usr/bin/perl
#
# Compare various cache backends
#
use Cache::Benchmark;
use Cwd qw(realpath);
use Data::Dump qw(dump);
use DBI;
use DBD::mysql;
use File::Basename;
use File::Path;
use Getopt::Long;
use Hash::MoreUtils qw(slice_def);
use List::Util qw(sum);
use List::MoreUtils qw(uniq);
use Pod::Usage;
use Text::Table;
use Try::Tiny;
use YAML::Any qw(DumpFile);
use warnings;
use strict;

my %cache_generators = cache_generators();

sub usage {
    pod2usage( -verbose => 1, -exitval => "NOEXIT" );
    print "Valid drivers: " . join( ", ", sort keys(%cache_generators) ) . "\n";
    print "To install all requirements:\n  cpanm " . join(" ", sort(uniq(map { @{$_->{req} || []} } values(%cache_generators)))) . "\n";
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
) or usage();
usage() if $help || !$drivers_pattern;

my $value =
  $complex
  ? { map { ( $_, scalar( $_ x 100 ) ) } qw(a b c d e) }
  : scalar( 'x' x 500 );
my $sets = int( $count * $set_frequency );
my $iterations = 10;

require CHI;

print "benchmarking $count operations split over $iterations iterations\n";
print "CHI version $CHI::VERSION\n" if $CHI::VERSION;

my $cwd = dirname(realpath($0));
my $data = "$cwd/data";
rmtree($data);
mkpath( $data, 0, 0775 );

my %common_chi_opts = ( on_get_error => 'die', on_set_error => 'die' );

my %caches;
foreach my $name (grep { /$drivers_pattern/ } keys(%cache_generators)) {
    try {
        if (my $req = $cache_generators{$name}->{req}) {
            Class::MOP::load_class($_) foreach @$req;
        }
        $caches{$name} = $cache_generators{$name}->{code}->($count);
    } catch {
        warn "error initializing '$name', will skip - $_";
    }
}
my @names = sort(keys(%caches));
print "Drivers: " . join( ", ", @names ) . "\n";

my $cb = new Cache::Benchmark();
$cb->init( keys => int($sets / $iterations), access_counter => int($count / $iterations), value => $value );

my %results;
foreach my $iter (0..$iterations-1) {
    print "Iteration $iter\n";
    foreach my $name (@names) {
        my $cache = $caches{$name};
        add_fake_purge($cache);
        $cb->run($cache);
        foreach my $field qw(get_time set_time reads writes runtime) {
            $results{$name}->{$field} += $cb->get_raw_result->{$field};
        }
    }
}

my (%colvalues, $reads, $writes);
foreach my $name (@names) {
    my $generator = $cache_generators{$name};
    my $result = $results{$name};
    my @colvalues = (
        $name,
        sprintf( "%.2fms", $result->{get_time} * 1000 / $result->{reads} ),
        sprintf( "%.2fms", $result->{set_time} * 1000 / $result->{writes} ),
        sprintf( "%.2fs",  $result->{runtime} ),
        $generator->{desc},
        );
    $colvalues{$name} = \@colvalues;
    $reads = $result->{reads};
    $writes = $result->{writes};
}

my $tb = Text::Table->new( 'Cache', "Get time\n&right", "Set time\n&right", "Run time\n&right",  'Description' );
my $sort_field = $sort_by_name ? 0 : 3;
my @rows =
  sort { $colvalues{$a}->[$sort_field] cmp $colvalues{$b}->[$sort_field] }
  keys(%colvalues);
$tb->add( @{ $colvalues{$_} } ) for @rows;

printf ("%s gets, %s sets, %s total operations\n", $reads, $writes, $reads+$writes); 

print $tb;
DumpFile( 'results.dat', \%colvalues );

sub add_fake_purge {
    my ($cache) = @_;
    if (!$cache->can('purge')) {
        my $method_name = ref($cache) . "::purge";
        no strict 'refs';
        *$method_name = sub {};
    }
}

sub cache_generators {
    return (
        cache_cache_file => {
            req => ['Cache::FileCache'],
            desc => 'Cache::FileCache',
            code => sub {
                Cache::FileCache->new(
                    {
                        cache_root  => "$data/cachecache/file",
                        cache_depth => 2,
                    }
                );
              }
        },
        cache_cache_memory => {
            req => ['Cache::MemoryCache'],
            desc => 'Cache::MemoryCache',
            code => sub {
                Cache::MemoryCache->new();
              }
        },
        cache_fastmmap => {
            req => ['Cache::FastMmap'],
            desc => 'Cache::FastMmap',
            code => sub {
               
                my $fastmmap_file = "$data/fastmmap.fm";
                Cache::FastMmap->new( share_file => $fastmmap_file, );
              }
        },
        cache_memcached_lib => {
            req => ['Cache::Memcached::libmemcached'],
            desc => 'Cache::Memcached::libmemcached',
            code => sub {
                Cache::Memcached::libmemcached->new(
                    { servers => ["localhost:11211"] }, );
              }
        },
        cache_memcached_fast => {
            req => ['Cache::Memcached::Fast'],
            desc => 'Cache::Memcached::Fast',
            code => sub {
                Cache::Memcached::Fast->new( { servers => ["localhost:11211"] } );
              }
        },
        cache_memcached_std => {
            req => ['Cache::Memcached'],
            desc => 'Cache::Memcached',
            code => sub {
                Cache::Memcached->new( { servers => ["localhost:11211"] } );
              }
        },
        cache_ref => {
            req => ['Cache::Ref::CART'],
            desc => 'Cache::Ref',
            code => sub {
                my $count = shift;
               
                Cache::Ref::CART->new( size => $count * 2 );
              }
        },
        chi_berkeleydb => {
            req => ['CHI::Driver::BerkeleyDB'],
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
            req => ['CHI::Driver::DBI', 'DBD::mysql'],
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
            req => ['CHI::Driver::DBI', 'DBD::SQLite'],
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
            req => ['CHI::Driver::Memcached::Fast'],
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
            req => ['CHI::Driver::Memcached::libmemcached'],
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
            req => ['CHI::Driver::Memcached'],
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

  -d driver_regex    Run drivers matching this regex (required) - use '.' for all
  -c count           Run this many iterations (default 10000)
  -n                 Sort results by name instead of by read performance
  -s set_frequency   Run this many sets as a percentage of gets (default 0.05)
  -x|--complex       Use a complex data structure instead of a scalar

=head1 REQUIREMENTS

=over

=item *

For the mysql drivers, run this as mysql root:

    create database chibench;
    grant all privileges on chibench.* to 'chibench'@'localhost' identified by 'chibench';

=item *

For the memcached drivers, you'll need to start memcached on the default port (11211).

=back

=cut
