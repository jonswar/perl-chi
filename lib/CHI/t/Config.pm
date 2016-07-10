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
        'Foo' => { label => 'FooCache', storage => 'file' },
        'Bar' => { label => 'BarCache', storage => 'file', depth => 3 },
        'Default' => { label => 'JohnnyCache' },
    },
    defaults => { storage => 'memory' },
);

{
    package My::CHI;

    use base qw(CHI);
    My::CHI->config( {%config} );
}

{
    package My::CHI::Subclass;

    use base qw(My::CHI);
}

{
    package My::CHI::Memo;

    use base qw(CHI);
    My::CHI::Memo->config( { %config, memoize_cache_objects => 1 } );
}

{
    package My::CHI::Subcaching;

    use base qw(CHI);
    My::CHI::Subcaching->config(
        {
            %config,
            defaults => {
                storage  => 'file',
                l1_cache => {
                    storage => 'memory',
                },
            },
        }
    );
}

sub _create {
    my ( $params, $checks ) = @_;

    my $desc = dump_one_line($params);
    foreach my $class (qw(My::CHI My::CHI::Subclass)) {
        my $cache = $class->new(%$params);
        while ( my ( $key, $value ) = each(%$checks) ) {
            is( $cache->$key, $value, "$key == $value ($desc)" );
        }
    }
}

sub test_config : Tests {
    my $self = shift;

    _create(
        {},
        {
            namespace         => 'Default',
            label             => 'JohnnyCache',
            storage           => 'memory',
            short_driver_name => 'Memory',
        }
    );
    _create(
        { namespace => 'Foo' },
        {
            namespace         => 'Foo',
            label             => 'FooCache',
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
            label             => 'BarCache',
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
            label             => 'FooCache',
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
            label             => 'BarCache',
            storage           => 'file',
            short_driver_name => 'File',
            root_dir          => $root_dir,
            depth             => 4
        }
    );
    _create(
        { no_defaults_for => [qw(namespace)] },
        {
            namespace         => 'Default',
            label             => 'Memory',
            storage           => 'memory',
            short_driver_name => 'Memory',
        }
    );
    _create(
        { namespace => 'Foo', no_defaults_for => [qw(label)] },
        {
            namespace         => 'Foo',
            label             => 'File',
            storage           => 'file',
            short_driver_name => 'File',
        }
    );

    my %new_config = %config;
    $new_config{namespace}->{'Bar'}->{depth} = 5;
    My::CHI->config( {%new_config} );
    _create(
        { namespace => 'Bar' },
        {
            namespace         => 'Bar',
            label             => 'BarCache',
            storage           => 'file',
            short_driver_name => 'File',
            root_dir          => $root_dir,
            depth             => 5
        }
    );
}

sub test_memoize : Tests {
    my $cache1 = My::CHI::Memo->new( namespace => 'Foo' );
    my $cache2 = My::CHI::Memo->new( namespace => 'Foo' );
    is( $cache1, $cache2, "same - namespace Foo" );

    my $cache3 = My::CHI::Memo->new( namespace => 'Bar', depth => 4 );
    my $cache4 = My::CHI::Memo->new( namespace => 'Bar', depth => 4 );
    isnt( $cache3, $cache4, "different - namespace Bar" );

    My::CHI::Memo->clear_memoized_cache_objects();
    my $cache5 = My::CHI::Memo->new( namespace => 'Foo' );
    my $cache6 = My::CHI::Memo->new( namespace => 'Foo' );
    is( $cache5, $cache6, "same - namespace Foo" );
    isnt( $cache1, $cache3, "different - post-clear" );

    my $cache7 = My::CHI->new( namespace => 'Foo' );
    my $cache8 = My::CHI->new( namespace => 'Foo' );
    isnt( $cache7, $cache8, "different - namespace Foo - no memoization" );
}

sub test_subcache_constructor_args : Tests {
    my $subcaching1 = My::CHI::Subcaching->new;

    is( $subcaching1->l1_cache->can('l1_cache'),
        undef, 'l1_cache not automatically built with nested l1_cache' );

    my $subcaching2 = My::CHI::Subcaching->new(
        l1_cache => {
            storage  => 'memory',
            l1_cache => {
                driver => '+CHI::Driver::Null',
            },
        },
    );

    is(
        $subcaching2->l1_cache->l1_cache->driver_class,
        'CHI::Driver::Null',
        'driver of nested subcache not overriden by default settings',
    );
}

1;
