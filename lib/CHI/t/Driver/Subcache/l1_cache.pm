package CHI::t::Driver::Subcache::l1_cache;

use strict;
use warnings;
use CHI::Test;
use CHI::Test::Util qw(activate_test_logger);
use File::Temp qw(tempdir);
use base qw(CHI::t::Driver::Subcache);

my $root_dir;

sub testing_driver_class {
    return 'CHI::Driver::File';
}

sub new_cache_options {
    my $self = shift;

    $root_dir ||=
      tempdir( "chi-driver-subcache-l1-XXXX", TMPDIR => 1, CLEANUP => 1 );
    return (
        $self->SUPER::new_cache_options(),
        root_dir => $root_dir,
        l1_cache => { driver => 'Memory', global => 1 },
    );
}

sub test_stats : Tests {
    my $self = shift;

    my $stats = $self->testing_chi_root_class->stats;
    $stats->enable();

    my ( $key, $value ) = $self->kvpair();
    my $start_time = time();

    my $cache;
    $cache = $self->new_cache( namespace => 'Foo' );
    $cache->get($key);
    $cache->set( $key, $value, 80 );
    $cache->get($key);

    my $log = activate_test_logger();
    $log->empty_ok();
    $stats->flush();

    $log->contains_ok(
        qr/CHI stats: {"absent_misses":1,"end_time":\d+,"get_time_ms":\d+,"label":"File","namespace":"Foo","root_class":"CHI","set_key_size":6,"set_time_ms":\d+,"set_value_size":20,"sets":1,"start_time":\d+}/
    );
    $log->contains_ok(
        qr/CHI stats: {"absent_misses":1,"end_time":\d+,"get_time_ms":\d+,"hits":1,"label":"File:l1_cache","namespace":"Foo","root_class":"CHI","set_key_size":6,"set_time_ms":\d+,"set_value_size":20,"sets":1,"start_time":\d+}/
    );

}

# not working yet
sub test_append { }

# won't work in presence of l1 cache
sub test_max_key_length { }

1;
