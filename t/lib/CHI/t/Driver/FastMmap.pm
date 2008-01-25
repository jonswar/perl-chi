package CHI::t::Driver::FastMmap;
use strict;
use warnings;
use CHI::Test;
use CHI::Util qw(dp);
use File::Temp qw(tempdir);
use base qw(CHI::t::Driver);

my $root_dir;

sub required_modules {
    return { 'Cache::FastMmap' => undef };
}

sub new_cache_options {
    my $self = shift;

    $root_dir ||=
      tempdir( "chi-driver-fastmmap-XXXX", TMPDIR => 1, CLEANUP => 1 );
    return ( $self->SUPER::new_cache_options(), root_dir => $root_dir );
}

1;
