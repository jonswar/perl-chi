package CHI::t::Driver;
use strict;
use warnings;
use CHI::Test;
use CHI::Test::Util
  qw(activate_test_logger cmp_bool is_between random_string skip_until);
use CHI::Util qw(can_load dump_one_line write_file);
use Encode;
use File::Spec::Functions qw(tmpdir);
use File::Temp qw(tempdir);
use List::Util qw(shuffle);
use Scalar::Util qw(weaken);
use Storable qw(dclone);
use Test::Warn;
use Time::HiRes qw(usleep);
use base qw(CHI::Test::Class);

# Flags indicating what each test driver supports
sub supports_clear              { 1 }
sub supports_expires_on_backend { 0 }
sub supports_get_namespaces     { 1 }

sub standard_keys_and_values : Test(startup) {
    my ($self) = @_;

    my ( $keys_ref, $values_ref ) = $self->set_standard_keys_and_values();
    $self->{keys}          = $keys_ref;
    $self->{values}        = $values_ref;
    $self->{keynames}      = [ keys( %{$keys_ref} ) ];
    $self->{key_count}     = scalar( @{ $self->{keynames} } );
    $self->{all_test_keys} = [ values(%$keys_ref), $self->extra_test_keys() ];
    my $cache = $self->new_cache();
    push(
        @{ $self->{all_test_keys} },
        $self->process_keys( $cache, @{ $self->{all_test_keys} } )
    );
    $self->{all_test_keys_hash} =
      { map { ( $_, 1 ) } @{ $self->{all_test_keys} } };
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

sub testing_chi_root_class {
    return 'CHI';
}

sub new_cache {
    my $self = shift;

    return $self->testing_chi_root_class->new( $self->new_cache_options(), @_ );
}

sub new_cleared_cache {
    my $self = shift;

    my $cache = $self->new_cache(@_);
    $cache->clear();
    return $cache;
}

sub new_cache_options {
    my $self = shift;

    return (
        driver       => '+' . $self->testing_driver_class(),
        on_get_error => 'die',
        on_set_error => 'die'
    );
}

sub set_standard_keys_and_values {
    my $self = shift;

    my ( %keys, %values );
    my @mixed_chars = ( 32 .. 48, 57 .. 65, 90 .. 97, 122 .. 126, 240 );

    %keys = (
        'space'   => ' ',
        'newline' => "\n",
        'char'    => 'a',
        'zero'    => 0,
        'one'     => 1,
        'medium'  => 'medium',
        'mixed'   => join( "", map { chr($_) } @mixed_chars ),
        'binary'  => join( "", map { chr($_) } ( 129 .. 255 ) ),
        'large'   => scalar( 'ab' x 256 ),
        'empty'   => 'empty',
        'arrayref' => [ 1, 2 ],
        'hashref' => { foo => [ 'bar', 'baz' ] },
        'utf8'    => "Have \x{263a} a nice day",
    );

    %values = map {
        ( $_, ref( $keys{$_} ) ? $keys{$_} : scalar( reverse( $keys{$_} ) ) )
    } keys(%keys);
    $values{empty} = '';

    return ( \%keys, \%values );
}

# Extra keys (beyond the standard keys above) that we may use in these
# tests. We need to adhere to this for the benefit of drivers that don't
# support get_keys (like memcached) - they simulate get_keys(), clear(),
# etc. by using this fixed list of keys.
#
sub extra_test_keys {
    my ($class) = @_;
    return (
        '',        '2',
        'medium2', 'foo',
        'hashref', 'test_namespace_types',
        "utf8",    "encoded",
        "binary", ( map { "done$_" } ( 0 .. 2 ) ),
        ( map { "key$_" } ( 0 .. 20 ) )
    );
}

sub set_some_keys {
    my ( $self, $c ) = @_;

    foreach my $keyname ( @{ $self->{keynames} } ) {
        $c->set( $self->{keys}->{$keyname}, $self->{values}->{$keyname} );
    }
}

sub test_encode : Tests {
    my $self  = shift;
    my $cache = $self->new_cleared_cache();

    my $utf8       = $self->{keys}->{utf8};
    my $encoded    = encode( utf8 => $utf8 );
    my $binary_off = $self->{keys}->{binary};
    my $binary_on  = substr( $binary_off . $utf8, 0, length($binary_off) );

    ok( $binary_off eq $binary_on, "binary_off eq binary_on" );
    ok( !Encode::is_utf8($binary_off), "!is_utf8(binary_off)" );
    ok( Encode::is_utf8($binary_on),   "is_utf8(binary_on)" );

    # Key maps to same thing whether encoded or non-encoded
    #
    my $value = time;
    $cache->set( $utf8, $value );
    is( $cache->get($utf8), $value, "get" );
    is( $cache->get($encoded), $value,
        "encoded and non-encoded map to same value" );

    # Key maps to same thing whether utf8 flag is off or on
    #
    # Commenting out for now - this is broken on FastMmap and
    # DBI drivers (at least), and not entirely sure whether or
    # with what priority we should demand this behavior.
    #
    if (0) {
        $cache->set( $binary_off, $value );
        is( $cache->get($binary_off), $value, "get binary_off" );
        is( $cache->get($binary_on),
            $value, "binary_off and binary_on map to same value" );
        $cache->clear($binary_on);
        ok( !$cache->get($binary_off), "cleared binary_off" );    #
    }

    # Value is maintained as a utf8 or binary string, in scalar or in arrayref
    $cache->set( "utf8", $utf8 );
    is( $cache->get("utf8"), $utf8, "utf8 in scalar" );
    $cache->set( "utf8", [$utf8] );
    is( $cache->get("utf8")->[0], $utf8, "utf8 in arrayref" );

    $cache->set( "encoded", $encoded );
    is( $cache->get("encoded"), $encoded, "encoded in scalar" );
    $cache->set( "encoded", [$encoded] );
    is( $cache->get("encoded")->[0], $encoded, "encoded in arrayref" );

    # Value retrieves as same thing whether stored with utf8 flag off or on
    #
    $cache->set( "binary", $binary_off );
    is( $cache->get("binary"), $binary_on, "stored binary_off = binary_on" );
    $cache->set( "binary", $binary_on );
    is( $cache->get("binary"), $binary_off, "stored binary_on = binary_off" );
}

sub test_simple : Tests {
    my $self = shift;
    my $cache = shift || $self->{cache};

    ok( $cache->set( $self->{keys}->{medium}, $self->{values}->{medium} ) );
    is( $cache->get( $self->{keys}->{medium} ), $self->{values}->{medium} );
}

sub test_driver_class : Tests {
    my $self  = shift;
    my $cache = $self->{cache};

    isa_ok( $cache, 'CHI::Driver' );
    isa_ok( $cache, $cache->driver_class );
    can_ok( $cache, 'get', 'set', 'remove', 'clear', 'expire' );
}

sub test_key_types : Tests {
    my $self  = shift;
    my $cache = $self->{cache};
    $self->num_tests( $self->{key_count} * 9 + 1 );

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
        push( @keys_set, $self->process_keys( $cache, $key ) );
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

    # Confirm that transform_key is idempotent
    #
    foreach my $keyname ( @{ $self->{keynames} } ) {
        my $key   = $self->{keys}->{$keyname};
        my $value = $self->{values}->{$keyname};
        is(
            $cache->transform_key( $cache->transform_key($key) ),
            $cache->transform_key($key),
            "transform_key is idempotent for '$keyname'"
        );
        $cache->clear();
        $cache->set( $key, $value );
        is( scalar( $cache->get_keys() ), 1, "exactly one key" );
        cmp_deeply( $cache->get( ( $cache->get_keys )[0] ),
            $value, "get with get_keys[0] got same value" );
    }
}

sub test_deep_copy : Tests {
    my $self  = shift;
    my $cache = $self->{cache};

    $self->set_some_keys($cache);
    foreach my $keyname (qw(arrayref hashref)) {
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

    my $struct = { a => [ 1, 2 ], b => [ 4, 5 ] };
    my $struct2 = dclone($struct);
    $cache->set( 'hashref', $struct );
    push( @{ $struct->{a} }, 3 );
    delete( $struct->{b} );
    cmp_deeply( $cache->get('hashref'),
        $struct2,
        "altering original set structure does not affect cached copy" );
}

sub test_expires_immediately : Tests {
    my $self = shift;

    return 'author testing only - timing is unreliable'
      unless ( $ENV{AUTHOR_TESTING} );

    # expires_in default should be ignored
    my $cache = $self->new_cache( expires_in => '1 hour' );

    # Expires immediately
    my $test_expires_immediately = sub {
        my ($set_option) = @_;
        my ( $key, $value ) = $self->kvpair();
        my $desc = dump_one_line($set_option);
        is( $cache->set( $key, $value, $set_option ), $value, "set ($desc)" );
        is_between(
            $cache->get_expires_at($key),
            time() - 4,
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

sub test_expires_shortly : Tests {
    my $self = shift;

    return 'author testing only - timing is unreliable'
      unless ( $ENV{AUTHOR_TESTING} );

    # expires_in default should be ignored
    my $cache = $self->new_cache( expires_in => '1 hour' );

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
            $start_time + 8,
            "expires_at ($desc)"
        );
        ok( !$cache->exists_and_is_expired($key), "not expired ($desc)" );
        ok( $cache->is_valid($key),               "valid ($desc)" );

        # Only bother sleeping and expiring for one of the variants
        if ( $set_option eq "3 seconds" ) {
            sleep(3);
            ok( !defined $cache->get($key), "miss after 2 seconds ($desc)" );
            ok( $cache->exists_and_is_expired($key), "is_expired ($desc)" );
            ok( !$cache->is_valid($key),             "invalid ($desc)" );
        }
    };
    $test_expires_shortly->(3);
    $test_expires_shortly->("3 seconds");
    $test_expires_shortly->( { expires_at => time + 3 } );
}

sub test_expires_later : Tests {
    my $self = shift;

    return 'author testing only - timing is unreliable'
      unless ( $ENV{AUTHOR_TESTING} );

    # expires_in default should be ignored
    my $cache = $self->new_cache( expires_in => '1s' );

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
            $start_time + 3580,
            $start_time + 3620,
            "expires_at ($desc)"
        );
        ok( !$cache->exists_and_is_expired($key), "not expired ($desc)" );
        ok( $cache->is_valid($key),               "valid ($desc)" );
        local $CHI::Driver::Test_Time = $start_time + 3590;
        ok( !$cache->exists_and_is_expired($key), "not expired ($desc)" );
        ok( $cache->is_valid($key),               "valid ($desc)" );
        local $CHI::Driver::Test_Time = $start_time + 3610;
        ok( !defined $cache->get($key),          "miss after 1 hour ($desc)" );
        ok( $cache->exists_and_is_expired($key), "is_expired ($desc)" );
        ok( !$cache->is_valid($key),             "invalid ($desc)" );
    };
    $test_expires_later->(3600);
    $test_expires_later->("1 hour");
    $test_expires_later->( { expires_at => time + 3600 } );
}

sub test_expires_never : Tests {
    my $self = shift;
    my $cache;

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

    # never is default
    $cache = $self->new_cache();
    $test_expires_never->();

    # expires_in default should be ignored when never passed to set (RT #67970)
    $cache = $self->new_cache( expires_in => '1s' );
    $test_expires_never->('never');
}

sub test_expires_defaults : Tests {
    my $self = shift;

    my $start_time = time();
    local $CHI::Driver::Test_Time = $start_time;
    my $cache;

    my $set_and_confirm_expires_at = sub {
        my ( $expected_expires_at, $desc )  = @_;
        my ( $key,                 $value ) = $self->kvpair();
        $cache->set( $key, $value );
        is( $cache->get_expires_at($key), $expected_expires_at, $desc );
        $cache->clear();
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

sub test_expires_manually : Tests {
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

sub test_expires_conditionally : Tests {
    my $self  = shift;
    my $cache = $self->{cache};

    # Expires conditionally
    my $test_expires_conditionally = sub {
        my ( $code, $cond_desc, $expect_expire ) = @_;

        my ( $key, $value ) = $self->kvpair();
        my $desc = "expires conditionally ($cond_desc)";
        $cache->set( $key, $value );
        is(
            $cache->get( $key, expire_if => $code ),
            $expect_expire ? undef : $value,
            "get result ($desc)"
        );

        is( $cache->get($key), $value, "hit after expire_if ($desc)" );

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

sub test_expires_variance : Tests {
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

sub test_not_in_cache : Tests {
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
        my $expect_transformed =
            ( $keyname eq 'arrayref' || $keyname eq 'hashref' ) ? 1
          : ( $keyname eq 'utf8' ) ? 2
          :                          0;
        is(
            $cache->get_object( $self->{keys}->{$keyname} )->_is_transformed(),
            $expect_transformed,
            "is_transformed = $expect_transformed ($keyname)"
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

    unless ( can_load('Data::Serializer') ) {
        $self->num_tests(1);
        return 'Data::Serializer not installed';
    }

    my @modes    = (qw(string hash object));
    my @variants = (qw(Storable Data::Dumper YAML));
    @variants = grep { can_load($_) } @variants;
    ok( scalar(@variants), "some variants ok" );

    my $initial_count        = 5;
    my $test_key_types_count = $self->{key_count};
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
        qr/Validation failed for|isa check for ".*?" failed/,
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

            foreach my $keyname ( @{ $self->{keynames} } ) {
                my $key   = $self->{keys}->{$keyname};
                my $value = $self->{values}->{$keyname};
                $cache->set( $key, $value );
                cmp_deeply( $cache->get($key), $value,
                    "hit for key '$keyname'" );
            }

            $self->num_tests($test_count);
        }
    }
}

sub test_namespaces : Tests {
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

sub test_persist : Tests {
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

sub test_multi : Tests {
    my $self  = shift;
    my $cache = $self->{cache};

    my ( $keys, $values, $keynames ) =
      ( $self->{keys}, $self->{values}, $self->{keynames} );

    my @ordered_keys = map { $keys->{$_} } @{$keynames};
    my @ordered_values =
      map { $values->{$_} } @{$keynames};
    my %ordered_scalar_key_values =
      map { ( $keys->{$_}, $values->{$_} ) }
      grep { !ref( $keys->{$_} ) } @{$keynames};

    cmp_deeply( $cache->get_multi_arrayref( ['foo'] ),
        [undef], "get_multi_arrayref before set" );

    $cache->set_multi( \%ordered_scalar_key_values );
    $cache->set( $keys->{arrayref}, $values->{arrayref} );
    $cache->set( $keys->{hashref},  $values->{hashref} );

    cmp_deeply( $cache->get_multi_arrayref( \@ordered_keys ),
        \@ordered_values, "get_multi_arrayref" );
    cmp_deeply( $cache->get( $ordered_keys[0] ),
        $ordered_values[0], "get one after set_multi" );
    cmp_deeply(
        $cache->get_multi_arrayref( [ reverse @ordered_keys ] ),
        [ reverse @ordered_values ],
        "get_multi_arrayref"
    );
    cmp_deeply(
        $cache->get_multi_hashref( [ grep { !ref($_) } @ordered_keys ] ),
        \%ordered_scalar_key_values, "get_multi_hashref" );
    cmp_set(
        [ $cache->get_keys ],
        [ $self->process_keys( $cache, @ordered_keys ) ],
        "get_keys after set_multi"
    );

    $cache->remove_multi( \@ordered_keys );
    cmp_deeply(
        $cache->get_multi_arrayref( \@ordered_keys ),
        [ (undef) x scalar(@ordered_values) ],
        "get_multi_arrayref after remove_multi"
    );
    cmp_set( [ $cache->get_keys ], [], "get_keys after remove_multi" );
}

sub test_multi_no_keys : Tests {
    my $self  = shift;
    my $cache = $self->{cache};

    cmp_deeply( $cache->get_multi_arrayref( [] ),
        [], "get_multi_arrayref (no args)" );
    cmp_deeply( $cache->get_multi_hashref( [] ),
        {}, "get_multi_hashref (no args)" );
    lives_ok { $cache->set_multi( {} ) } "set_multi (no args)";
    lives_ok { $cache->remove_multi( [] ) } "remove_multi (no args)";
}

sub test_l1_cache : Tests {
    my $self   = shift;
    my @keys   = map { "key$_" } ( 0 .. 2 );
    my @values = map { "value$_" } ( 0 .. 2 );
    my ( $cache, $l1_cache );

    return "skipping - no support for clear" unless $self->supports_clear();

    my $test_l1_cache = sub {

        is( $l1_cache->subcache_type, "l1_cache", "subcache_type = l1_cache" );

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
        $cache->set( $keys[1], $values[1] );
        $l1_cache->remove( $keys[0] );
        $l1_cache->set( $keys[1], $values[2] );

        cmp_deeply(
            $cache->get_multi_arrayref( [ $keys[0], $keys[1], $keys[2] ] ),
            [ $values[0], $values[2], undef ],
            "get_multi_arrayref"
        );
        cmp_deeply(
            $cache->get_multi_hashref( [ $keys[0], $keys[1], $keys[2] ] ),
            {
                $keys[0] => $values[0],
                $keys[1] => $values[2],
                $keys[2] => undef
            },
            "get_multi_hashref"
        );

        $self->_test_logging_with_l1_cache( $cache, $l1_cache );

        $self->_test_common_subcache_features( $cache, $l1_cache, 'l1_cache' );
    };

    # Test with current cache in primary position...
    #
    $cache =
      $self->new_cache( l1_cache => { driver => 'Memory', datastore => {} } );
    $l1_cache = $cache->l1_cache;
    isa_ok( $cache,    $self->testing_driver_class, 'cache' );
    isa_ok( $l1_cache, 'CHI::Driver::Memory',       'l1_cache' );
    $test_l1_cache->();

    # and in l1 position
    #
    $cache = $self->testing_chi_root_class->new(
        driver    => 'Memory',
        datastore => {},
        l1_cache  => { $self->new_cache_options() }
    );
    $l1_cache = $cache->l1_cache;
    isa_ok( $cache,    'CHI::Driver::Memory',       'cache' );
    isa_ok( $l1_cache, $self->testing_driver_class, 'l1_cache' );
    $test_l1_cache->();
}

sub test_mirror_cache : Tests {
    my $self = shift;
    my ( $cache, $mirror_cache );
    my ( $key, $value, $key2, $value2 ) = $self->kvpair(2);

    return "skipping - no support for clear" unless $self->supports_clear();

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

        $self->_test_common_subcache_features( $cache, $mirror_cache,
            'mirror_cache' );
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
      $self->testing_chi_root_class->new( $file_cache_options->(),
        mirror_cache => { $self->new_cache_options() } );
    $mirror_cache = $cache->mirror_cache;
    isa_ok( $cache,        'CHI::Driver::File' );
    isa_ok( $mirror_cache, $self->testing_driver_class );
    $test_mirror_cache->();
}

sub test_subcache_overridable_params : Tests {
    my ($self) = @_;

    my $cache;
    warning_like {
        $cache = $self->new_cache(
            l1_cache => {
                driver           => 'Memory',
                on_get_error     => 'log',
                datastore        => {},
                expires_variance => 0.5,
                serializer       => 'Foo'
            }
        );
    }
    qr/cannot override these keys/, "non-overridable subcache keys";
    is( $cache->l1_cache->expires_variance, $cache->expires_variance );
    is( $cache->l1_cache->serializer,       $cache->serializer );
    is( $cache->l1_cache->on_set_error,     $cache->on_set_error );
    is( $cache->l1_cache->on_get_error,     'log' );
}

# Run logging tests for a cache with an l1_cache
#
sub _test_logging_with_l1_cache {
    my ( $self, $cache ) = @_;

    $cache->clear();
    my $log = activate_test_logger();
    my ( $key, $value ) = $self->kvpair();

    my $driver = $cache->label;

    my $miss_not_in_cache = 'MISS \(not in cache\)';
    my $miss_expired      = 'MISS \(expired\)';

    my $start_time = time();

    $cache->get($key);
    $log->contains_ok(
        qr/cache get for .* key='$key', cache='$driver', time='[-\d]+ms': $miss_not_in_cache/
    );
    $log->contains_ok(
        qr/cache get for .* key='$key', cache='.*l1.*', time='[-\d]+ms': $miss_not_in_cache/
    );
    $log->empty_ok();

    $cache->set( $key, $value, 81 );
    $log->contains_ok(
        qr/cache set for .* key='$key', size=\d+, expires='1m2[012]s', cache='$driver', time='[-\d]+ms'/
    );

    $log->contains_ok(
        qr/cache set for .* key='$key', size=\d+, expires='1m2[012]s', cache='.*l1.*', time='[-\d]+ms'/
    );
    $log->empty_ok();

    $cache->get($key);
    $log->contains_ok(
        qr/cache get for .* key='$key', cache='.*l1.*', time='[-\d]+ms': HIT/);
    $log->empty_ok();

    local $CHI::Driver::Test_Time = $start_time + 120;
    $cache->get($key);
    $log->contains_ok(
        qr/cache get for .* key='$key', cache='$driver', time='[-\d]+ms': $miss_expired/
    );
    $log->contains_ok(
        qr/cache get for .* key='$key', cache='.*l1.*', time='[-\d]+ms': $miss_expired/
    );
    $log->empty_ok();

    $cache->remove($key);
    $cache->get($key);
    $log->contains_ok(
        qr/cache get for .* key='$key', cache='$driver', time='[-\d]+ms': $miss_not_in_cache/
    );
    $log->contains_ok(
        qr/cache get for .* key='$key', cache='.*l1.*', time='[-\d]+ms': $miss_not_in_cache/
    );
    $log->empty_ok();
}

sub _test_logging_with_mirror_cache {
    my ( $self, $cache ) = @_;

    $cache->clear();
    my $log = activate_test_logger();
    my ( $key, $value ) = $self->kvpair();

    my $driver = $cache->label;

    my $miss_not_in_cache = 'MISS \(not in cache\)';
    my $miss_expired      = 'MISS \(expired\)';

    my $start_time = time();

    $cache->get($key);
    $log->contains_ok(
        qr/cache get for .* key='$key', cache='$driver', time='[-\d]+ms': $miss_not_in_cache/
    );
    $log->empty_ok();

    $cache->set( $key, $value, 81 );
    $log->contains_ok(
        qr/cache set for .* key='$key', size=\d+, expires='1m2[012]s', cache='$driver', time='[-\d]+ms'/
    );

    $log->contains_ok(
        qr/cache set for .* key='$key', size=\d+, expires='1m2[012]s', cache='.*mirror.*', time='[-\d]+ms'/
    );
    $log->empty_ok();

    $cache->get($key);
    $log->contains_ok(
        qr/cache get for .* key='$key', cache='$driver', time='[-\d]+ms': HIT/);
    $log->empty_ok();

    local $CHI::Driver::Test_Time = $start_time + 120;
    $cache->get($key);
    $log->contains_ok(
        qr/cache get for .* key='$key', cache='$driver', time='[-\d]+ms': $miss_expired/
    );
    $log->empty_ok();

    $cache->remove($key);
    $cache->get($key);
    $log->contains_ok(
        qr/cache get for .* key='$key', cache='$driver', time='[-\d]+ms': $miss_not_in_cache/
    );
    $log->empty_ok();
}

# Run tests common to l1_cache and mirror_cache
#
sub _test_common_subcache_features {
    my ( $self, $cache, $subcache, $subcache_type ) = @_;
    my ( $key,  $value, $key2,     $value2 )        = $self->kvpair(2);

    for ( $cache, $subcache ) { $_->clear() }

    # Test informational methods
    #
    ok( !$cache->is_subcache,         "is_subcache - false" );
    ok( $subcache->is_subcache,       "is_subcache - true" );
    ok( $cache->has_subcaches,        "has_subcaches - true" );
    ok( !$subcache->has_subcaches,    "has_subcaches - false" );
    ok( !$cache->can('parent_cache'), "parent_cache - cannot" );
    is( $subcache->parent_cache, $cache, "parent_cache - defined" );
    ok( !$cache->can('subcache_type'), "subcache_type - cannot" );
    is( $subcache->subcache_type, $subcache_type, "subcache_type - defined" );
    cmp_deeply( $cache->subcaches, [$subcache], "subcaches - defined" );
    ok( !$subcache->can('subcaches'), "subcaches - cannot" );
    is( $cache->$subcache_type, $subcache, "$subcache_type - defined" );
    ok( !$subcache->can($subcache_type), "$subcache_type - cannot" );

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
    $test_remove_method->( 'clear', sub { $cache->clear() } );
}

sub _verify_cache_is_cleared {
    my ( $self, $cache, $desc ) = @_;

    cmp_deeply( [ $cache->get_keys ], [], "get_keys ($desc)" );
    is( scalar( $cache->get_keys ), 0, "scalar(get_keys) = 0 ($desc)" );
    while ( my ( $keyname, $key ) = each( %{ $self->{keys} } ) ) {
        ok( !defined $cache->get($key),
            "key '$keyname' no longer defined ($desc)" );
    }
}

sub process_keys {
    my ( $self, $cache, @keys ) = @_;
    $self->process_key( $cache, 'foo' );
    return map { $self->process_key( $cache, $_ ) } @keys;
}

sub process_key {
    my ( $self, $cache, $key ) = @_;
    return $cache->unescape_key(
        $cache->escape_key( $cache->transform_key($key) ) );
}

sub test_clear : Tests {
    my $self   = shift;
    my $cache  = $self->new_cache( namespace => 'name' );
    my $cache2 = $self->new_cache( namespace => 'other' );
    my $cache3 = $self->new_cache( namespace => 'name' );
    $self->num_tests( $self->{key_count} * 2 + 5 );

    if ( $self->supports_clear() ) {
        $self->set_some_keys($cache);
        $self->set_some_keys($cache2);
        $cache->clear();

        $self->_verify_cache_is_cleared( $cache,  'cache after clear' );
        $self->_verify_cache_is_cleared( $cache3, 'cache3 after clear' );
        cmp_set(
            [ $cache2->get_keys ],
            [ $self->process_keys( $cache2, values( %{ $self->{keys} } ) ) ],
            'cache2 untouched by clear'
        );
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

sub test_logging : Tests {
    my $self  = shift;
    my $cache = $self->{cache};

    my $log = activate_test_logger();
    my ( $key, $value ) = $self->kvpair();

    my $driver = $cache->label;

    my $miss_not_in_cache = 'MISS \(not in cache\)';
    my $miss_expired      = 'MISS \(expired\)';

    my $start_time = time();

    $cache->get($key);
    $log->contains_ok(
        qr/cache get for .* key='$key', cache='$driver', time='[-\d]+ms': $miss_not_in_cache/
    );
    $log->empty_ok();

    $cache->set( $key, $value );
    $log->contains_ok(
        qr/cache set for .* key='$key', size=\d+, expires='never', cache='$driver', time='[-\d]+ms'/
    );
    $log->empty_ok();
    $cache->set( $key, $value, 81 );
    $log->contains_ok(
        qr/cache set for .* key='$key', size=\d+, expires='1m2[012]s', cache='$driver', time='[-\d]+ms'/
    );
    $log->empty_ok();

    $cache->get($key);
    $log->contains_ok(
        qr/cache get for .* key='$key', cache='$driver', time='[-\d]+ms': HIT/);
    $log->empty_ok();

    local $CHI::Driver::Test_Time = $start_time + 120;
    $cache->get($key);
    $log->contains_ok(
        qr/cache get for .* key='$key', cache='$driver', time='[-\d]+ms': $miss_expired/
    );
    $log->empty_ok();

    $cache->remove($key);
    $cache->get($key);
    $log->contains_ok(
        qr/cache get for .* key='$key', cache='$driver', time='[-\d]+ms': $miss_not_in_cache/
    );
    $log->empty_ok();
}

sub test_stats : Tests {
    my $self = shift;

    return 'author testing only - possible differences between JSON versions'
      unless ( $ENV{AUTHOR_TESTING} );

    my $stats = $self->testing_chi_root_class->stats;
    $stats->enable();

    my ( $key, $value ) = $self->kvpair();
    my $start_time = time();

    my $cache;
    $cache = $self->new_cache( namespace => 'Foo' );
    $cache->get($key);
    $cache->set( $key, $value, 80 );
    $cache->get($key);
    local $CHI::Driver::Test_Time = $start_time + 120;
    $cache->get($key);
    $cache->remove($key);
    $cache->get($key);

    $cache = $self->new_cache( namespace => 'Bar' );
    $cache->set( $key, scalar( $value x 3 ) );
    $cache->set( $key, $value );

    $cache = $self->new_cache( namespace => 'Baz' );
    my $code = sub { usleep(100000); scalar( $value x 5 ) };
    $cache->compute( $key, undef, $code );
    $cache->compute( $key, undef, $code );
    $cache->compute( $key, undef, $code );

    my $log   = activate_test_logger();
    my $label = $cache->label;
    $log->empty_ok();
    $stats->flush();
    $log->contains_ok(
        qr/CHI stats: {"absent_misses":2,"end_time":\d+,"expired_misses":1,"get_time_ms":\d+,"hits":1,"label":"$label","namespace":"Foo","root_class":"CHI","set_key_size":6,"set_time_ms":\d+,"set_value_size":20,"sets":1,"start_time":\d+}/
    );
    $log->contains_ok(
        qr/CHI stats: {"end_time":\d+,"label":"$label","namespace":"Bar","root_class":"CHI","set_key_size":12,"set_time_ms":\d+,"set_value_size":52,"sets":2,"start_time":\d+}/
    );
    $log->contains_ok(
        qr/CHI stats: {"absent_misses":1,"compute_time_ms":\d+,"computes":1,"end_time":\d+,"get_time_ms":\d+,"hits":2,"label":"$label","namespace":"Baz","root_class":"CHI","set_key_size":6,"set_time_ms":\d+,"set_value_size":44,"sets":1,"start_time":\d+}/
    );
    $log->empty_ok();

    my @logs = (
        'CHI stats: {"root_class":"CHI","namespace":"Foo","label":"File","start_time":1338404896,"end_time":1338404899,"hits":3,"sets":5,"set_time_ms":10}',
        'CHI stats: {"root_class":"CHI","namespace":"Foo","label":"File","start_time":1338404896,"end_time":1338404899,"hits":1,"sets":7,"set_time_ms":14}',
        'CHI stats: {"root_class":"CHI","namespace":"Bar","label":"File","start_time":1338404896,"end_time":1338404899,"hits":4,"sets":9,"set_time_ms":18}',
        'CHI stats: {"root_class":"CHI","namespace":"Foo","label":"File","start_time":1338404896,"end_time":1338404899,"sets":3,"set_time_ms":6}',
        'CHI stats: {"root_class":"CHI","namespace":"Foo","label":"File","start_time":1338404896,"end_time":1338404899,"hits":8}',
        'CHI stats: {"root_class":"CHI","namespace":"Foo","label":"Memory","start_time":1338404896,"end_time":1338404899,"sets":2,"set_time_ms":4}',
        'CHI stats: {"root_class":"CHI","namespace":"Bar","label":"File","start_time":1338404896,"end_time":1338404899,"hits":10,"sets":1,"set_time_ms":2}',
        'CHI stats: {"root_class":"CHI","namespace":"Bar","label":"File","start_time":1338404896,"end_time":1338404899,"hits":3,"set_errors":2}',
    );
    my $log_dir = tempdir( "chi-test-stats-XXXX", TMPDIR => 1, CLEANUP => 1 );
    write_file( "$log_dir/log1", join( "\n", splice( @logs, 0, 4 ) ) . "\n" );
    write_file( "$log_dir/log2", join( "\n", @logs ) );
    open( my $fh2, "<", "$log_dir/log2" ) or die "cannot open $log_dir/log2";
    my $results = $stats->parse_stats_logs( "$log_dir/log1", $fh2 );
    close($fh2);
    cmp_deeply(
        $results,
        Test::Deep::bag(
            {
                avg_set_time_ms => '2',
                gets            => 12,
                hit_rate        => '1',
                hits            => 12,
                label           => 'File',
                namespace       => 'Foo',
                root_class      => 'CHI',
                set_time_ms     => 30,
                sets            => 15
            },
            {
                avg_set_time_ms => '2',
                gets            => 17,
                hit_rate        => '1',
                hits            => 17,
                label           => 'File',
                namespace       => 'Bar',
                root_class      => 'CHI',
                set_errors      => 2,
                set_time_ms     => 20,
                sets            => 10
            },
            {
                avg_set_time_ms => '2',
                label           => 'Memory',
                namespace       => 'Foo',
                root_class      => 'CHI',
                set_time_ms     => 4,
                sets            => 2
            },
            {
                avg_set_time_ms => '2',
                hits            => '29',
                label           => 'TOTALS',
                namespace       => 'TOTALS',
                root_class      => 'TOTALS',
                set_errors      => '2',
                set_time_ms     => 54,
                sets            => 27
            }
        ),
        'parse_stats_logs'
    );
}

sub test_cache_object : Tests {
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

sub test_size_awareness : Tests {
    my $self = shift;
    my ( $key, $value ) = $self->kvpair();

    ok( !$self->new_cleared_cache()->is_size_aware(),
        "not size aware by default" );
    ok( $self->new_cleared_cache( is_size_aware => 1 )->is_size_aware(),
        "is_size_aware turns on size awareness" );
    ok( $self->new_cleared_cache( max_size => 10 )->is_size_aware(),
        "max_size turns on size awareness" );

    my $cache = $self->new_cleared_cache( is_size_aware => 1 );
    is( $cache->get_size(), 0, "size is 0 for empty" );
    $cache->set( $key, $value );
    is_about( $cache->get_size, 20, "size is about 20 with one value" );
    $cache->set( $key, scalar( $value x 5 ) );
    is_about( $cache->get_size, 45, "size is 45 after overwrite" );
    $cache->set( $key, scalar( $value x 5 ) );
    is_about( $cache->get_size, 45, "size is still 45 after same overwrite" );
    $cache->set( $key, scalar( $value x 2 ) );
    is_about( $cache->get_size, 26, "size is 26 after overwrite" );
    $cache->remove($key);
    is( $cache->get_size, 0, "size is 0 again after removing key" );
    $cache->set( $key, $value );
    is_about( $cache->get_size, 20, "size is about 20 with one value" );
    $cache->clear();
    is( $cache->get_size, 0, "size is 0 again after clear" );

    my $time = time() + 10;
    $cache->set( $key, $value, { expires_at => $time } );
    is( $cache->get_expires_at($key),
        $time, "set options respected by size aware cache" );
}

sub test_max_size : Tests {
    my $self = shift;

    is( $self->new_cache( max_size => '30k' )->max_size,
        30 * 1024, 'max_size parsing' );

    my $cache = $self->new_cleared_cache( max_size => 99 );
    ok( $cache->is_size_aware, "is size aware when max_size specified" );
    my $value_20 = 'x' x 6;

    for ( my $i = 0 ; $i < 5 ; $i++ ) {
        $cache->set( "key$i", $value_20 );
    }
    for ( my $i = 0 ; $i < 10 ; $i++ ) {
        $cache->set( "key" . int( rand(10) ), $value_20 );
        is_between( $cache->get_size, 60, 99,
            "after iteration $i, size = " . $cache->get_size );
        is_between( scalar( $cache->get_keys ),
            3, 5, "after iteration $i, keys = " . scalar( $cache->get_keys ) );
    }
}

sub test_max_size_with_l1_cache : Tests {
    my $self = shift;

    my $cache = $self->new_cleared_cache(
        l1_cache => { driver => 'Memory', datastore => {}, max_size => 99 } );
    my $l1_cache = $cache->l1_cache;
    ok( $l1_cache->is_size_aware, "is size aware when max_size specified" );
    my $value_20 = 'x' x 6;

    my @keys = map { "key$_" } ( 0 .. 9 );
    my @shuffle_keys = shuffle(@keys);
    for ( my $i = 0 ; $i < 5 ; $i++ ) {
        $cache->set( "key$i", $value_20 );
    }
    for ( my $i = 0 ; $i < 10 ; $i++ ) {
        my $key = $shuffle_keys[$i];
        $cache->set( $key, $value_20 );
        is_between( $l1_cache->get_size, 60, 99,
            "after iteration $i, size = " . $l1_cache->get_size );
        is_between( scalar( $l1_cache->get_keys ),
            3, 5,
            "after iteration $i, keys = " . scalar( $l1_cache->get_keys ) );
    }
    cmp_deeply( [ sort $cache->get_keys ],
        \@keys, "primary cache still has all keys" );

    # Now test population by writeback
    $l1_cache->clear();
    is( $l1_cache->get_size, 0, "l1 size is 0 after clear" );
    for ( my $i = 0 ; $i < 5 ; $i++ ) {
        $cache->get("key$i");
    }
    for ( my $i = 0 ; $i < 10 ; $i++ ) {
        my $key = $shuffle_keys[$i];
        $cache->get($key);
        is_between( $l1_cache->get_size, 60, 99,
            "after iteration $i, size = " . $l1_cache->get_size );
        is_between( scalar( $l1_cache->get_keys ),
            3, 5,
            "after iteration $i, keys = " . scalar( $l1_cache->get_keys ) );
    }
}

sub test_custom_discard_policy : Tests {
    my $self          = shift;
    my $value_20      = 'x' x 6;
    my $highest_first = sub {
        my $c           = shift;
        my @sorted_keys = sort( $c->get_keys );
        return sub { pop(@sorted_keys) };
    };
    my $cache = $self->new_cleared_cache(
        is_size_aware  => 1,
        discard_policy => $highest_first
    );
    for ( my $j = 0 ; $j < 10 ; $j += 2 ) {
        $cache->clear();
        for ( my $i = 0 ; $i < 10 ; $i++ ) {
            my $k = ( $i + $j ) % 10;
            $cache->set( "key$k", $value_20 );
        }
        $cache->discard_to_size(100);
        cmp_set(
            [ $cache->get_keys ],
            [ map { "key$_" } ( 0 .. 4 ) ],
            "5 lowest"
        );
        $cache->discard_to_size(20);
        cmp_set( [ $cache->get_keys ], ["key0"], "1 lowest" );
    }
}

sub test_discard_timeout : Tests {
    my $self = shift;
    return 'author testing only' unless ( $ENV{AUTHOR_TESTING} );

    my $bad_policy = sub {
        return sub { '1' };
    };
    my $cache = $self->new_cleared_cache(
        is_size_aware  => 1,
        discard_policy => $bad_policy
    );
    ok( defined( $cache->discard_timeout ) && $cache->discard_timeout > 1,
        "positive discard timeout" );
    $cache->discard_timeout(1);
    is( $cache->discard_timeout, 1, "can set timeout" );
    my $start_time = time;
    $cache->set( 2, 2 );
    throws_ok { $cache->discard_to_size(0) } qr/discard timeout .* reached/;
    ok(
        time >= $start_time && time <= $start_time + 4,
        sprintf(
            "time (%d) is between %d and %d",
            time, $start_time, $start_time + 4
        )
    );
}

sub test_size_awareness_with_subcaches : Tests {
    my $self = shift;

    my ( $cache, $l1_cache );
    my $set_values = sub {
        my $value_20 = 'x' x 6;
        for ( my $i = 0 ; $i < 20 ; $i++ ) {
            $cache->set( "key$i", $value_20 );
        }
        $l1_cache = $cache->l1_cache;
    };
    my $is_size_aware = sub {
        my $c     = shift;
        my $label = $c->label;

        ok( $c->is_size_aware, "$label is size aware" );
        my $max_size = $c->max_size;
        ok( $max_size > 0, "$label has max size" );
        is_between( $c->get_size, $max_size - 40,
            $max_size, "$label size = " . $c->get_size );
        is_between(
            scalar( $c->get_keys ),
            ( $max_size + 1 ) / 20 - 2,
            ( $max_size + 1 ) / 20,
            "$label keys = " . scalar( $c->get_keys )
        );
    };
    my $is_not_size_aware = sub {
        my $c     = shift;
        my $label = $c->label;

        ok( !$c->is_size_aware, "$label is not size aware" );
        is( $c->get_keys, 20, "$label keys = 20" );
    };

    $cache = $self->new_cleared_cache(
        l1_cache => { driver => 'Memory', datastore => {}, max_size => 99 } );
    $set_values->();
    $is_not_size_aware->($cache);
    $is_size_aware->($l1_cache);

    $cache = $self->new_cleared_cache(
        l1_cache => { driver => 'Memory', datastore => {}, max_size => 99 },
        max_size => 199
    );
    $set_values->();
    $is_size_aware->($cache);
    $is_size_aware->($l1_cache);

    $cache = $self->new_cleared_cache(
        l1_cache => { driver => 'Memory', datastore => {} },
        max_size => 199
    );
    $set_values->();
    $is_size_aware->($cache);

    # Cannot call is_not_size_aware because the get_keys check will
    # fail. Keys will be removed from the l1_cache when they are removed
    # from the main cache, even though l1_cache does not have a max
    # size. Not sure if this is the correct behavior, but for now, we're not
    # going to test it. Normally, l1 caches will be more size limited than
    # their parent caches.
    #
    ok( !$l1_cache->is_size_aware, $l1_cache->label . " is not size aware" );
}

sub is_about {
    my ( $value, $expected, $msg ) = @_;

    my $margin = int( $expected * 0.1 );
    if ( abs( $value - $expected ) <= $margin ) {
        pass($msg);
    }
    else {
        fail("$msg - got $value, expected $expected");
    }
}

sub test_busy_lock : Tests {
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

sub test_obj_ref : Tests {
    my $self = shift;

    # Make sure obj_ref works in conjunction with subcaches too
    my $cache =
      $self->new_cache( l1_cache => { driver => 'Memory', datastore => {} } );
    my $obj;
    my ( $key, $value ) = ( 'medium', [ a => 5, b => 6 ] );

    my $validate_obj = sub {
        isa_ok( $obj, 'CHI::CacheObject' );
        is( $obj->key, $key, "keys match" );
        cmp_deeply( $obj->value, $value, "values match" );
    };

    $cache->get( $key, obj_ref => \$obj );
    ok( !defined($obj), "obj not defined on miss" );
    $cache->set( $key, $value, { obj_ref => \$obj } );
    $validate_obj->();
    undef $obj;
    ok( !defined($obj), "obj not defined before get" );
    $cache->get( $key, obj_ref => \$obj );
    $validate_obj->();
}

sub test_metacache : Tests {
    my $self  = shift;
    my $cache = $self->{cache};

    ok( !defined( $cache->{metacache} ), "metacache is lazy" );
    $cache->metacache->set( 'foo', 5 );
    ok( defined( $cache->{metacache} ), "metacache autovivified" );
    is( $cache->metacache->get('foo'), 5 );
}

sub test_scalar_return_values : Tests {
    my $self  = shift;
    my $cache = $self->{cache};

    my $check = sub {
        my ($code)        = @_;
        my $scalar_result = $code->();
        my @list          = $code->();
        cmp_deeply( \@list, [$scalar_result] );
    };

    $check->( sub { $cache->fetch('a') } );
    $check->( sub { $cache->get('a') } );
    $check->( sub { $cache->set( 'a', 5 ) } );
    $check->( sub { $cache->fetch('a') } );
    $check->( sub { $cache->get('a') } );
}

sub test_no_leak : Tests {
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

Class::MOP::Class->create( 'My::CHI' => ( superclasses => ['CHI'] ) );

sub test_driver_properties : Tests {
    my $self  = shift;
    my $cache = $self->{cache};

    is( $cache->chi_root_class, 'CHI', 'chi_root_class=CHI' );
    my $cache2 = My::CHI->new( $self->new_cache_options() );
    is( $cache2->chi_root_class, 'My::CHI', 'chi_root_class=My::CHI' );
}

sub test_missing_params : Tests {
    my $self  = shift;
    my $cache = $self->{cache};

    # These methods require a key
    foreach my $method (
        qw(get get_object get_expires_at exists_and_is_expired is_valid set expire compute get_multi_arrayref get_multi_hashref set_multi remove_multi)
      )
    {
        throws_ok(
            sub { $cache->$method() },
            qr/must specify key/,
            "$method throws error when no key passed"
        );
    }
}

sub test_compute : Tests {
    my $self  = shift;
    my $cache = $self->{cache};

    # Test current arg order and pre-0.40 arg order
    foreach my $iter ( 0 .. 1 ) {
        my $count       = 5;
        my $expire_time = time + 10;
        my @args1       = ( { expires_at => $expire_time }, sub { $count++ } );
        my @args2       = (
            {
                expire_if => sub { 1 }
            },
            sub { $count++ }
        );
        if ($iter) {
            @args1 = reverse(@args1);
            @args2 = reverse(@args2);
        }
        $cache->clear;
        is( $cache->get('foo'), undef, "miss" );
        is( $cache->compute( 'foo', @args1 ), 5, "compute - 5" );
        is( $cache->get('foo'), 5, "hit - 5" );
        is( $cache->get_object('foo')->expires_at, $expire_time,
            "expire time" );
        is( $cache->compute( 'foo', @args2 ), 6, "compute - 6" );
        is( $cache->get('foo'), 6, "hit - 6" );
    }

    # Test wantarray
    $cache->clear();
    my $compute_list = sub {
        $cache->compute( 'foo', {}, sub { ( int( rand(10000) ) ) x 5 } );
    };
    my @list1 = $compute_list->();
    my @list2 = $compute_list->();
    is( scalar(@list1), 5, "list has 5 items" );
    cmp_deeply( \@list1, \@list2, "lists are the same" );
}

sub test_compress_threshold : Tests {
    my $self  = shift;
    my $cache = $self->{cache};

    my $s0 = 'x' x 180;
    my $s1 = 'x' x 200;
    $cache->set( 'key0', $s0 );
    $cache->set( 'key1', $s1 );
    is_between( $cache->get_object('key0')->size, 180, 220 );
    is_between( $cache->get_object('key1')->size, 200, 240 );

    my $cache2 = $self->new_cache( compress_threshold => 190 );
    $cache2->set( 'key0', $s0 );
    $cache2->set( 'key1', $s1 );
    is_between( $cache2->get_object('key0')->size, 180, 220 );
    ok( $cache2->get_object('key1')->size < 100 );
    is( $cache2->get('key0'), $s0 );
    is( $cache2->get('key1'), $s1 );
}

sub test_expires_on_backend : Tests {
    my $self = shift;

    return "skipping - no support for expires_on_backend"
      unless $self->supports_expires_on_backend();
    foreach my $expires_on_backend ( 0, 1 ) {
        my $cache =
          $self->new_cache( expires_on_backend => $expires_on_backend );
        $cache->set( 'key0', 5, '2s' );
        $cache->set( 'key1', 6, { expires_at => time + 2 } );
        is( $cache->get('key0'), 5, 'hit key0 before expire' );
        is( $cache->get('key1'), 6, 'hit key1 before expire' );
        sleep(3);
        ok( !defined( $cache->get('key0') ), 'miss key0 after expire' );
        ok( !defined( $cache->get('key1') ), 'miss key1 after expire' );

        if ($expires_on_backend) {
            ok(
                !defined( $cache->get_object('key0') ),
                'cannot get_object(key0) after expire'
            );
            ok(
                !defined( $cache->get_object('key1') ),
                'cannot get_object(key1) after expire'
            );
        }
        else {
            ok(
                $cache->get_object('key0')->is_expired(),
                'can get_object(key0) after expire'
            );
            ok(
                $cache->get_object('key1')->is_expired(),
                'can get_object(key1) after expire'
            );
        }
    }
}

sub test_append : Tests {
    my $self  = shift;
    my $cache = $self->{cache};
    my ( $key, $value ) =
      ( $self->{keys}->{arrayref}, $self->{values}->{medium} );

    # Appending to non-existent key has no effect
    #
    $cache->append( $key, $value );
    ok( !$cache->get($key) );

    ok( $cache->set( $key, $value ) );
    $cache->append( $key, $value );
    is( $cache->get($key), $value . $value );
    $cache->append( $key, $value );
    is( $cache->get($key), $value . $value . $value );
}

sub test_add : Tests {
    my $self  = shift;
    my $cache = $self->{cache};
    my ( $key, $value ) =
      ( $self->{keys}->{arrayref}, $self->{values}->{medium} );

    my $t = time();

    $cache->add( $key, $value, { expires_at => $t + 100 } );
    is( $cache->get($key),                    $value,   "get" );
    is( $cache->get_object($key)->expires_at, $t + 100, "expires_at" );

    $cache->add( $key, $value . $value, { expires_at => $t + 200 } );
    is( $cache->get($key), $value, "get (after add)" );
    is( $cache->get_object($key)->expires_at,
        $t + 100, "expires_at (after add)" );

    $cache->remove($key);
    $cache->add( $key, $value . $value, { expires_at => $t + 200 } );
    is( $cache->get($key), $value . $value, "get (after expire and add)" );
    is( $cache->get_object($key)->expires_at,
        $t + 200, "expires_at (after expire and add)" );
}

sub test_replace : Tests {
    my $self  = shift;
    my $cache = $self->{cache};
    my ( $key, $value ) =
      ( $self->{keys}->{arrayref}, $self->{values}->{medium} );

    my $t = time();

    $cache->replace( $key, $value, { expires_at => $t + 100 } );
    ok( !$cache->get_object($key), "get" );

    $cache->set( $key, $value . $value, { expires_at => $t + 200 } );
    $cache->replace( $key, $value, { expires_at => $t + 100 } );
    is( $cache->get($key), $value, "get (after replace)" );
    is( $cache->get_object($key)->expires_at,
        $t + 100, "expires_at (after replace)" );
}

sub test_max_key_length : Tests {
    my $self = shift;

    # Test max_key_length and also that key does not get transformed twice in mirror_cache
    #
    my $mirror_store = {};
    my $cache        = $self->new_cleared_cache(
        max_key_length => 10,
        mirror_cache   => { driver => 'Memory', datastore => $mirror_store }
    );

    foreach my $keyname ( 'medium', 'large' ) {
        my ( $key, $value ) =
          ( $self->{keys}->{$keyname}, $self->{values}->{$keyname} );
        $cache->set( $key, $value );
        is( $cache->get($key),               $value, $keyname );
        is( $cache->mirror_cache->get($key), $value, $keyname );
        if ( $keyname eq 'medium' ) {
            is( $cache->get_object($key)->key(), $key, "medium key stored" );
        }
        else {
            isnt( $cache->get_object($key)->key(), $key, "md5 key stored" );
            is( length( $cache->get_object($key)->key() ),
                32, "md5 key stored" );
        }
    }
}

# Test that cache does not get corrupted with multiple concurrent processes writing
#
sub test_multiple_processes : Tests {
    my $self = shift;
    return "author test only" unless $ENV{AUTHOR_TESTING};
    return "does not pass on file driver"
      if $self->new_cache->short_driver_name eq 'File';

    my ( @values, @pids, %valid_values );
    my $shared_key = $self->{keys}->{medium};
    my $num_procs  = 4;

    local $SIG{CHLD} = 'IGNORE';

    # Each child continuously writes a unique 10000 byte string to a single shared key
    #
    my $child_action = sub {
        my $p           = shift;
        my $value       = $values[$p];
        my $child_cache = $self->new_cache();

        sleep(1);    # Wait for parent to be ready
        my $child_end_time = time() + 5;
        while ( time < $child_end_time ) {
            $child_cache->set( $shared_key, $value );
        }
        $child_cache->set( "done$p", 1 );
    };

    foreach my $p ( 0 .. $num_procs ) {
        $values[$p] = random_string(10000);
        $valid_values{ $values[$p] } = $p;
        if ( my $pid = fork() ) {
            $pids[$p] = $pid;
        }
        else {
            $child_action->($p);
            exit;
        }
    }

    # Parent continuously gets shared key, makes sure it is one of the valid values.
    # Loop until we see done flag for each child process, or until 10 secs pass.
    # At end make sure we saw each process's value once.
    #
    my ( %seen, $error );
    my $parent_end_time = time() + 10;
    my $parent_cache    = $self->new_cache();
    while ( !$error ) {
        for ( my $i = 0 ; $i < 100 ; $i++ ) {
            my $value = $parent_cache->get($shared_key);
            if ( defined($value) ) {
                if ( defined( my $p = $valid_values{$value} ) ) {
                    $seen{$p} = 1;
                }
                else {
                    $error = "got invalid value '$value' from shared key";
                    last;
                }
            }
        }
        if ( !grep { !$parent_cache->get("done$_") } ( 0 .. $num_procs ) ) {
            last;
        }
        if ( time() >= $parent_end_time ) {
            $error = "did not see all done flags after 10 secs";
        }
    }

    if ( !$error ) {
        if ( my ($p) = grep { !$seen{$_} } ( 0 .. $num_procs ) ) {
            $error = "never saw value from process $p";
        }
    }

    if ($error) {
        ok( 0, $error );
    }
    else {
        ok( 1, "passed" );
    }
}

1;
