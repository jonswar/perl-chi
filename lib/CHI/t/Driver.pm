package CHI::t::Driver;
use strict;
use warnings;
use CHI::Test;
use CHI::Test::Logger;
use CHI::Test::Util qw(cmp_bool is_between random_string skip_until);
use CHI::Util qw(dump_one_line dp);
use File::Temp qw(tempdir);
use Module::Load::Conditional qw(can_load check_install);
use Scalar::Util qw(weaken);
use base qw(CHI::Test::Class);

# Flags indicating what each test driver supports
sub supports_clear          { 1 }
sub supports_get_namespaces { 1 }

sub standard_keys_and_values : Test(startup) {
    my ($self) = @_;

    my ( $keys_ref, $values_ref ) = $self->set_standard_keys_and_values();
    $self->{keys}      = $keys_ref;
    $self->{values}    = $values_ref;
    $self->{keynames}  = [ keys( %{$keys_ref} ) ];
    $self->{key_count} = scalar( @{ $self->{keynames} } );
}

sub kvpair {
    my $self = shift;
    my $count = shift || 1;

    return map {
        (
            $self->{keys}->{medium} .   ( $_ == 1 ? '' : $_ ),
            $self->{values}->{medium} . ( $_ == 1 ? '' : $_ )
          )
    } ( 1 .. $count );
}

sub setup : Test(setup) {
    my $self = shift;

    $self->{cache} = $self->new_cache();
    $self->{cache}->clear() if $self->supports_clear();
}

sub testing_driver_class {
    my $self  = shift;
    my $class = ref($self);

    # By default, take the last part of the classname and use it as driver
    my $driver_class = 'CHI::Driver::' . ( split( '::', $class ) )[-1];
    return $driver_class;
}

sub new_cache {
    my $self = shift;

    return CHI->new( $self->new_cache_options(), @_ );
}

sub new_cache_options {
    my $self = shift;

    return (
        driver_class     => $self->testing_driver_class(),
        expires_variance => 0,
        on_get_error     => 'die',
        on_set_error     => 'die'
    );
}

sub set_standard_keys_and_values {
    my $self = shift;

    my ( %keys, %values );
    my @mixed_chars = ( 32 .. 48, 57 .. 65, 90 .. 97, 122 .. 126 );
    %keys = (
        'space'    => ' ',
        'char'     => 'a',
        'zero'     => 0,
        'one'      => 1,
        'medium'   => 'medium',
        'mixed'    => join( "", map { chr($_) } @mixed_chars ),
        'large'    => scalar( 'ab' x 256 ),
        'arrayref' => 'arrayref',
        'hashref'  => 'hashref',

        # Several problems with trying to handle unicode keys and values.
        # * They generate 'Wide character in print' warnings when logging about the gets/sets
        # * Causes metadata packing to break
        # * Storable won't touch them
        # not sure how to handle these. Maybe there's no way. Even if we automatically
        # encoded all keys and values, what to do about complex values where wide strings
        # might be lurking?
        # 'utf8_partial' => "abc\x{263A}def",
        # 'utf8_all' => "\x{263A}\x{263B}\x{263C}",

        # What should be done for empty key?
        #     'empty'        => '',

        # TODO: We should test passing an actual arrayref or hashref as a key - not sure what
        # expected behavior is
    );

    %values =
      map { ( $_, scalar( reverse( $keys{$_} ) ) ) } keys(%keys);
    $values{arrayref} = [ 1, 2 ];
    $values{hashref} = { foo => 'bar' };

    return ( \%keys, \%values );
}

sub set_some_keys {
    my ( $self, $c ) = @_;

    foreach my $keyname ( @{ $self->{keynames} } ) {
        $c->set( $self->{keys}->{$keyname}, $self->{values}->{$keyname} );
    }
}

sub test_simple : Test(1) {
    my $self  = shift;
    my $cache = $self->{cache};

    $cache->set( $self->{keys}->{medium}, $self->{values}->{medium} );
    is( $cache->get( $self->{keys}->{medium} ), $self->{values}->{medium} );
}

sub test_driver_class : Tests(4) {
    my $self  = shift;
    my $cache = $self->{cache};

    isa_ok( $cache, 'CHI::Driver' );
    isa_ok( $cache, $cache->driver_class );
    isa_ok( $cache, 'CHI::Driver::Wrapper' );
    can_ok( $cache, 'get', 'set', 'remove', 'clear', 'expire' );
}

sub test_key_types : Tests {
    my $self  = shift;
    my $cache = $self->{cache};
    $self->num_tests( $self->{key_count} * 6 + 1 );

    my @keys_set;
    my $check_keys_set = sub {
        my $desc = shift;
        cmp_set( [ $cache->get_keys ], \@keys_set, "checking keys $desc" );
    };

    $check_keys_set->("before sets");
    foreach my $keyname ( @{ $self->{keynames} } ) {
        my $key   = $self->{keys}->{$keyname};
        my $value = $self->{values}->{$keyname};
        ok( !defined $cache->get($key), "miss for key '$keyname'" );
        is( $cache->set( $key, $value ), $value, "set for key '$keyname'" );
        push( @keys_set, $key );
        $check_keys_set->("after set of key '$keyname'");
        cmp_deeply( $cache->get($key), $value, "hit for key '$keyname'" );
    }

    foreach my $keyname ( reverse @{ $self->{keynames} } ) {
        my $key = $self->{keys}->{$keyname};
        $cache->remove($key);
        ok( !defined $cache->get($key),
            "miss after remove for key '$keyname'" );
        pop(@keys_set);
        $check_keys_set->("after removal of key '$keyname'");
    }
}

sub test_deep_copy : Test(8) {
    my $self  = shift;
    my $cache = $self->{cache};

    $self->set_some_keys($cache);
    foreach my $keyname qw(arrayref hashref) {
        my $key   = $self->{keys}->{$keyname};
        my $value = $self->{values}->{$keyname};
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

sub test_expires_immediately : Test(32) {
    my $self  = shift;
    my $cache = $self->{cache};

    # Expires immediately
    my $test_expires_immediately = sub {
        my ($set_option) = @_;
        my ( $key, $value ) = $self->kvpair();
        my $desc = dump_one_line($set_option);
        is( $cache->set( $key, $value, $set_option ), $value, "set ($desc)" );
        is_between(
            $cache->get_expires_at($key),
            time() - 2,
            time(), "expires_at ($desc)"
        );
        ok( $cache->exists_and_is_expired($key), "is_expired ($desc)" );
        ok( !defined $cache->get($key),          "immediate miss ($desc)" );
    };
    $test_expires_immediately->(0);
    $test_expires_immediately->(-1);
    $test_expires_immediately->("0 seconds");
    $test_expires_immediately->("0 hours");
    $test_expires_immediately->("-1 seconds");
    $test_expires_immediately->( { expires_in => "0 seconds" } );
    $test_expires_immediately->( { expires_at => time - 1 } );
    $test_expires_immediately->("now");
}

sub test_expires_shortly : Test(18) {
    my $self  = shift;
    my $cache = $self->{cache};

    # Expires shortly (real time)
    my $test_expires_shortly = sub {
        my ($set_option) = @_;
        my ( $key, $value ) = $self->kvpair();
        my $desc       = "set_option = " . dump_one_line($set_option);
        my $start_time = time();
        is( $cache->set( $key, $value, $set_option ), $value, "set ($desc)" );
        is( $cache->get($key), $value, "hit ($desc)" );
        is_between(
            $cache->get_expires_at($key),
            $start_time + 1,
            $start_time + 5,
            "expires_at ($desc)"
        );
        ok( !$cache->exists_and_is_expired($key), "not expired ($desc)" );
        ok( $cache->is_valid($key),               "valid ($desc)" );

        # Only bother sleeping and expiring for one of the variants
        if ( $set_option eq "2 seconds" ) {
            sleep(2);
            ok( !defined $cache->get($key), "miss after 2 seconds ($desc)" );
            ok( $cache->exists_and_is_expired($key), "is_expired ($desc)" );
            ok( !$cache->is_valid($key),             "invalid ($desc)" );
        }
    };
    $test_expires_shortly->(2);
    $test_expires_shortly->("2 seconds");
    $test_expires_shortly->( { expires_at => time + 2 } );
}

sub test_expires_later : Test(30) {
    my $self  = shift;
    my $cache = $self->{cache};

    # Expires later (test time)
    my $test_expires_later = sub {
        my ($set_option) = @_;
        my ( $key, $value ) = $self->kvpair();
        my $desc = "set_option = " . dump_one_line($set_option);
        is( $cache->set( $key, $value, $set_option ), $value, "set ($desc)" );
        is( $cache->get($key), $value, "hit ($desc)" );
        my $start_time = time();
        is_between(
            $cache->get_expires_at($key),
            $start_time + 3599,
            $start_time + 3601,
            "expires_at ($desc)"
        );
        ok( !$cache->exists_and_is_expired($key), "not expired ($desc)" );
        ok( $cache->is_valid($key),               "valid ($desc)" );
        local $CHI::Driver::Test_Time = $start_time + 3598;
        ok( !$cache->exists_and_is_expired($key), "not expired ($desc)" );
        ok( $cache->is_valid($key),               "valid ($desc)" );
        local $CHI::Driver::Test_Time = $start_time + 3602;
        ok( !defined $cache->get($key),          "miss after 1 hour ($desc)" );
        ok( $cache->exists_and_is_expired($key), "is_expired ($desc)" );
        ok( !$cache->is_valid($key),             "invalid ($desc)" );
    };
    $test_expires_later->(3600);
    $test_expires_later->("1 hour");
    $test_expires_later->( { expires_at => time + 3600 } );
}

sub test_expires_never : Test(6) {
    my $self  = shift;
    my $cache = $self->{cache};

    # Expires never (will fail in 2037)
    my ( $key, $value ) = $self->kvpair();
    my $test_expires_never = sub {
        my (@set_options) = @_;
        $cache->set( $key, $value, @set_options );
        ok(
            $cache->get_expires_at($key) >
              time + Time::Duration::Parse::parse_duration('1 year'),
            "expires never"
        );
        ok( !$cache->exists_and_is_expired($key), "not expired" );
        ok( $cache->is_valid($key),               "valid" );
    };
    $test_expires_never->();
    $test_expires_never->('never');
}

sub test_expires_defaults : Test(4) {
    my $self = shift;

    my $start_time = time();
    local $CHI::Driver::Test_Time = $start_time;
    my $cache;

    my $set_and_confirm_expires_at = sub {
        my ( $expected_expires_at, $desc ) = @_;
        my ( $key, $value ) = ( random_string(10), random_string(10) );
        $cache->set( $key, $value );
        is( $cache->get_expires_at($key), $expected_expires_at, $desc );
    };

    $cache = $self->new_cache( expires_in => 10 );
    $set_and_confirm_expires_at->(
        $start_time + 10,
        "after expires_in constructor option"
    );
    $cache->expires_in(20);
    $set_and_confirm_expires_at->( $start_time + 20,
        "after expires_in method" );

    $cache = $self->new_cache( expires_at => $start_time + 30 );
    $set_and_confirm_expires_at->(
        $start_time + 30,
        "after expires_at constructor option"
    );
    $cache->expires_at( $start_time + 40 );
    $set_and_confirm_expires_at->( $start_time + 40,
        "after expires_at method" );
}

sub test_expires_manually : Test(3) {
    my $self  = shift;
    my $cache = $self->{cache};

    my ( $key, $value ) = $self->kvpair();
    my $desc = "expires manually";
    $cache->set( $key, $value );
    is( $cache->get($key), $value, "hit ($desc)" );
    $cache->expire($key);
    ok( !defined $cache->get($key), "miss after expire ($desc)" );
    ok( !$cache->is_valid($key),    "invalid after expire ($desc)" );
}

sub test_expires_conditionally : Test(22) {
    my $self  = shift;
    my $cache = $self->{cache};

    # Expires conditionally
    my $test_expires_conditionally = sub {
        my ( $code, $cond_desc, $expect_expire ) = @_;
        foreach my $separate_call ( 0, 1 ) {
            my ( $key, $value ) = $self->kvpair();
            my $desc =
              "expires conditionally ($cond_desc, separate_call=$separate_call)";
            $cache->set( $key, $value );
            if ($separate_call) {
                is( $cache->get($key), $value, "hit ($desc)" );
                cmp_bool( $cache->expire_if( $key, $code ),
                    $expect_expire, "expire_if ($desc)" );
            }
            else {
                is(
                    $cache->get( $key, expire_if => $code ),
                    $expect_expire ? undef : $value,
                    "get result ($desc)"
                );
            }
            if ( $expect_expire && $separate_call ) {
                ok( !defined $cache->get($key),
                    "miss after expire_if ($desc)" );
                ok( !$cache->is_valid($key),
                    "invalid after expire_if ($desc)" );
            }
            else {
                is( $cache->get($key), $value, "hit after expire_if ($desc)" );
            }
        }
    };
    my $time = time();
    $test_expires_conditionally->( sub { 1 }, 'true',  1 );
    $test_expires_conditionally->( sub { 0 }, 'false', 0 );
    $test_expires_conditionally->(
        sub { $_[0]->created_at >= $time },
        'created_at >= now', 1
    );
    $test_expires_conditionally->(
        sub { $_[0]->created_at < $time },
        'created_at < now', 0
    );
}

sub test_expires_variance : Test(9) {
    my $self  = shift;
    my $cache = $self->{cache};

    my $start_time = time();
    my $expires_at = $start_time + 10;
    my ( $key, $value ) = $self->kvpair();
    $cache->set( $key, $value,
        { expires_at => $expires_at, expires_variance => 0.5 } );
    is( $cache->get_object($key)->expires_at(),
        $expires_at, "expires_at = $start_time" );
    is(
        $cache->get_object($key)->early_expires_at(),
        $start_time + 5,
        "early_expires_at = $start_time + 5"
    );

    my %expire_count;
    for ( my $time = $start_time + 3 ; $time <= $expires_at + 1 ; $time++ ) {
        local $CHI::Driver::Test_Time = $time;
        for ( my $i = 0 ; $i < 100 ; $i++ ) {
            if ( !defined $cache->get($key) ) {
                $expire_count{$time}++;
            }
        }
    }
    for ( my $time = $start_time + 3 ; $time <= $start_time + 5 ; $time++ ) {
        ok( !$expire_count{$time}, "got no expires at $time" );
    }
    for ( my $time = $start_time + 7 ; $time <= $start_time + 8 ; $time++ ) {
        ok( $expire_count{$time} > 0 && $expire_count{$time} < 100,
            "got some expires at $time" );
    }
    for ( my $time = $expires_at ; $time <= $expires_at + 1 ; $time++ ) {
        ok( $expire_count{$time} == 100, "got all expires at $time" );
    }
}

sub test_not_in_cache : Test(3) {
    my $self  = shift;
    my $cache = $self->{cache};

    ok( !defined $cache->get_object('not in cache') );
    ok( !defined $cache->get_expires_at('not in cache') );
    ok( !$cache->is_valid('not in cache') );
}

sub test_serialize : Tests {
    my $self  = shift;
    my $cache = $self->{cache};
    $self->num_tests( $self->{key_count} );

    $self->set_some_keys($cache);
    foreach my $keyname ( @{ $self->{keynames} } ) {
        my $expect_serialized =
          ( $keyname eq 'arrayref' || $keyname eq 'hashref' ) ? 1 : 0;
        is(
            $cache->get_object( $self->{keys}->{$keyname} )->_is_serialized(),
            $expect_serialized,
            "is_serialized = $expect_serialized ($keyname)"
        );
    }
}

{

    package DummySerializer;
    sub serialize   { }
    sub deserialize { }
}

sub test_serializers : Tests {
    my ($self) = @_;

    return 'Data::Serializer not installed'
      unless can_load( modules => { 'Data::Serializer' => undef } );

    my @modes    = (qw(string hash object));
    my @variants = (qw(Storable Data::Dumper YAML));
    @variants = grep { check_install( module => $_ ) } @variants;
    ok( scalar(@variants), "some variants ok" );

    my $initial_count        = 5;
    my $test_key_types_count = $self->{key_count} * 6 + 1;
    my $test_count           = $initial_count +
      scalar(@variants) * scalar(@modes) * ( 1 + $test_key_types_count );

    my $cache1 = $self->new_cache();
    isa_ok( $cache1->serializer, 'CHI::Serializer::Storable' );
    my $cache2 = $self->new_cache();
    is( $cache1->serializer, $cache2->serializer,
        'same serializer returned from two objects' );

    throws_ok(
        sub {
            $self->new_cache( serializer => [1] );
        },
        qr/Validation failed for 'Serializer'/,
        "invalid serializer"
    );
    lives_ok(
        sub { $self->new_cache( serializer => bless( {}, 'DummySerializer' ) ) }
        ,
        "valid dummy serializer"
    );

    foreach my $mode (@modes) {
        foreach my $variant (@variants) {
            my $serializer_param = (
                  $mode eq 'string' ? $variant
                : $mode eq 'hash' ? { serializer => $variant }
                : Data::Serializer->new( serializer => $variant )
            );
            my $cache = $self->new_cache( serializer => $serializer_param );
            is( $cache->serializer->serializer,
                $variant, "serializer = $variant, mode = $mode" );
            $self->{cache} = $cache;
            $self->test_key_types();
            $self->num_tests($test_count);
        }
    }
}

sub test_namespaces : Test(12) {
    my $self  = shift;
    my $cache = $self->{cache};

    my $cache0 = $self->new_cache();
    is( $cache0->namespace, 'Default', 'namespace defaults to "Default"' );

    my ( $ns1, $ns2, $ns3 ) = ( 'ns1', 'ns2', 'ns3' );
    my ( $cache1, $cache1a, $cache2, $cache3 ) =
      map { $self->new_cache( namespace => $_ ) } ( $ns1, $ns1, $ns2, $ns3 );
    cmp_deeply(
        [ map { $_->namespace } ( $cache1, $cache1a, $cache2, $cache3 ) ],
        [ $ns1, $ns1, $ns2, $ns3 ],
        'cache->namespace()'
    );
    $self->set_some_keys($cache1);
    cmp_deeply(
        $cache1->dump_as_hash(),
        $cache1a->dump_as_hash(),
        'cache1 and cache1a are same cache'
    );
    cmp_deeply( [ $cache2->get_keys() ],
        [], 'cache2 empty after setting keys in cache1' );
    $cache3->set( $self->{keys}->{medium}, 'different' );
    is(
        $cache1->get('medium'),
        $self->{values}->{medium},
        'cache1{medium} = medium'
    );
    is( $cache3->get('medium'), 'different', 'cache1{medium} = different' );

    if ( $self->supports_get_namespaces() ) {

        # get_namespaces may or may not automatically include empty namespaces
        cmp_deeply(
            [ $cache1->get_namespaces() ],
            supersetof( $ns1, $ns3 ),
            "get_namespaces contains $ns1 and $ns3"
        );

        foreach my $c ( $cache0, $cache1, $cache1a, $cache2, $cache3 ) {
            cmp_deeply(
                [ $cache->get_namespaces() ],
                [ $c->get_namespaces() ],
                'get_namespaces the same regardless of which cache asks'
            );
        }
    }
    else {
        throws_ok(
            sub { $cache1->get_namespaces() },
            qr/not supported/,
            "get_namespaces not supported"
        );
      SKIP: { skip "get_namespaces not supported", 5 }
    }
}

sub test_persist : Test(1) {
    my $self  = shift;
    my $cache = $self->{cache};

    my $hash;
    {
        my $cache1 = $self->new_cache();
        $self->set_some_keys($cache1);
        $hash = $cache1->dump_as_hash();
    }
    my $cache2 = $self->new_cache();
    cmp_deeply( $hash, $cache2->dump_as_hash(),
        'cache persisted between cache object creations' );
}

sub test_multi : Test(8) {
    my $self  = shift;
    my $cache = $self->{cache};

    my @ordered_keys = map { $self->{keys}->{$_} } @{ $self->{keynames} };
    my @ordered_values =
      map { $self->{values}->{$_} } @{ $self->{keynames} };
    my %ordered_key_values =
      map { ( $self->{keys}->{$_}, $self->{values}->{$_} ) }
      @{ $self->{keynames} };

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
    cmp_set( [ $cache->get_keys ], \@ordered_keys, "get_keys after set_multi" );

    $cache->remove_multi( \@ordered_keys );
    cmp_deeply(
        $cache->get_multi_arrayref( \@ordered_keys ),
        [ (undef) x scalar(@ordered_values) ],
        "get_multi_arrayref after remove_multi"
    );
    cmp_set( [ $cache->get_keys ], [], "get_keys after remove_multi" );
}

sub test_multi_no_keys : Test(4) {
    my $self  = shift;
    my $cache = $self->{cache};

    cmp_deeply( $cache->get_multi_arrayref( [] ),
        [], "get_multi_arrayref (no args)" );
    cmp_deeply( $cache->get_multi_hashref( [] ),
        {}, "get_multi_hashref (no args)" );
    lives_ok { $cache->set_multi( {} ) } "set_multi (no args)";
    lives_ok { $cache->remove_multi( [] ) } "remove_multi (no args)";
}

sub test_l1_cache : Test(228) {
    my $self   = shift;
    my @keys   = map { "key$_" } ( 0 .. 2 );
    my @values = map { "value$_" } ( 0 .. 2 );
    my ( $cache, $l1_cache );

    my $test_l1_cache = sub {

        is( $l1_cache->subcache_type, "l1_cache" );

        # Get on cache should populate l1 cache
        #
        $cache->set( $keys[0], $values[0] );
        $l1_cache->clear();
        ok( !$l1_cache->get( $keys[0] ), "l1 miss after clear" );
        is( $cache->get( $keys[0] ),
            $values[0], "primary hit after primary set" );
        is( $l1_cache->get( $keys[0] ), $values[0],
            "l1 hit after primary get" );

        # Primary cache should be reading l1 cache first
        #
        $l1_cache->set( $keys[0], $values[1] );
        is( $cache->get( $keys[0] ),
            $values[1], "got new value set explicitly in l1 cache" );
        $l1_cache->remove( $keys[0] );
        is( $cache->get( $keys[0] ), $values[0], "got old value again" );

        $cache->clear();
        ok( !$cache->get( $keys[0] ),    "miss after clear" );
        ok( !$l1_cache->get( $keys[0] ), "miss after clear" );

        # get_multi_* - one from l1 cache, one from primary cache, one miss
        #
        $cache->set( $keys[0], $values[0] );
        $cache->set( $keys[1], $values[0] );
        $l1_cache->remove( $keys[0] );
        $l1_cache->set( $keys[1], $values[1] );
        cmp_deeply(
            $cache->get_multi_arrayref( [ $keys[0], $keys[1], $keys[2] ] ),
            [ $values[0], $values[1], undef ],
            "get_multi_arrayref"
        );
        cmp_deeply(
            [ $cache->get_multi_array( [ $keys[0], $keys[1], $keys[2] ] ) ],
            [ $values[0], $values[1], undef ],
            "get_multi_array"
        );
        cmp_deeply(
            $cache->get_multi_hashref( [ $keys[0], $keys[1], $keys[2] ] ),
            {
                $keys[0] => $values[0],
                $keys[1] => $values[1],
                $keys[2] => undef
            },
            "get_multi_hashref"
        );

        $self->_test_logging_with_l1_cache( $cache, $l1_cache );

        $self->_test_common_subcache_features( $cache, $l1_cache );
    };

    # Test with current cache in primary position...
    #
    $cache = $self->new_cache( l1_cache => { driver => 'Memory' } );
    $l1_cache = $cache->l1_cache;
    isa_ok( $cache,    $self->testing_driver_class );
    isa_ok( $l1_cache, 'CHI::Driver::Memory' );
    $test_l1_cache->();

    # and in l1 position
    #
    $cache = CHI->new(
        driver   => 'Memory',
        l1_cache => { $self->new_cache_options() }
    );
    $l1_cache = $cache->l1_cache;
    isa_ok( $cache,    'CHI::Driver::Memory' );
    isa_ok( $l1_cache, $self->testing_driver_class );
    $test_l1_cache->();
}

sub test_mirror_cache : Test(206) {
    my $self = shift;
    my ( $cache, $mirror_cache );
    my ( $key, $value, $key2, $value2 ) = $self->kvpair(2);

    my $test_mirror_cache = sub {

        is( $mirror_cache->subcache_type, "mirror_cache" );

        # Get on either cache should not populate the other, and should not be able to see
        # mirror keys from regular cache
        #
        $cache->set( $key, $value );
        $mirror_cache->remove($key);
        $cache->get($key);
        ok( !$mirror_cache->get($key), "key not in mirror_cache" );

        $mirror_cache->set( $key2, $value2 );
        ok( !$cache->get($key2), "key2 not in cache" );

        $self->_test_logging_with_mirror_cache( $cache, $mirror_cache );

        $self->_test_common_subcache_features( $cache, $mirror_cache );
    };

    my $file_cache_options = sub {
        my $root_dir =
          tempdir( "chi-test-mirror-cache-XXXX", TMPDIR => 1, CLEANUP => 1 );
        return ( driver => 'File', root_dir => $root_dir, depth => 3 );
    };

    # Test with current cache in primary position...
    #
    $cache = $self->new_cache( mirror_cache => { $file_cache_options->() } );
    $mirror_cache = $cache->mirror_cache;
    isa_ok( $cache,        $self->testing_driver_class );
    isa_ok( $mirror_cache, 'CHI::Driver::File' );
    $test_mirror_cache->();

    # and in mirror position
    #
    $cache =
      CHI->new( $file_cache_options->(),
        mirror_cache => { $self->new_cache_options() } );
    $mirror_cache = $cache->mirror_cache;
    isa_ok( $cache,        'CHI::Driver::File' );
    isa_ok( $mirror_cache, $self->testing_driver_class );
    $test_mirror_cache->();
}

# Run logging tests for a cache with an l1_cache
#
sub _test_logging_with_l1_cache {
    my ( $self, $cache ) = @_;

    $cache->clear();
    my $log = CHI::Test::Logger->new();
    CHI->logger($log);
    my ( $key, $value ) = $self->kvpair();

    my $driver = $cache->short_driver_name;

    my $miss_not_in_cache = 'MISS \(not in cache\)';
    my $miss_expired      = 'MISS \(expired\)';

    my $start_time = time();

    $cache->get($key);
    $log->contains_ok(
        qr/cache get for .* key='$key', cache='$driver': $miss_not_in_cache/);
    $log->contains_ok(
        qr/cache get for .* key='$key', cache='.*l1.*': $miss_not_in_cache/);
    $log->empty_ok();

    $cache->set( $key, $value, 80 );
    my $length = length($value);
    $log->contains_ok(
        qr/cache set for .* key='$key', size=$length, expires='1m20s', cache='$driver'/
    );
    $log->contains_ok(
        qr/cache set for .* key='$key', size=$length, expires='1m20s', cache='.*l1.*'/
    );
    $log->empty_ok();

    $cache->get($key);
    $log->contains_ok(qr/cache get for .* key='$key', cache='.*l1.*': HIT/);
    $log->empty_ok();

    local $CHI::Driver::Test_Time = $start_time + 120;
    $cache->get($key);
    $log->contains_ok(
        qr/cache get for .* key='$key', cache='$driver': $miss_expired/);
    $log->contains_ok(
        qr/cache get for .* key='$key', cache='.*l1.*': $miss_expired/);
    $log->empty_ok();

    $cache->remove($key);
    $cache->get($key);
    $log->contains_ok(
        qr/cache get for .* key='$key', cache='$driver': $miss_not_in_cache/);
    $log->contains_ok(
        qr/cache get for .* key='$key', cache='.*l1.*': $miss_not_in_cache/);
    $log->empty_ok();
}

sub _test_logging_with_mirror_cache {
    my ( $self, $cache ) = @_;

    $cache->clear();
    my $log = CHI::Test::Logger->new();
    CHI->logger($log);
    my ( $key, $value ) = $self->kvpair();

    my $driver = $cache->short_driver_name;

    my $miss_not_in_cache = 'MISS \(not in cache\)';
    my $miss_expired      = 'MISS \(expired\)';

    my $start_time = time();

    $cache->get($key);
    $log->contains_ok(
        qr/cache get for .* key='$key', cache='$driver': $miss_not_in_cache/);
    $log->empty_ok();

    $cache->set( $key, $value, 80 );
    my $length = length($value);
    $log->contains_ok(
        qr/cache set for .* key='$key', size=$length, expires='1m20s', cache='$driver'/
    );
    $log->contains_ok(
        qr/cache set for .* key='$key', size=$length, expires='1m20s', cache='.*mirror.*'/
    );
    $log->empty_ok();

    $cache->get($key);
    $log->contains_ok(qr/cache get for .* key='$key', cache='$driver': HIT/);
    $log->empty_ok();

    local $CHI::Driver::Test_Time = $start_time + 120;
    $cache->get($key);
    $log->contains_ok(
        qr/cache get for .* key='$key', cache='$driver': $miss_expired/);
    $log->empty_ok();

    $cache->remove($key);
    $cache->get($key);
    $log->contains_ok(
        qr/cache get for .* key='$key', cache='$driver': $miss_not_in_cache/);
    $log->empty_ok();
}

# Run tests common to l1_cache and mirror_cache
#
sub _test_common_subcache_features {
    my ( $self, $cache, $subcache ) = @_;
    my ( $key, $value, $key2, $value2 ) = $self->kvpair(2);

    for ( $cache, $subcache ) { $_->clear() }

    # Test informational methods
    #
    ok( !$cache->is_subcache,             "is_subcache - false" );
    ok( $subcache->is_subcache,           "is_subcache - true" );
    ok( !defined( $cache->parent_cache ), "parent_cache - undef" );
    is( $subcache->parent_cache, $cache, "parent_cache - defined" );
    ok( !defined( $cache->subcache_type ), "subcache_type - undef" );
    cmp_deeply( $cache->subcaches,    [$subcache], "subcaches - empty" );
    cmp_deeply( $subcache->subcaches, [],          "subcaches - empty" );

    # Test that sets and various kinds of removals and expirations are distributed to both
    # the primary cache and the subcache
    #
    my ( $test_remove_method, $confirm_caches_empty,
        $confirm_caches_populated );
    $test_remove_method = sub {
        my ( $desc, $remove_code ) = @_;
        $desc = "testing $desc";

        $confirm_caches_empty->("$desc: before set");

        $cache->set( $key,  $value );
        $cache->set( $key2, $value2 );
        $confirm_caches_populated->("$desc: after set");
        $remove_code->();

        $confirm_caches_empty->("$desc: before set_multi");
        $cache->set_multi( { $key => $value, $key2 => $value2 } );
        $confirm_caches_populated->("$desc: after set_multi");
        $remove_code->();

        $confirm_caches_empty->("$desc: before return");
    };

    $confirm_caches_empty = sub {
        my ($desc) = @_;
        ok( !defined( $cache->get($key) ),
            "primary cache is not populated with '$key' - $desc" );
        ok( !defined( $subcache->get($key) ),
            "subcache is not populated with '$key' - $desc" );
        ok( !defined( $cache->get($key2) ),
            "primary cache is not populated #2 with '$key2' - $desc" );
        ok( !defined( $subcache->get($key2) ),
            "subcache is not populated #2 with '$key2' - $desc" );
    };

    $confirm_caches_populated = sub {
        my ($desc) = @_;
        is( $cache->get($key), $value,
            "primary cache is populated with '$key' - $desc" );
        is( $subcache->get($key), $value,
            "subcache is populated with '$key' - $desc" );
        is( $cache->get($key2), $value2,
            "primary cache is populated with '$key2' - $desc" );
        is( $subcache->get($key2), $value2,
            "subcache is populated with '$key2' - $desc" );
    };

    $test_remove_method->(
        'remove', sub { $cache->remove($key); $cache->remove($key2) }
    );
    $test_remove_method->(
        'expire', sub { $cache->expire($key); $cache->expire($key2) }
    );
    $test_remove_method->(
        'expire_if',
        sub {
            $cache->expire_if( $key,  sub { 1 } );
            $cache->expire_if( $key2, sub { 1 } );
        }
    );
    $test_remove_method->( 'clear', sub { $cache->clear() } );
}

sub test_clear : Tests {
    my $self  = shift;
    my $cache = $self->{cache};
    $self->num_tests( $self->{key_count} + 2 );

    if ( $self->supports_clear() ) {
        $self->set_some_keys($cache);
        $cache->clear();
        cmp_deeply( [ $cache->get_keys ], [], "get_keys after clear" );
        is( scalar( $cache->get_keys ), 0, "scalar(get_keys) = 0 after clear" );
        while ( my ( $keyname, $key ) = each( %{ $self->{keys} } ) ) {
            ok( !defined $cache->get($key),
                "key '$keyname' no longer defined after clear" );
        }
    }
    else {
        throws_ok(
            sub { $cache->clear() },
            qr/not supported/,
            "clear not supported"
        );
      SKIP: { skip "clear not supported", 9 }
    }
}

sub test_logging : Test(10) {
    my $self  = shift;
    my $cache = $self->{cache};

    my $log = CHI::Test::Logger->new();
    CHI->logger($log);
    my ( $key, $value ) = $self->kvpair();

    my $driver = $cache->short_driver_name;

    # Multilevel cache logs less details about misses
    my $miss_not_in_cache =
      ( $driver eq 'Multilevel' ? 'MISS' : 'MISS \(not in cache\)' );
    my $miss_expired =
      ( $driver eq 'Multilevel' ? 'MISS' : 'MISS \(expired\)' );

    my $start_time = time();

    $cache->get($key);
    $log->contains_ok(
        qr/cache get for .* key='$key', cache='$driver': $miss_not_in_cache/);
    $log->empty_ok();

    $cache->set( $key, $value, 80 );
    my $length = length($value);
    $log->contains_ok(
        qr/cache set for .* key='$key', size=$length, expires='1m20s', cache='$driver'/
    );
    $log->empty_ok();

    $cache->get($key);
    $log->contains_ok(qr/cache get for .* key='$key', cache='$driver': HIT/);
    $log->empty_ok();

    local $CHI::Driver::Test_Time = $start_time + 120;
    $cache->get($key);
    $log->contains_ok(
        qr/cache get for .* key='$key', cache='$driver': $miss_expired/);
    $log->empty_ok();

    $cache->remove($key);
    $cache->get($key);
    $log->contains_ok(
        qr/cache get for .* key='$key', cache='$driver': $miss_not_in_cache/);
    $log->empty_ok();
}

sub test_cache_object : Test(6) {
    my $self  = shift;
    my $cache = $self->{cache};
    my ( $key, $value ) = $self->kvpair();
    my $start_time = time();
    $cache->set( $key, $value, { expires_at => $start_time + 10 } );
    is_between( $cache->get_object($key)->created_at,
        $start_time, $start_time + 2 );
    is_between( $cache->get_object($key)->get_created_at,
        $start_time, $start_time + 2 );
    is( $cache->get_object($key)->expires_at,     $start_time + 10 );
    is( $cache->get_object($key)->get_expires_at, $start_time + 10 );

    local $CHI::Driver::Test_Time = $start_time + 50;
    $cache->set( $key, $value );
    is_between(
        $cache->get_object($key)->created_at,
        $start_time + 50,
        $start_time + 52
    );
    is_between(
        $cache->get_object($key)->get_created_at,
        $start_time + 50,
        $start_time + 52
    );
}

sub test_busy_lock : Test(5) {
    my $self  = shift;
    my $cache = $self->{cache};

    my ( $key, $value ) = $self->kvpair();
    my @bl = ( busy_lock => '30 sec' );
    my $start_time = time();

    local $CHI::Driver::Test_Time = $start_time;
    $cache->set( $key, $value, 100 );
    local $CHI::Driver::Test_Time = $start_time + 90;
    is( $cache->get( $key, @bl ), $value, "hit before expiration" );
    is(
        $cache->get_expires_at($key),
        $start_time + 100,
        "expires_at before expiration"
    );
    local $CHI::Driver::Test_Time = $start_time + 110;
    ok( !defined( $cache->get( $key, @bl ) ), "miss after expiration" );
    is(
        $cache->get_expires_at($key),
        $start_time + 140,
        "expires_at after busy lock"
    );
    is( $cache->get( $key, @bl ), $value, "hit after busy lock" );
}

sub test_obj_ref : Tests(8) {
    my $self  = shift;
    my $cache = $self->{cache};
    my $obj;
    my ( $key, $value ) = ( 'medium', [ a => 5, b => 6 ] );

    my $validate_obj = sub {
        my $obj = shift;
        isa_ok( $obj, 'CHI::CacheObject' );
        is( $obj->key, $key, "keys match" );
        cmp_deeply( $obj->value, $value, "values match" );
    };

    $cache->get( $key, obj_ref => \$obj );
    ok( !defined($obj), "obj not defined on miss" );
    $cache->set( $key, $value, { obj_ref => \$obj } );
    $validate_obj->($obj);
    undef $obj;
    ok( !defined($obj), "obj not defined before get" );
    $cache->get( $key, obj_ref => \$obj );
    $validate_obj->($obj);
}

sub test_no_leak : Tests(2) {
    my ($self) = @_;

    my $weakref;
    {
        my $cache = $self->new_cache();
        $weakref = $cache;
        weaken($weakref);
        ok( defined($weakref) && $weakref->isa('CHI::Driver'),
            "weakref is defined" );
    }
    ok( !defined($weakref), "weakref is no longer defined - cache was freed" );
}

## no critic
{ package My::CHI; use Mouse; extends 'CHI' }

sub test_driver_properties : Tests(2) {
    my $self  = shift;
    my $cache = $self->{cache};

    is( $cache->chi_root_class, 'CHI', 'chi_root_class=CHI' );
    my $cache2 = My::CHI->new( $self->new_cache_options() );
    is( $cache2->chi_root_class, 'My::CHI', 'chi_root_class=My::CHI' );
}

sub test_missing_params : Tests(13) {
    my $self  = shift;
    my $cache = $self->{cache};

    # These methods require a key
    foreach my $method (
        qw(get get_object get_expires_at exists_and_is_expired is_valid set expire expire_if compute get_multi_arrayref get_multi_hashref set_multi remove_multi)
      )
    {
        throws_ok(
            sub { $cache->$method() },
            qr/must specify key/,
            "$method throws error when no key passed"
        );
    }
}

1;
