package CHI::t::Driver::File;
use strict;
use warnings;
use CHI::Test;
use CHI::Test::Util qw(random_string);
use CHI::Util qw(fast_catdir unique_id);
use File::Basename;
use File::Temp qw(tempdir);
use base qw(CHI::t::Driver);

my $root_dir;

sub new_cache_options {
    my $self = shift;

    $root_dir ||= tempdir( "chi-driver-file-XXXX", TMPDIR => 1, CLEANUP => 1 );
    return ( $self->SUPER::new_cache_options(), root_dir => $root_dir );
}

sub set_standard_keys_and_values {
    my ($self) = @_;

    my ( $keys, $values ) = $self->SUPER::set_standard_keys_and_values();

    # keys have max length of 255 or so
    # but on windows xp, the full pathname is limited to 255 chars as well
    $keys->{'large'} = scalar( 'ab' x ( $^O eq 'MSWin32' ? 64 : 120 ) );

    return ( $keys, $values );
}

sub test_path_to_key : Test(5) {
    my ($self) = @_;

    my $key;
    my $cache = $self->new_cache( namespace => random_string(10) );
    my $log = CHI::Test::Logger->new();
    CHI->logger($log);

    $key = "\$20.00 plus 5% = \$25.00";
    my $file = basename( $cache->path_to_key($key) );
    is(
        $file,
        "+2420+2e00+20plus+205+25+20=+20+2425+2e00.dat",
        "path_to_key for key with mixed chars"
    );

    # Should escape to over 255 chars
    $key = "!@#" x 100;
    $log->clear();
    ok(
        !defined( $cache->path_to_key($key) ),
        "path_to_key undefined for too-long key"
    );
    my $namespace = $cache->namespace();
    $log->contains_ok(
        qr/escaped key '.+' in namespace '\Q$namespace\E' is over \d+ chars; cannot cache/
    );

    # Full path is too long
    my $max_path_length = ( $^O eq 'MSWin32' ? 254 : 1023 );
    my $long_root_dir =
      fast_catdir( $root_dir, scalar( "a" x ( $max_path_length - 60 ) ) );
    $cache = $self->new_cache(
        root_dir  => $long_root_dir,
        namespace => random_string(10)
    );
    $key = 'abcd' x 25;
    $log->clear();
    ok(
        !defined( $cache->path_to_key($key) ),
        "path_to_key undefined for too-long key"
    );
    $namespace = $cache->namespace();
    $log->contains_ok(
        qr/full escaped path for key '.+' in namespace '\Q$namespace\E' is over \d+ chars; cannot cache/
    );
}

{

    package CHI::t::Driver::File::NoTempDriver;
    use base qw(CHI::Driver::File);

    sub generate_temporary_filename {
        my ( $self, $dir, $file ) = @_;
        return undef;
    }
}

{

    package CHI::t::Driver::File::BadTempDriver;
    use base qw(CHI::Driver::File);

    sub generate_temporary_filename {
        my ( $self, $dir, $file ) = @_;
        return "/dir/does/not/exist/$file";
    }
}

# Test that we can override how temporary files are generated
#
sub test_generate_temporary_filename : Tests(2) {
    my $self = shift;

    $self->{cache} =
      $self->new_cache( driver_class => 'CHI::t::Driver::File::NoTempDriver' );
    $self->test_simple();
    $self->{cache} =
      $self->new_cache( driver_class => 'CHI::t::Driver::File::BadTempDriver' );
    throws_ok { $self->test_simple() } qr/error during cache set/;
}

sub test_default_depth : Test(1) {
    my $self = shift;

    my $cache = $self->new_cache();
    is( $cache->depth, 2 );
}

sub test_creation_and_deletion : Test(7) {
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

sub test_root_dir_does_not_exist : Test(4) {
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

1;

