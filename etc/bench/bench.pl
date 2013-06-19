#!/usr/bin/perl
#
# Compare various cache backends
#
use Benchmark qw(:hireswallclock timethese);
use Capture::Tiny qw(capture);
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
use Module::Runtime qw(require_module);
use warnings;
use strict;

my %cache_generators = cache_generators();

sub usage {
    pod2usage( -verbose => 1, -exitval => "NOEXIT" );
    print "Valid drivers: " . join( ", ", sort keys(%cache_generators) ) . "\n";
    print "To install all requirements:\n  cpanm "
      . join( " ",
        sort( uniq( map { @{ $_->{req} || [] } } values(%cache_generators) ) ) )
      . "\n";
    exit(1);
}

my $time = 2;
my ( $complex, $drivers_pattern, $help, $incs, $sort_by_name );
usage() if !@ARGV;
GetOptions(
    'd|drivers=s' => \$drivers_pattern,
    'h|help'      => \$help,
    'n'           => \$sort_by_name,
    't|time=s'    => \$time,
    'x|complex'   => \$complex,
) or usage();
usage() if $help || !$drivers_pattern;

my $value =
  $complex
  ? { map { ( $_, scalar( $_ x 100 ) ) } qw(a b c d e) }
  : scalar( 'x' x 500 );
my $num_keys = 1000;

require CHI;

print "CHI version $CHI::VERSION\n" if $CHI::VERSION;

my $cwd  = dirname( realpath($0) );
my $data = "$cwd/data";
rmtree($data);
mkpath( $data, 0, 0775 );

my %common_chi_opts = ( on_get_error => 'die', on_set_error => 'die' );

my %caches;
foreach my $name ( grep { /$drivers_pattern/ } keys(%cache_generators) ) {
    try {
        if ( my $req = $cache_generators{$name}->{req} ) {
            require_module($_) foreach @$req;
        }
        $caches{$name} = $cache_generators{$name}->{code}->();
    }
    catch {
        warn "error initializing '$name', will skip - $_";
    };
}

my @names = sort( keys(%caches) );
print "Drivers: " . join( ", ", @names ) . "\n";

my %counts;

# Sets
my $set_results;
print "Benchmarking sets\n";
$set_results = timethese(
    -1 * $time,
    {
        map {
            my $name  = $_;
            my $cache = $caches{$name};
            my $key   = 0;
            (
                $name,
                sub {
                    my $key = ( $counts{$name}++ % 100 );
                    $cache->set( $key, $value );
                }
            );
          } @names
    }
);

# Gets
my $get_results;
print "Benchmarking gets\n";
$get_results = timethese(
    -1 * $time,
    {
        map {
            my $name  = $_;
            my $cache = $caches{$name};
            my $key   = 0;
            (
                $name,
                sub {
                    my $key = ( $counts{$name}++ % 100 );
                    $cache->get($key);
                }
            );
          } @names
    }
);

my %colvalues;
foreach my $name (@names) {
    my $generator = $cache_generators{$name};
    my $get       = ms_time( $get_results->{$name} );
    my $set       = ms_time( $set_results->{$name} );
    my @colvalues = ( $name, $get . "ms", $set . "ms", $generator->{desc}, );
    $colvalues{$name} = \@colvalues;
}

my $tb = Text::Table->new(
    'Cache',
    "Get time\n&right",
    "Set time\n&right",
    'Description'
);
my $sort_field = $sort_by_name ? 0 : 1;
my @rows =
  sort { $colvalues{$a}->[$sort_field] cmp $colvalues{$b}->[$sort_field] }
  keys(%colvalues);
$tb->add( @{ $colvalues{$_} } ) for @rows;

print $tb;

sub ms_time {
    my $result = shift;
    return sprintf( "%0.3f", ( $result->[0] / $result->[5] ) * 1000 );
}

sub cache_generators {
    return (
        cache_cache_file => {
            req  => ['Cache::FileCache'],
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
            req  => ['Cache::MemoryCache'],
            desc => 'Cache::MemoryCache',
            code => sub {
                Cache::MemoryCache->new();
              }
        },
        cache_fastmmap => {
            req  => ['Cache::FastMmap'],
            desc => 'Cache::FastMmap',
            code => sub {

                my $fastmmap_file = "$data/fastmmap.fm";
                Cache::FastMmap->new( share_file => $fastmmap_file, );
              }
        },
        cache_memcached_lib => {
            req  => ['Cache::Memcached::libmemcached'],
            desc => 'Cache::Memcached::libmemcached',
            code => sub {
                Cache::Memcached::libmemcached->new(
                    { servers => ["localhost:11211"] },
                );
              }
        },
        cache_memcached_fast => {
            req  => ['Cache::Memcached::Fast'],
            desc => 'Cache::Memcached::Fast',
            code => sub {
                Cache::Memcached::Fast->new(
                    { servers => ["localhost:11211"] } );
              }
        },
        cache_memcached_std => {
            req  => ['Cache::Memcached'],
            desc => 'Cache::Memcached',
            code => sub {
                Cache::Memcached->new( { servers => ["localhost:11211"] } );
              }
        },
        cache_ref => {
            req  => ['Cache::Ref::CART'],
            desc => 'Cache::Ref (CART)',
            code => sub {
                Cache::Ref::CART->new( size => 10000 );
              }
        },
        chi_berkeleydb => {
            req  => ['CHI::Driver::BerkeleyDB'],
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
            req  => [ 'CHI::Driver::DBI', 'DBD::mysql' ],
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
            req  => [ 'CHI::Driver::DBI', 'DBD::SQLite' ],
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
            req  => ['CHI::Driver::Memcached::Fast'],
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
            req  => ['CHI::Driver::Memcached::libmemcached'],
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
            req  => ['CHI::Driver::Memcached'],
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
            desc => 'CHI::Driver::RawMemory',
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

Uses L<Benchmark> to compare a variety of CHI and non-CHI caches in terms of
raw reading and writing speed. Sorts results by read performance. Does not
attempt to test discard policies.

=head1 SYNOPSIS

bench.pl -d driver_regex [options]

=head1 OPTIONS

  -d driver_regex    Run drivers matching this regex (required) - use '.' for all
  -h --help          Print help message
  -n                 Sort results by name instead of by read performance
  -t time            Number of seconds to benchmark each operation (default 2)
  -x|--complex       Use a complex data structure instead of a scalar

Run bench.pl with no arguemnts to get a full list of available drivers.

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
