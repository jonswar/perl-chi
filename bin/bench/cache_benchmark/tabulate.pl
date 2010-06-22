#!/usr/bin/perl
use HTML::Table;
use File::Slurp;
use YAML::Any qw(LoadFile);
use warnings;
use strict;

my $table_format;
my $html       = '';
my %results    = %{ LoadFile("results.dat") };
my @all_caches = sort keys %results;

sub make_table {
    my ( $title, $caches ) = @_;

    my $table = new HTML::Table(
        -border => 1,
        -class  => 'cachestats',
        -head =>
          [ 'Cache', 'Gets', 'Sets', 'Get time', 'Set time', 'Run time' ],
    );

    foreach my $cache (@$caches) {
        my $result = $results{$cache} or die "no result for '$cache'";
        $table->addRow(@$result);
    }

    $table->setColAlign( 1, 'left' );
    map { $table->setColAlign( $_, 'right' ) } ( 2 .. 6 );

    $html .= sprintf( $table_format, $title, $table->getTable );
}

sub main {
    make_table( 'All CHI drivers', [ grep { /^chi_/ } @all_caches ] );
    make_table( 'Cache::Cache vs CHI',
        [qw(cache_cache_memory chi_memory cache_cache_file chi_file)] );
    make_table( 'CHI vs native',
        [qw(cache_fastmmap chi_fastmmap cache_memcached chi_memcached)] );
    write_file(
        "/home/swartz/servers/openswartz/docs/perl/chi/stats/stats.mhtml",
        $html );
}

$table_format = '
<h2>%s</h2>

%s
';

main();
