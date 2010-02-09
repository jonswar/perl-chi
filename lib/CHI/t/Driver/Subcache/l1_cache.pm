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

sub test_stats : Test(3) {
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
        qr/CHI stats: namespace='Foo'; cache='File'; start=.*; end=.*; absent_misses=1; set_key_size=6; set_value_size=20; sets=1/
    );
    $log->contains_ok(
        qr/CHI stats: namespace='Foo'; cache='File:l1_cache'; start=.*; end=.*; absent_misses=1; hits=1/
    );

}

1;
