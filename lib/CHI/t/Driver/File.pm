package CHI::t::Driver::File;
use strict;
use warnings;
use CHI::Test;
use CHI::Test::Util qw(random_string);
use CHI::Util qw(fast_catdir unique_id);
use File::Basename;
use File::Path;
use File::Temp qw(tempdir);
use base qw(CHI::t::Driver);

my $root_dir;

sub new_cache_options {
    my $self = shift;

    $root_dir ||= tempdir( "chi-driver-file-XXXX", TMPDIR => 1, CLEANUP => 1 );
    return ( $self->SUPER::new_cache_options(), root_dir => $root_dir );
}

{
    package CHI::t::Driver::File::NoTempDriver;
    use Moose;
    extends 'CHI::Driver::File';
    __PACKAGE__->meta->make_immutable;

    sub generate_temporary_filename {
        my ( $self, $dir, $file ) = @_;
        return undef;
    }
}

{
    package CHI::t::Driver::File::BadTempDriver;
    use Moose;
    extends 'CHI::Driver::File';
    __PACKAGE__->meta->make_immutable;

    sub generate_temporary_filename {
        my ( $self, $dir, $file ) = @_;
        return "/dir/does/not/exist/$file";
    }
}

# Test that we can override how temporary files are generated
#
sub test_generate_temporary_filename : Tests {
    my $self = shift;

    $self->{cache} =
      $self->new_cache( driver_class => 'CHI::t::Driver::File::NoTempDriver' );
    $self->test_simple();
    $self->{cache} =
      $self->new_cache( driver_class => 'CHI::t::Driver::File::BadTempDriver' );
    throws_ok { $self->test_simple() } qr/error during cache set/;
}

sub test_default_depth : Tests {
    my $self = shift;

    my $cache = $self->new_cache();
    is( $cache->depth, 2 );
}

sub test_creation_and_deletion : Tests {
    my $self = shift;

    my $cache = $self->new_cache();

    my ( $key, $value ) = $self->kvpair();
    my $cache_file    = $cache->path_to_key($key);
    my $namespace_dir = $cache->path_to_namespace();
    ok( !-f $cache_file, "cache file '$cache_file' does not exist before set" );

    $cache->set( $key, $value, 0 );
    ok( !defined $cache->get($key) );
    ok( -f $cache_file,    "cache file '$cache_file' exists after set" );
    ok( -d $namespace_dir, "namespace dir '$namespace_dir' exists after set" );

    $cache->remove($key);
    ok( !-f $cache_file,
        "cache file '$cache_file' does not exist after remove" );
    ok( -d $namespace_dir,
        "namespace dir '$namespace_dir' exists after remove" );

    $cache->clear();
    ok( !-d $namespace_dir,
        "namespace dir '$namespace_dir' does not exist after clear" );
}

sub test_root_dir_does_not_exist : Tests {
    my $self = shift;

    my $parent_dir =
      tempdir( "chi-driver-file-XXXX", TMPDIR => 1, CLEANUP => 1 );
    my $non_existent_root = fast_catdir( $parent_dir, unique_id() );
    ok( !-d $non_existent_root, "$non_existent_root does not exist" );
    my $cache = $self->new_cache( root_dir => $non_existent_root );
    ok( !defined( $cache->get('foo') ), 'miss' );
    $cache->set( 'foo', 5 );
    is( $cache->get('foo'), 5, 'hit' );
    ok( -d $non_existent_root, "$non_existent_root exists after set" );
}

sub test_ignore_bad_namespaces : Tests {
    my $self  = shift;
    my $cache = $self->new_cleared_cache(
        root_dir => tempdir( "chi-driver-file-XXXX", TMPDIR => 1, CLEANUP => 1 )
    );

    foreach my $dir ( ".etc", "+2eetd", 'a@b', 'a+40c', "plain" ) {
        mkpath( join( "/", $cache->root_dir, $dir ) );
    }
    cmp_set(
        [ $cache->get_namespaces ],
        [ '.etd', 'a@c', 'plain' ],
        'only valid dirs shown as namespaces'
    );
}

sub test_default_discard : Tests {
    my $self = shift;
    my $cache = $self->new_cleared_cache( is_size_aware => 1 );
    is( $cache->discard_policy, 'arbitrary' );
}

1;
