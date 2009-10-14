package CHI::t::Driver::Memory;
use strict;
use warnings;
use CHI::Test;
use CHI::Test::Driver::Role::CheckKeyValidity;
use Test::Warn;
use base qw(CHI::t::Driver);

# Skip multiple process test
sub test_multiple_procs { }

sub new_cache_options {
    my $self = shift;

    return ( $self->SUPER::new_cache_options(), global => 1 );
}

sub new_cache {
    my $self   = shift;
    my %params = @_;

    # If new_cache called with datastore, ignore global flag (otherwise would be an error)
    #
    if ( $params{datastore} ) {
        $params{global} = 0;
    }

    # Check test key validity on every get and set - only necessary to do for one driver
    #
    $params{roles}       = ['CHI::Test::Driver::Role::CheckKeyValidity'];
    $params{test_object} = $self;

    my $cache = CHI->new( $self->new_cache_options(), %params );
    return $cache;
}

sub test_short_driver_name : Tests(1) {
    my ($self) = @_;

    my $cache = $self->{cache};
    is( $cache->short_driver_name, 'Memory' );
}

# Warn if global or datastore not passed, but still use global datastore by default
#
sub test_global_or_datastore_required : Tests(3) {
    my ( $cache, $cache2 );
    warning_like( sub { $cache = CHI->new( driver => 'Memory' ) },
        qr/must specify either/ );
    warning_like( sub { $cache2 = CHI->new( driver => 'Memory' ) },
        qr/must specify either/ );
    $cache->set( 'foo', 5 );
    is( $cache2->get('foo'), 5, "defaulted to global datastore" );
}

# Make sure two caches don't share datastore
#
sub test_different_datastores : Tests(1) {
    my $self   = shift;
    my $cache1 = CHI->new( driver => 'Memory', datastore => {} );
    my $cache2 = CHI->new( driver => 'Memory', datastore => {} );
    $self->set_some_keys($cache1);
    ok( $cache2->is_empty() );
}

# Make sure cache is cleared when datastore itself is cleared
#
sub test_clear_datastore : Tests {
    my $self = shift;
    $self->num_tests( $self->{key_count} * 3 + 6 );

    my (@caches);

    my %datastore;
    $caches[0] =
      $self->new_cache( namespace => 'name', datastore => \%datastore );
    $caches[1] =
      $self->new_cache( namespace => 'other', datastore => \%datastore );
    $caches[2] =
      $self->new_cache( namespace => 'name', datastore => \%datastore );
    $self->set_some_keys( $caches[0] );
    $self->set_some_keys( $caches[1] );
    %datastore = ();

    foreach my $i ( 0 .. 2 ) {
        $self->_verify_cache_is_cleared( $caches[$i],
            "cache $i after out of scope" );
    }
}

sub test_lru_discard : Tests(2) {
    my $self = shift;
    my $cache = $self->new_cleared_cache( max_size => 41 );
    is( $cache->discard_policy, 'lru' );
    my $value_20 = 'x' x 6;
    foreach my $key ( map { "key$_" } qw(1 2 3 4 5 6 5 6 5 3 2) ) {
        $cache->set( $key, $value_20 );
    }
    cmp_set( [ $cache->get_keys ], [ "key2", "key3" ] );
}

1;
