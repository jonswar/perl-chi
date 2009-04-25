package CHI::t::Driver::Subcache::l1_cache;
use strict;
use warnings;
use CHI::Test;
use File::Temp qw(tempdir);
use base qw(CHI::t::Driver::Subcache);

my $root_dir;

sub new_cache_options {
    my $self = shift;

    $root_dir ||=
      tempdir( "chi-driver-subcache-l1-XXXX", TMPDIR => 1, CLEANUP => 1 );
    return (
        $self->SUPER::new_cache_options(),
        driver   => 'File',
        root_dir => $root_dir,
        l1_cache => { driver => 'Memory' },
    );
}

1;
