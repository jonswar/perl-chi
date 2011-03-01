package CHI::t::Driver::File::DepthZero;
use strict;
use warnings;
use CHI::Test;
use File::Temp qw(tempdir);
use File::Basename qw(dirname);
use base qw(CHI::t::Driver::File);

# Test file driver with zero depth

sub testing_driver_class { 'CHI::Driver::File' }

sub new_cache_options {
    my $self = shift;

    return ( $self->SUPER::new_cache_options(), depth => 0 );
}

sub test_default_depth : Tests {
    my $self = shift;

    my $cache = $self->new_cache();
    is( $cache->depth, 0 );
    is( dirname( $cache->path_to_key('foo') ),
        $cache->path_to_namespace, "data files are one level below namespace" );
}

1;
