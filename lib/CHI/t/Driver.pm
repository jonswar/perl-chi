package CHI::t::Driver;
use CHI::Test;
use strict;
use warnings;
use base qw(CHI::Test::Class);

my ( $cache, $cache_class );

sub setup : Test(setup) {
    my $self = shift;

    $cache = $self->new_cache();
    $cache->clear();
    $cache_class = ref($cache);
}

sub testing_driver {
    my $self  = shift;
    my $class = ref($self);

    # By default, take the last part of the classname and use it as driver
    my $driver = ( split( '::', $class ) )[-1];
    return $driver;
}

sub new_cache {
    my $self = shift;

    return CHI->new( $self->new_cache_options(), @_ );
}

sub new_cache_options {
    my $self = shift;

    return ( driver => $self->testing_driver(), on_set_error => 'die' );
}

# Some standard keys and values
my @mixed_chars = ( 32 .. 48, 57 .. 65, 90 .. 97, 122 .. 126 );
my %keys = (
    'space'    => ' ',
    'char'     => 'a',
    'zero'     => 0,
    'one'      => 1,
    'medium'   => 'medium',
    'mixed'    => join( "", map { chr($_) } @mixed_chars ),
    'large'    => scalar( 'ab' x 256 ),
    'arrayref' => 'arrayref',
    'hashref'  => 'hashref',

    # These generate 'Wide character in print' warnings when logging about the gets/sets...
    # not sure how to handle this...
    #     'utf8_partial' => "abc\x{263A}def",
    #     'utf8_all'     => "\x{263A}\x{263B}\x{263C}",

    # What should be done for empty key?
    #     'empty'        => '',

    # TODO: We should test passing an actual arrayref or hashref as a key - not sure what
    # expected behavior is
);

my @keynames = keys(%keys);
my %values = map { $_, scalar( reverse( $keys{$_} ) ) } @keynames;
$values{arrayref} = [ 1, 2 ];
$values{hashref} = { foo => 'bar' };

# my $onlykey = 'mixed';
# %keys = ($onlykey => $keys{$onlykey});
# %values = ($onlykey => $values{$onlykey});
# @keynames = keys(%keys);

sub set_some_keys {
    my ($c) = @_;

    foreach my $keyname (@keynames) {
        $c->set( $keys{$keyname}, $values{$keyname} );
    }
}

sub test_simple : Test(1) {
    my $self = shift;

    # A comment.
    $cache->set( $keys{medium}, $values{medium} );
    is( $cache->get( $keys{medium} ), $values{medium} );
}

sub test_key_types : Test(64) {
    my $self = shift;

    my @keys_set;
    my $check_keys_set = sub {
        my $desc = shift;
        cmp_set( $cache->get_keys, \@keys_set, "checking keys $desc" );
    };

    $check_keys_set->("before sets");
    foreach my $keyname (@keynames) {
        my $key   = $keys{$keyname};
        my $value = $values{$keyname};
        ok( !defined $cache->get($key), "miss for key '$keyname'" );
        is( $cache->set( $key, $value ), $value, "set for key '$keyname'" );
        push( @keys_set, $key );
        $check_keys_set->("after set of key '$keyname'");
        cmp_deeply( $cache->get($key), $value, "hit for key '$keyname'" );
    }

    foreach my $keyname ( reverse @keynames ) {
        my $key = $keys{$keyname};
        $cache->remove($key);
        ok( !defined $cache->get($key),
            "miss after remove for key '$keyname'" );
        pop(@keys_set);
        cmp_set( $cache->get_keys, \@keys_set,
            "get_keys = " . join( ", ", @keys_set ) );
        $check_keys_set->("after removal of key '$keyname'");
    }
}

sub test_deep_copy : Test(8) {
    my $self = shift;

    set_some_keys($cache);
    foreach my $keyname qw(arrayref hashref) {
        my $key   = $keys{$keyname};
        my $value = $values{$keyname};
        cmp_deeply( $cache->get($key), $value,
            "get($key) returns original data structure" );
        cmp_deeply( $cache->get($key), $cache->get($key),
            "multiple get($key) return same data structure" );
        isnt( $cache->get($key), $value,
            "get($key) does not return original reference" );
        isnt( $cache->get($key), $cache->get($key),
            "multiple get($key) do not return same reference" );
    }
}

sub test_expire : Test(50) {
    my $self = shift;

    # Expires immediately
    my $test_expires_immediately = sub {
        my ($set_option) = @_;
        my ( $key, $value ) = kvpair();
        my $desc = dump_one_line($set_option);
        is( $cache->set( $key, $value, $set_option ), $value, "set ($desc)" );
        is_between(
            $cache->get_expires_at($key),
            time() - 2,
            time(), "expires_at ($desc)"
        );
        ok( $cache->get_object($key)->is_expired(), "is_expired ($desc)" );
        ok( !defined $cache->get($key), "immediate miss ($desc)" );
    };
    $test_expires_immediately->(0);
    $test_expires_immediately->(-1);
    $test_expires_immediately->("0 seconds");
    $test_expires_immediately->("0 hours");
    $test_expires_immediately->("-1 seconds");
    $test_expires_immediately->( { expires_in => "0 seconds" } );
    $test_expires_immediately->( { expires_at => time - 1 } );

    # Expires shortly
    my $test_expires_shortly = sub {
        my ($set_option) = @_;
        my ( $key, $value ) = kvpair();
        my $desc = "set_option = " . dump_one_line($set_option);
        is( $cache->set( $key, $value, $set_option ), $value, "set ($desc)" );
        is( $cache->get($key), $value, "hit ($desc)" );
        is_between(
            $cache->get_expires_at($key),
            time() + 1,
            time() + 3,
            "expires_at ($desc)"
        );
        ok( $cache->is_valid($key), "valid ($desc)" );
        sleep(2);
        ok( !defined $cache->get($key), "miss after 2 seconds ($desc)" );
        ok( !$cache->is_valid($key), "invalid ($desc)" );
    };
    $test_expires_shortly->("2 seconds");
    $test_expires_shortly->( { expires_at => time + 2 } );

    # Expires later
    my $test_expires_later = sub {
        my ($set_option) = @_;
        my ( $key, $value ) = kvpair();
        my $desc = "set_option = " . dump_one_line($set_option);
        is( $cache->set( $key, $value, $set_option ), $value, "set ($desc)" );
        is( $cache->get($key), $value, "hit ($desc)" );
        is_between(
            $cache->get_expires_at($key),
            time() + 3599,
            time() + 3601,
            "expires_at ($desc)"
        );
    };
    $test_expires_later->(3600);
    $test_expires_later->("1 hour");
    $test_expires_later->( { expires_at => time + 3600 } );

    # Expires never (will fail in 2037)
    my ( $key, $value ) = kvpair();
    $cache->set( $key, $value );
    ok(
        $cache->get_expires_at($key) >
          time + Time::Duration::Parse::parse_duration('1 year'),
        "expires never"
    );
}

sub test_not_in_cache : Test(3) {
    ok( !defined $cache->get_object('not in cache') );
    ok( !defined $cache->get_expires_at('not in cache') );
    ok( !$cache->is_valid('not in cache') );
}

sub test_serialize : Test(9) {
    my $self = shift;

    set_some_keys($cache);
    foreach my $keyname (@keynames) {
        my $expect_serialized =
          ( $keyname eq 'arrayref' || $keyname eq 'hashref' ) ? 1 : 0;
        is( $cache->get_object( $keys{$keyname} )->_is_serialized(),
            $expect_serialized,
            "is_serialized = $expect_serialized ($keyname)" );
    }
}

sub test_namespaces : Test(6) {
    my $self = shift;

    my $cache0 =
      do { package Foo::Bar; CHI->new( driver => $self->testing_driver ) };
    is( $cache0->namespace, 'Foo::Bar', 'namespace defaults to package' );

    my ( $ns1, $ns2, $ns3 ) = ( 'ns1', 'ns2', 'ns3' );
    my ( $cache1, $cache1a, $cache2, $cache3 ) =
      map { $self->new_cache( namespace => $_ ) } ( $ns1, $ns1, $ns2, $ns3 );
    cmp_deeply(
        [ map { $_->namespace } ( $cache1, $cache1a, $cache2, $cache3 ) ],
        [ $ns1, $ns1, $ns2, $ns3 ],
        'cache->namespace()'
    );
    set_some_keys($cache1);
    cmp_deeply(
        $cache1->dump_as_hash(),
        $cache1a->dump_as_hash(),
        'cache1 and cache1a are same cache'
    );
    ok( !( @{ $cache2->get_keys() } ),
        'cache2 empty after setting keys in cache1' );
    $cache3->set( $keys{medium}, 'different' );
    is( $cache1->get('medium'), $values{medium}, 'cache1{medium} = medium' );
    is( $cache3->get('medium'), 'different', 'cache1{medium} = different' );

    # Have to figure out proper behavior of get_namespaces - whether it automatically includes new or now-empty namespaces
    # cmp_set($cache1->get_namespaces(), [$cache->namespace(), $ns1, $ns2, $ns3], "get_namespaces");
}

sub test_persist : Test(1) {
    my $self = shift;

    my $hash;
    {
        my $cache1 = $self->new_cache();
        set_some_keys($cache1);
        $hash = $cache1->dump_as_hash();
    }
    my $cache2 = $self->new_cache();
    cmp_deeply( $hash, $cache2->dump_as_hash(),
        'cache persisted between cache object creations' );
}

sub test_multi : Test(8) {
    my $self = shift;

    my @ordered_keys       = sort keys %keys;
    my %ordered_key_values = map { ( $_, $values{$_} ) } @ordered_keys;
    my @ordered_values     = map { $ordered_key_values{$_} } @ordered_keys;

    cmp_deeply( $cache->get_multi_arrayref( ['foo'] ),
        [undef], "get_multi_arrayref before set" );
    $cache->set_multi( \%ordered_key_values );
    cmp_deeply( $cache->get_multi_arrayref( \@ordered_keys ),
        \@ordered_values, "get_multi_arrayref" );
    cmp_deeply( $cache->get( $ordered_keys[0] ),
        $ordered_values[0], "get one after set_multi" );
    cmp_deeply(
        $cache->get_multi_arrayref( [ reverse @ordered_keys ] ),
        [ reverse @ordered_values ],
        "get_multi_arrayref"
    );
    cmp_deeply( $cache->get_multi_hashref( \@ordered_keys ),
        \%ordered_key_values, "get_multi_hashref" );
    cmp_set( $cache->get_keys, \@ordered_keys, "get_keys after set_multi" );
    $cache->remove_multi( \@ordered_keys );
    cmp_deeply(
        $cache->get_multi_arrayref( \@ordered_keys ),
        [ (undef) x scalar(@ordered_values) ],
        "get_multi_arrayref after remove_multi"
    );
    cmp_set( $cache->get_keys, [], "get_keys after remove_multi" );
}

sub test_multi_no_keys : Test(4) {
    my $self = shift;

    cmp_deeply( $cache->get_multi_arrayref( [] ),
        [], "get_multi_arrayref (no args)" );
    cmp_deeply( $cache->get_multi_hashref( [] ),
        {}, "get_multi_hashref (no args)" );
    lives_ok { $cache->set_multi( {} ) } "set_multi (no args)";
    lives_ok { $cache->remove_multi( [] ) } "remove_multi (no args)";
}

sub test_clear : Test(10) {
    my $self = shift;

    set_some_keys($cache);
    $cache->clear();
    cmp_deeply( $cache->get_keys, [], "get_keys after clear" );
    while ( my ( $keyname, $key ) = each(%keys) ) {
        ok( !defined $cache->get($key),
            "key '$keyname' no longer defined after clear" );
    }
}

1;
