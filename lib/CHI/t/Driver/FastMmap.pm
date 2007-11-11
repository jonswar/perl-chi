package CHI::t::Driver::FastMmap;
use CHI::Test;
use File::Temp qw(tempdir);
use strict;
use warnings;
use base qw(CHI::t::Driver);

my $root_dir;

sub new_cache_options {
    my $self = shift;

    $root_dir ||=
      tempdir( "chi-driver-fastmmap-XXXX", TMPDIR => 1, CLEANUP => 1 );
    return ( $self->SUPER::new_cache_options(), root_dir => $root_dir );
}

1;
