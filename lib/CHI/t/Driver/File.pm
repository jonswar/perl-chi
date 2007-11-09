package CHI::t::Driver::File;
use CHI::Test;
use File::Temp qw(tempdir);
use strict;
use warnings;
use base qw(CHI::t::Driver);

my $root_dir;

sub choose_root_dir : Test(startup) {
    $root_dir = tempdir( "chi-driver-file-XXXX", TMPDIR => 1, CLEANUP => 0 );
}

sub testing_driver {
    return 'File';
}

sub new_cache {
    my $self = shift;

    return CHI->new(
        {
            driver       => $self->testing_driver(),
            root_dir     => $root_dir,
            on_set_error => 'die',
            @_
        }
    );
}

sub test_creation_and_deletion : Test(10) {
    my $self = shift;

    my $cache = $self->new_cache();
    is( $cache->depth, 2 );

    my ( $key, $value ) = kvpair();
    my ($cache_file) = $cache->path_to_key($key);
    my $namespace_dir = $cache->path_to_namespace();
    ok( !-f $cache_file, "cache file '$cache_file' does not exist before set" );

    $cache->set( $key, $value, 0 );
    ok( !defined $cache->get($key) );
    ok( -f $cache_file,    "cache file '$cache_file' exists after set" );
    ok( -d $namespace_dir, "namespace dir '$namespace_dir' exists after set" );
    is( ( stat $cache_file )[2] & 07777, 0664, "'$cache_file' has mode 0664" );
    is( ( stat $namespace_dir )[2] & 07777,
        0775, "'$namespace_dir' has mode 0775" );

    $cache->remove($key);
    ok( !-f $cache_file,
        "cache file '$cache_file' does not exist after remove" );
    ok( -d $namespace_dir,
        "namespace dir '$namespace_dir' exists after remove" );

    $cache->clear();
    ok( !-d $namespace_dir,
        "namespace dir '$namespace_dir' does not exist after clear" );
}

1;
