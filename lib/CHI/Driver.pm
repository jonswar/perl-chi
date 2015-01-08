package CHI::Driver;

use Carp;
use CHI::CacheObject;
use CHI::Constants qw(CHI_Max_Time);
use CHI::Driver::Metacache;
use CHI::Driver::Role::HasSubcaches;
use CHI::Driver::Role::IsSizeAware;
use CHI::Driver::Role::IsSubcache;
use CHI::Driver::Role::Universal;
use CHI::Serializer::Storable;
use CHI::Serializer::JSON;
use CHI::Util qw(parse_duration);
use CHI::Types qw(:all);
use Digest::MD5;
use Encode;
use Hash::MoreUtils qw(slice_grep);
use Log::Any qw($log);
use Moo;
use MooX::Types::MooseLike::Base qw(:all);
use Scalar::Util qw(blessed);
use Time::Duration;
use Time::HiRes qw(gettimeofday);
use strict;
use warnings;

my $default_serializer     = CHI::Serializer::Storable->new();
my $default_key_serializer = CHI::Serializer::JSON->new();
my $default_key_digester   = Digest::MD5->new();

my @common_params;
{
    my %attr = (
        chi_root_class => {
            is => 'ro',
        },
        compress_threshold => {
            is  => 'ro',
            isa => Int,
        },
        constructor_params => {
            is       => 'ro',
            init_arg => undef,
        },
        driver_class => {
            is => 'ro',
        },
        expires_at => {
            is      => 'rw',
            default => sub { CHI_Max_Time },
        },
        expires_in => {
            is     => 'rw',
            isa    => Duration,
            coerce => \&to_Duration,
        },
        expires_on_backend => {
            is      => 'ro',
            isa     => Num,
            default => sub { 0 },
        },
        expires_variance => {
            is      => 'rw',
            isa     => Num,
            default => sub { 0 },
        },
        has_subcaches => {
            is       => 'lazy',
            isa      => Bool,
            init_arg => undef,
        },
        is_size_aware => {
            is  => 'ro',
            isa => Bool,
        },
        is_subcache => {
            is  => 'ro',
            isa => Bool,
        },
        key_digester => {
            is      => 'ro',
            isa     => Digester,
            coerce  => \&to_Digester,
            default => sub { $default_key_digester },
        },
        key_serializer => {
            is      => 'ro',
            isa     => Serializer,
            coerce  => \&to_Serializer,
            default => sub { $default_key_serializer },
        },
        label => {
            is        => 'rw',
            lazy      => 1,
            builder   => 1,
            clearer   => 1,
            predicate => 1,
        },
        max_build_depth => {
            is      => 'ro',
            default => sub { 8 },
        },
        max_key_length => {
            is      => 'ro',
            isa     => Int,
            default => sub { 1 << 31 },
        },
        metacache => {
            is        => 'lazy',
            clearer   => 1,
            predicate => 1,
        },
        namespace => {
            is      => 'ro',
            isa     => Str,
            default => sub { 'Default' },
        },
        on_get_error => {
            is      => 'rw',
            isa     => OnError,
            default => sub { 'log' },
        },
        on_set_error => {
            is      => 'rw',
            isa     => OnError,
            default => sub { 'log' },
        },
        serializer => {
            is      => 'ro',
            isa     => Serializer,
            coerce  => \&to_Serializer,
            default => sub { $default_serializer },
        },
        short_driver_name => {
            is        => 'lazy',
            clearer   => 1,
            predicate => 1,
        },
        storage => {
            is => 'ro',
        },
    );
    push @common_params, keys %attr;
    for my $attr ( keys %attr ) {
        has $attr => %{ $attr{$attr} };
    }
}

sub _build_has_subcaches { undef }

# These methods must be implemented by subclass
foreach my $method (qw(fetch store remove get_keys get_namespaces)) {
    no strict 'refs';
    *{$method} = sub { die "method '$method' must be implemented by subclass" };
}

# Given a hash of params, return the subset that are not in CHI's common parameters.
#
push @common_params, qw(
  discard_policy
  discard_timeout
  l1_cache
  max_size
  max_size_reduction_factor
  mirror_cache
  parent_cache
  subcache_type
  subcaches
);
my %common_params = map { ( $_, 1 ) } @common_params;

sub non_common_constructor_params {
    my ( $class, $params ) = @_;

    return {
        map { ( $_, $params->{$_} ) }
        grep { !$common_params{$_} } keys(%$params)
    };
}

sub declare_unsupported_methods {
    my ( $class, @methods ) = @_;

    foreach my $method (@methods) {
        no strict 'refs';
        *{"$class\::$method"} =
          sub { croak "method '$method' not supported by '$class'" };
    }
}

sub cache_object_class { 'CHI::CacheObject' }

# To override time() for testing - must be writable in a dynamically scoped way from tests
our $Test_Time;    ## no critic (ProhibitPackageVars)
our $Build_Depth = 0;    ## no critic (ProhibitPackageVars)

sub valid_get_options { qw(expire_if busy_lock) }
sub valid_set_options { qw(expires_at expires_in expires_variance) }

sub BUILD {
    my ( $self, $params ) = @_;

    # Ward off infinite build recursion, e.g. from circular subcache configuration.
    #
    local $Build_Depth = $Build_Depth + 1;
    die "$Build_Depth levels of CHI cache creation; infinite recursion?"
      if ( $Build_Depth > $self->max_build_depth );

    # Save off constructor params. Used to create metacache, for
    # example. Hopefully this will not cause circular references...
    #
    $self->{constructor_params} = {%$params};
    foreach my $param (qw(l1_cache mirror_cache parent_cache)) {
        delete( $self->{constructor_params}->{$param} );
    }

    # If stats enabled, add ns_stats slot for keeping track of stats
    #
    my $stats = $self->chi_root_class->stats;
    if ( $stats->enabled ) {
        $self->{ns_stats} = $stats->stats_for_driver($self);
    }

    # Call BUILD_roles on any of the roles that need initialization.
    #
    $self->BUILD_roles($params);
}

sub BUILD_roles {

    # Will be modified by roles that need it
}

sub _build_short_driver_name {
    my ($self) = @_;

    ( my $name = $self->driver_class ) =~ s/^CHI::Driver:://;

    return $name;
}

sub _build_label {
    my ($self) = @_;

    return $self->short_driver_name;
}

sub _build_metacache {
    my $self = shift;

    return CHI::Driver::Metacache->new( owner_cache => $self );
}

sub get {
    my ( $self, $key, %params ) = @_;

    croak "must specify key" unless defined($key);
    my $ns_stats     = $self->{ns_stats};
    my $log_is_debug = $log->is_debug;
    my $measure_time = defined($ns_stats) || $log_is_debug;
    my ( $start_time, $elapsed_time );

    # Fetch cache object
    #
    $start_time = gettimeofday() if $measure_time;
    my $obj = eval { $params{obj} || $self->get_object($key) };
    $elapsed_time = ( gettimeofday() - $start_time ) * 1000 if $measure_time;
    if ( my $error = $@ ) {
        $ns_stats->{'get_errors'}++ if defined($ns_stats);
        $self->_handle_get_error( $error, $key );
        return undef;
    }
    if ( !defined $obj ) {
        $self->_record_get_stats( 'absent_misses', $elapsed_time )
          if defined($ns_stats);
        $self->_log_get_result( $log, "MISS (not in cache)",
            $key, $elapsed_time )
          if $log_is_debug;
        return undef;
    }
    if ( defined( my $obj_ref = $params{obj_ref} ) ) {
        $$obj_ref = $obj;
    }

    # Check if expired
    #
    my $is_expired = $obj->is_expired()
      || ( defined( $params{expire_if} ) && $params{expire_if}->($obj, $self) );
    if ($is_expired) {
        $self->_record_get_stats( 'expired_misses', $elapsed_time )
          if defined($ns_stats);
        $self->_log_get_result( $log, "MISS (expired)", $key, $elapsed_time )
          if $log_is_debug;

        # If busy_lock value provided, set a new "temporary" expiration time that many
        # seconds forward before returning undef
        #
        if ( defined( my $busy_lock = $params{busy_lock} ) ) {
            my $time = $Test_Time || time();
            my $busy_lock_time = $time + parse_duration($busy_lock);
            $obj->set_early_expires_at($busy_lock_time);
            $obj->set_expires_at($busy_lock_time);
            $self->set_object( $key, $obj );
        }

        return undef;
    }

    $self->_record_get_stats( 'hits', $elapsed_time ) if defined($ns_stats);
    $self->_log_get_result( $log, "HIT", $key, $elapsed_time ) if $log_is_debug;
    return $obj->value;
}

sub _record_get_stats {
    my ( $self, $stat, $elapsed_time ) = @_;
    $self->{ns_stats}->{$stat}++;
    $self->{ns_stats}->{'get_time_ms'} += $elapsed_time;
}

sub unpack_from_data {
    my ( $self, $key, $data ) = @_;

    return $self->cache_object_class->unpack_from_data( $key, $data,
        $self->serializer );
}

sub get_object {
    my ( $self, $key ) = @_;

    croak "must specify key" unless defined($key);
    $key = $self->transform_key($key);

    my $data = $self->fetch($key) or return undef;
    my $obj = $self->unpack_from_data( $key, $data );
    return $obj;
}

sub get_expires_at {
    my ( $self, $key ) = @_;
    croak "must specify key" unless defined($key);

    if ( my $obj = $self->get_object($key) ) {
        return $obj->expires_at;
    }
    else {
        return;
    }
}

sub exists_and_is_expired {
    my ( $self, $key ) = @_;
    croak "must specify key" unless defined($key);

    if ( my $obj = $self->get_object($key) ) {
        return $obj->is_expired;
    }
    else {
        return;
    }
}

sub is_valid {
    my ( $self, $key ) = @_;
    croak "must specify key" unless defined($key);

    if ( my $obj = $self->get_object($key) ) {
        return !$obj->is_expired;
    }
    else {
        return;
    }
}

sub _default_set_options {
    my $self = shift;

    return { map { $_ => $self->$_() }
          qw( expires_at expires_in expires_variance ) };
}

sub set {
    my $self = shift;
    my ( $key, $value, $options ) = @_;

    croak "must specify key" unless defined($key);
    $key = $self->transform_key($key);
    return unless defined($value);

    # Fill in $options if not passed, copy if passed, and apply defaults.
    #
    if ( !defined($options) ) {
        $options = $self->_default_set_options;
    }
    else {
        if ( !ref($options) ) {
            if ( $options eq 'never' ) {
                $options = { expires_at => CHI_Max_Time };
            }
            elsif ( $options eq 'now' ) {
                $options = { expires_in => 0 };
            }
            else {
                $options = { expires_in => $options };
            }
        }

        # Disregard default expires_at and expires_in if either are provided
        #
        if (   exists( $options->{expires_at} )
            || exists( $options->{expires_in} ) )
        {
            $options =
              { expires_variance => $self->expires_variance, %$options };
        }
        else {
            $options = { %{ $self->_default_set_options }, %$options };
        }
    }

    $self->set_with_options( $key, $value, $options );
}

sub set_with_options {
    my ( $self, $key, $value, $options ) = @_;
    my $ns_stats     = $self->{ns_stats};
    my $log_is_debug = $log->is_debug;
    my $measure_time = defined($ns_stats) || $log_is_debug;
    my ( $start_time, $elapsed_time );

    # Determine early and final expiration times
    #
    my $time = $Test_Time || time();
    my $created_at = $time;
    my $expires_at =
      ( defined( $options->{expires_in} ) )
      ? $time + parse_duration( $options->{expires_in} )
      : $options->{expires_at};
    my $early_expires_at =
        defined( $options->{early_expires_at} ) ? $options->{early_expires_at}
      : ( $expires_at == CHI_Max_Time )         ? CHI_Max_Time
      : $expires_at -
      ( ( $expires_at - $time ) * $options->{expires_variance} );

    # Pack into data, and store
    #
    my $obj =
      $self->cache_object_class->new( $key, $value, $created_at,
        $early_expires_at, $expires_at, $self->serializer,
        $self->compress_threshold );
    if ( defined( my $obj_ref = $options->{obj_ref} ) ) {
        $$obj_ref = $obj;
    }
    $start_time = gettimeofday() if $measure_time;
    if ( $self->set_object( $key, $obj ) ) {
        $elapsed_time = ( gettimeofday() - $start_time ) * 1000
          if $measure_time;

        # Log the set
        #
        if ( defined($ns_stats) ) {
            $ns_stats->{'sets'}++;
            $ns_stats->{'set_key_size'}   += length( $obj->key );
            $ns_stats->{'set_value_size'} += $obj->size;
            $ns_stats->{'set_time_ms'}    += $elapsed_time;
        }
        if ($log_is_debug) {
            $self->_log_set_result( $log, $obj, $elapsed_time );
        }
    }

    return $value;
}

sub set_object {
    my ( $self, $key, $obj ) = @_;

    my $data               = $obj->pack_to_data();
    my $expires_on_backend = $self->expires_on_backend;
    my @expires_in         = (
        $expires_on_backend && $obj->expires_at < CHI_Max_Time
        ? ( ( $obj->expires_at - time ) * $expires_on_backend )
        : ()
    );
    eval { $self->store( $key, $data, @expires_in ) };
    if ( my $error = $@ ) {
        $self->{ns_stats}->{'set_errors'}++ if defined( $self->{ns_stats} );
        $self->_handle_set_error( $error, $obj );
        return 0;
    }
    return 1;
}

sub get_keys_iterator {
    my ($self) = @_;

    my @keys = $self->get_keys();
    return sub { shift(@keys) };
}

sub clear {
    my $self = shift;
    die "clear takes no arguments" if @_;

    $self->remove_multi( [ $self->get_keys() ] );
}

sub expire {
    my ( $self, $key ) = @_;
    croak "must specify key" unless defined($key);

    my $time = $Test_Time || time();
    if ( defined( my $obj = $self->get_object($key) ) ) {
        my $expires_at = $time - 1;
        $obj->set_early_expires_at($expires_at);
        $obj->set_expires_at($expires_at);
        $self->set_object( $key, $obj );
    }
}

sub compute {
    my $self      = shift;
    my $key       = shift;
    my $wantarray = wantarray();

    # Allow these in either order for backward compatibility
    my ( $code, $options ) =
      ( ref( $_[0] ) eq 'CODE' ) ? ( $_[0], $_[1] ) : ( $_[1], $_[0] );

    croak "must specify key and code" unless defined($key) && defined($code);

    my %get_options =
      ( ref($options) eq 'HASH' )
      ? slice_grep { /(?:expire_if|busy_lock)/ } $options
      : ();
    my $set_options =
        ( ref($options) eq 'HASH' )
      ? { slice_grep { !/(?:expire_if|busy_lock)/ } $options }
      : $options;

    my $value = $self->get( $key, %get_options );
    if ( !defined $value ) {
        my ( $start_time, $elapsed_time );
        my $ns_stats = $self->{ns_stats};
        $start_time = gettimeofday if defined($ns_stats);
        $value = $wantarray ? [ $code->() ] : $code->();
        $elapsed_time = ( gettimeofday() - $start_time ) * 1000
          if defined($ns_stats);
        $self->set( $key, $value, $set_options );
        if ( defined($ns_stats) ) {
            $ns_stats->{'computes'}++;
            $ns_stats->{'compute_time_ms'} += $elapsed_time;
        }
    }
    return $wantarray ? @$value : $value;
}

sub purge {
    my ($self) = @_;

    foreach my $key ( $self->get_keys() ) {
        if ( my $obj = $self->get_object($key) ) {
            if ( $obj->is_expired() ) {
                $self->remove($key);
            }
        }
    }
}

sub dump_as_hash {
    my ($self) = @_;

    my %hash;
    foreach my $key ( $self->get_keys() ) {
        if ( defined( my $value = $self->get($key) ) ) {
            $hash{$key} = $value;
        }
    }
    return \%hash;
}

sub is_empty {
    my ($self) = @_;

    return !$self->get_keys();
}

#
# (SEMI-) ATOMIC OPERATIONS
#

sub add {
    my $self = shift;
    my $key  = shift;

    if ( !$self->is_valid($key) ) {
        $self->set( $key, @_ );
    }
}

sub append {
    my ( $self, $key, $new ) = @_;

    my $current = $self->fetch($key) or return undef;
    $self->store( $key, $current . $new );
    return 1;
}

sub replace {
    my $self = shift;
    my $key  = shift;

    if ( $self->is_valid($key) ) {
        $self->set( $key, @_ );
    }
}

#
# MULTI KEY OPERATIONS
#

sub fetch_multi_hashref {
    my ( $self, $keys ) = @_;

    return { map { ( $_, $self->fetch($_) ) } @$keys };
}

sub get_multi_hashref_objects {
    my ( $self, $keys ) = @_;
    my $key_data = $self->fetch_multi_hashref($keys);
    return {
        map {
            my $data = $key_data->{$_};
            defined($data)
              ? ( $_, $self->unpack_from_data( $_, $data ) )
              : ( $_, undef )
        } keys(%$key_data)
    };
}

sub get_multi_arrayref {
    my ( $self, $keys ) = @_;
    croak "must specify keys" unless defined($keys);
    my $transformed_keys = [ map { $self->transform_key($_) } @$keys ];

    my $key_count = scalar(@$keys);
    my $keyobjs   = $self->get_multi_hashref_objects($transformed_keys);
    return [
        map {
            my $key = $transformed_keys->[$_];
            my $obj = $keyobjs->{$key};
            $obj ? $self->get( $key, obj => $obj ) : undef
        } ( 0 .. $key_count - 1 )
    ];
}

sub get_multi_hashref {
    my ( $self, $keys ) = @_;
    croak "must specify keys" unless defined($keys);

    my $key_count = scalar(@$keys);
    my $values    = $self->get_multi_arrayref($keys);
    return { map { ( $keys->[$_], $values->[$_] ) } ( 0 .. $key_count - 1 ) };
}

sub set_multi {
    my $self = shift;
    $self->store_multi(@_);
}

sub store_multi {
    my ( $self, $key_values, $set_options ) = @_;
    croak "must specify key_values" unless defined($key_values);

    while ( my ( $key, $value ) = each(%$key_values) ) {
        $self->set( $key, $value, $set_options );
    }
}

sub remove_multi {
    my ( $self, $keys ) = @_;
    croak "must specify keys" unless defined($keys);

    foreach my $key (@$keys) {
        $self->remove($key);
    }
}

#
# KEY TRANSFORMATION
#

my %escapes;
for ( 0 .. 255 ) {
    $escapes{ chr($_) } = sprintf( "+%02x", $_ );
}
my $_fail_hi = sub {
    croak( sprintf "Can't escape multibyte character \\x{%04X}", ord( $_[0] ) );
};

sub transform_key {
    my ( $self, $key ) = @_;

    if ( ref($key) ) {
        $key = $self->key_serializer->serialize($key);
    }
    elsif ( Encode::is_utf8($key) && $key =~ /[^\x00-\xFF]/ ) {
        $key = $self->encode_key($key);
    }
    if ( length($key) > $self->max_key_length ) {
        $key = $self->digest_key($key);
    }

    return $key;
}

sub digest_key {
    my ( $self, $key ) = @_;

    return $self->key_digester->add($key)->hexdigest;
}

sub encode_key {
    my ( $self, $key ) = @_;

    return Encode::encode( utf8 => $key );
}

# These will be called by drivers if necessary, and in testing. By default
# no escaping/unescaping is necessary.
#
sub escape_key   { $_[1] }
sub unescape_key { $_[1] }

# May be used by drivers to implement escape_key/unescape_key.
#
sub escape_for_filename {
    my ( $self, $key ) = @_;

    $key =~ s/([^A-Za-z0-9_\=\-\~])/$escapes{$1} || $_fail_hi->($1)/ge;
    return $key;
}

sub unescape_for_filename {
    my ( $self, $key ) = @_;

    $key =~ s/\+([0-9A-Fa-f]{2})/chr(hex($1))/eg if defined $key;
    return $key;
}

sub is_escaped_for_filename {
    my ( $self, $key ) = @_;

    return $self->escape_for_filename( $self->unescape_for_filename($key) ) eq
      $key;
}

#
# LOGGING AND ERROR HANDLING
#

sub _log_get_result {
    my $self = shift;
    my $log  = shift;
    my $msg  = shift;
    $log->debug( sprintf( "%s: %s", $self->_describe_cache_get(@_), $msg ) );
}

sub _log_set_result {
    my $self = shift;
    my $log  = shift;
    $log->debug( $self->_describe_cache_set(@_) );
}

sub _handle_get_error {
    my $self  = shift;
    my $error = shift;
    my $key   = $_[0];

    my $msg =
      sprintf( "error during %s: %s", $self->_describe_cache_get(@_), $error );
    $self->_dispatch_error_msg( $msg, $error, $self->on_get_error(), $key );
}

sub _handle_set_error {
    my ( $self, $error, $obj ) = @_;

    my $msg =
      sprintf( "error during %s: %s", $self->_describe_cache_set($obj),
        $error );
    $self->_dispatch_error_msg( $msg, $error, $self->on_set_error(),
        $obj->key );
}

sub _dispatch_error_msg {
    my ( $self, $msg, $error, $on_error, $key ) = @_;

    for ($on_error) {
        ( ref($_) eq 'CODE' ) && do { $_->( $msg, $key, $error ) };
        /^log$/
          && do { $log->error($msg) };
        /^ignore$/ && do { };
        /^warn$/   && do { carp $msg };
        /^die$/    && do { croak $msg };
    }
}

sub _describe_cache_get {
    my ( $self, $key, $elapsed_time ) = @_;

    return
      sprintf( "cache get for namespace='%s', key='%s', cache='%s'"
          . ( defined($elapsed_time) ? ", time='%dms'" : "" ),
        $self->namespace, $key, $self->label,
        defined($elapsed_time) ? int($elapsed_time) : () );
}

sub _describe_cache_set {
    my ( $self, $obj, $elapsed_time ) = @_;

    my $expires_str = (
        ( $obj->expires_at == CHI_Max_Time )
        ? 'never'
        : Time::Duration::concise(
            Time::Duration::duration_exact(
                $obj->expires_at - $obj->created_at
            )
        )
    );

    return
      sprintf(
        "cache set for namespace='%s', key='%s', size=%d, expires='%s', cache='%s'"
          . ( defined($elapsed_time) ? ", time='%dms'" : "" ),
        $self->namespace, $obj->key, $obj->size, $expires_str, $self->label,
        defined($elapsed_time) ? int($elapsed_time) : () );

}

1;

__END__

=pod

=head1 NAME

CHI::Driver - Base class for all CHI drivers

=head1 DESCRIPTION

This is the base class that all CHI drivers inherit from. It provides the
methods that one calls on $cache handles, such as get() and set().

See L<CHI/METHODS> for documentation on $cache methods, and
L<CHI::Driver::Development|CHI::Driver::Development> for documentation on
creating new subclasses of CHI::Driver.

=cut
