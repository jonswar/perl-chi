package CHI::t::Bugs;
use strict;
use warnings;
use CHI::Test;
use File::Temp qw(tempdir);
use d;
use base qw(CHI::Test::Class);

# A place for testing obscure bug fixes. When possible, test will be named for RT ticket.

sub test_48998 : Test(1) {
    my $cache = CHI->new( driver => 'Memory', global => 1 );
    $cache->set( 'a', 5 );
    $cache->set( 'b', 6 );
    eval { die "bleah" };
    cmp_deeply( $cache->get_multi_arrayref( [ 'a', 'b' ] ),
        [ 5, 6 ], "get_multi" );
}

sub test_43409 : Test(1) {
    my $cache_root = tempdir( 'bugs-XXXX', TMPDIR => 1, CLEANUP => 1 );
    my $cache = CHI->new( driver => 'File', cache_root => $cache_root );
    is( $cache->root_dir, $cache_root );
}

1;
