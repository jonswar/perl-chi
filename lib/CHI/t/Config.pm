package CHI::t::Config;
use CHI::Util qw(dump_one_line);
use CHI::Test;
use File::Temp qw(tempdir);
use strict;
use warnings;
use base qw(CHI::Test::Class);

my $root_dir = tempdir( 'CHI-t-Config-XXXX', TMPDIR => 1, CLEANUP => 1 );

my %config = (
    storage => {
        memory => { driver => 'Memory', global   => 1 },
        file   => { driver => 'File',   root_dir => $root_dir },
    },
    namespace => {
        'Foo' => { storage => 'file' },
        'Bar' => { storage => 'file', depth => 3 },
    },
    defaults => { storage => 'memory' },
);

{
    package My::CHI;
    use base qw(CHI);
    My::CHI->config( {%config} );
}

{
    package Other::CHI;
    use base qw(CHI);
    My::CHI->config( { %config, memoize_cache_objects => 1 } );
}

sub _create {
    my ( $params, $checks ) = @_;

    my $desc  = dump_one_line($params);
    my $cache = My::CHI->new(%$params);
    while ( my ( $key, $value ) = each(%$checks) ) {
        is( $cache->$key, $value, "$key == $value ($desc)" );
    }
}

sub test_memoize : Tests {
    my $cache1 = My::CHI->new( namespace => 'Foo' );
    my $cache2 = My::CHI->new( namespace => 'Foo' );
    is( $cache1, $cache2, "same - namespace Foo" );

    my $cache3 = My::CHI->new( namespace => 'Bar', depth => 4 );
    my $cache4 = My::CHI->new( namespace => 'Bar', depth => 4 );
    isnt( $cache3, $cache4, "different - namespace Bar" );

    My::CHI->clear_memoized_cache_objects();
    my $cache5 = My::CHI->new( namespace => 'Foo' );
    my $cache6 = My::CHI->new( namespace => 'Foo' );
    is( $cache5, $cache6, "same - namespace Foo" );
    isnt( $cache1, $cache3, "different - post-clear" );
}

sub test_config : Tests {
    my $self = shift;

    _create(
        { namespace => 'Foo' },
        {
            namespace         => 'Foo',
            storage           => 'file',
            short_driver_name => 'File',
            root_dir          => $root_dir,
            depth             => 2
        },
    );
    _create(
        { namespace => 'Bar' },
        {
            namespace         => 'Bar',
            storage           => 'file',
            short_driver_name => 'File',
            root_dir          => $root_dir,
            depth             => 3
        }
    );
    _create(
        { namespace => 'Foo', depth => 4 },
        {
            namespace         => 'Foo',
            storage           => 'file',
            short_driver_name => 'File',
            root_dir          => $root_dir,
            depth             => 4
        }
    );
    _create(
        { namespace => 'Bar', depth => 4 },
        {
            namespace         => 'Bar',
            storage           => 'file',
            short_driver_name => 'File',
            root_dir          => $root_dir,
            depth             => 4
        }
    );
}

1;
