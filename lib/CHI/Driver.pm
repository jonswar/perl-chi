package CHI::Driver;
use Carp;
use CHI::CacheObject;
use CHI::Driver::Metacache;
use CHI::Driver::Role::Universal;
use CHI::Serializer::Storable;
use CHI::Util
  qw(has_moose_class parse_duration parse_memory_size require_dynamic);
use Module::Load::Conditional qw(can_load);
use Moose;
use Moose::Util::TypeConstraints;
use Scalar::Util qw(blessed);
use Time::Duration;
use strict;
use warnings;

type OnError => where { ref($_) eq 'CODE' || /^(?:ignore|warn|die|log)$/ };

subtype 'CHI::Duration' => as 'Int' => where { $_ > 0 };
coerce 'CHI::Duration' => from 'Str' => via { parse_duration($_) };

subtype 'CHI::MemorySize' => as 'Int' => where { $_ > 0 };
coerce 'CHI::MemorySize' => from 'Str' => via { parse_memory_size($_) };

subtype 'CHI::UnblessedHashRef' => as 'HashRef' => where { !blessed($_) };

type 'CHI::DiscardPolicy' => where { !ref($_) || ref($_) eq 'CODE' };

my $default_serializer = CHI::Serializer::Storable->new();
my $data_serializer_loaded =
  can_load( modules => { 'Data::Serializer' => undef } );
subtype Serializer => as 'Object';
coerce 'Serializer' => from 'HashRef' => via {
    _build_data_serializer($_);
};
coerce 'Serializer' => from 'Str' => via {
    _build_data_serializer( { serializer => $_, raw => 1 } );
};

use constant Max_Time => 0xffffffff;

has 'chi_root_class'     => ( is => 'ro' );
has 'constructor_params' => ( is => 'ro', init_arg => undef );
has 'driver_class'       => ( is => 'ro' );
has 'expires_at'         => ( is => 'rw', default => Max_Time );
has 'expires_in'         => ( is => 'rw', isa => 'CHI::Duration', coerce => 1 );
has 'expires_variance' => ( is => 'rw', default    => 0.0 );
has 'label'            => ( is => 'rw', lazy_build => 1 );
has 'l1_cache'         => ( is => 'ro', isa        => 'CHI::UnblessedHashRef' );
has 'mirror_cache'     => ( is => 'ro', isa        => 'CHI::UnblessedHashRef' );
has 'namespace' => ( is => 'ro', isa => 'Str', default => 'Default' );
has 'on_get_error' => ( is => 'rw', isa => 'OnError', default => 'log' );
has 'on_set_error' => ( is => 'rw', isa => 'OnError', default => 'log' );
has 'parent_cache' => ( is => 'ro', init_arg => undef );
has 'serializer' => (
    is      => 'ro',
    isa     => 'Serializer',
    coerce  => 1,
    default => sub { $default_serializer }
);
has 'short_driver_name' => ( is => 'ro', lazy_build => 1 );
has 'subcache_type'     => ( is => 'ro', init_arg   => undef );
has 'subcaches' => ( is => 'ro', default => sub { [] }, init_arg => undef );
has 'is_size_aware' => ( is => 'ro', isa => 'Bool', default => undef );
has 'metacache' => ( is => 'ro', lazy_build => 1 );

# xx These should go in SizeAware role, but cannot right now because of the way
# xx we apply role to instance
has 'max_size' => ( is => 'rw', isa => 'CHI::MemorySize', coerce => 1 );
has 'max_size_reduction_factor' => ( is => 'rw', isa => 'Num', default => 0.8 );
has 'discard_policy' => (
    is      => 'ro',
    isa     => 'Maybe[CHI::DiscardPolicy]',
    builder => 'default_discard_policy'
);
has 'discard_timeout' => (
    is      => 'rw',
    isa     => 'Num',
    default => 10
);

# These methods must be implemented by subclass
foreach my $method (qw(fetch store remove get_keys get_namespaces)) {
    __PACKAGE__->meta->add_method( $method =>
          sub { die "method '$method' must be implemented by subclass" } );
}

__PACKAGE__->meta->make_immutable();

# Given a hash of params, return the subset that are not in CHI's common parameters.
#
my %common_params =
  map { ( $_, 1 ) } keys( %{ __PACKAGE__->meta->get_attribute_map } );

# List of parameter keys that initialize a subcache
#
my @subcache_types = qw(l1_cache mirror_cache);

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
        $class->meta->add_method( $method =>
              sub { croak "method '$method' not supported by '$class'" } );
    }
}

# To override time() for testing - must be writable in a dynamically scoped way from tests
our $Test_Time;    ## no critic (ProhibitPackageVars)

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

sub _build_data_serializer {
    my ($params) = @_;

    if ($data_serializer_loaded) {
        return Data::Serializer->new(%$params);
    }
    else {
        croak "Data::Serializer not loaded, cannot handle serializer argument";
    }
}

sub BUILD {
    my ( $self, $params ) = @_;

    # Save off constructor params. Used to create metacache, for
    # example. Hopefully this will not cause circular references...
    #
    $self->{constructor_params} = $params;

    # Every Moose driver gets the Universal role
    #
    $self->_apply_role( 'CHI::Driver::Role::Universal', 1 );

    # Turn on is_size_aware automatically if max_size is defined
    #
    if ( defined( $self->{max_size} ) || defined( $self->{is_size_aware} ) ) {
        $self->_apply_role( 'CHI::Driver::Role::SizeAware', 0 );
        $self->{is_size_aware} = 1;
    }

    # Create subcaches as necessary (l1_cache, mirror_cache)
    # Eventually might allow existing caches to be passed
    #
    foreach my $subcache_type (@subcache_types) {
        if ( my $subcache_params = $params->{$subcache_type} ) {
            if ( !@{ $self->{subcaches} } ) {
                $self->_apply_role( 'CHI::Driver::Role::HasSubcaches', 0 );
            }
            $self->add_subcache( $params, $subcache_type, $subcache_params );
        }
    }
}

sub _apply_role {
    my ( $self, $role, $ignore_error ) = @_;

    if ( !$role->can('meta') ) {
        require_dynamic($role);
    }
    eval { $role->meta->apply($self) };
    if ($@) {
        if ( has_moose_class($self) ) {
            die $@;
        }
        else {
            if ( !$ignore_error ) {
                die "cannot apply role to non-Moose driver";
            }
        }
    }
}

sub logger {
    my ($self) = @_;

    ## no critic (ProhibitPackageVars)
    return $CHI::Logger;
}

sub default_discard_policy { 'arbitrary' }

sub get {
    my ( $self, $key, %params ) = @_;
    croak "must specify key" unless defined($key);

    # Fetch cache object
    #
    my $data = $params{data} || eval { $self->fetch($key) };
    if ( my $error = $@ ) {
        $self->_handle_get_error( $error, $key );
        return;
    }

    my $log = $self->logger();
    if ( !defined $data ) {
        $self->_log_get_result( $log, "MISS (not in cache)", $key )
          if $log->is_debug;
        return undef;
    }
    my $obj =
      CHI::CacheObject->unpack_from_data( $key, $data, $self->serializer );
    if ( defined( my $obj_ref = $params{obj_ref} ) ) {
        $$obj_ref = $obj;
    }

    # Check if expired
    #
    my $is_expired = $obj->is_expired()
      || ( defined( $params{expire_if} ) && $params{expire_if}->($obj) );
    if ($is_expired) {
        $self->_log_get_result( $log, "MISS (expired)", $key )
          if $log->is_debug;

        # If busy_lock value provided, set a new "temporary" expiration time that many
        # seconds forward before returning undef
        #
        if ( defined( my $busy_lock = $params{busy_lock} ) ) {
            my $time = $Test_Time || time();
            my $busy_lock_time = $time + parse_duration($busy_lock);
            $obj->set_early_expires_at($busy_lock_time);
            $obj->set_expires_at($busy_lock_time);
            $self->_set_object( $key, $obj );
        }

        return undef;
    }

    $self->_log_get_result( $log, "HIT", $key ) if $log->is_debug;
    return $obj->value;
}

sub get_object {
    my ( $self, $key ) = @_;
    croak "must specify key" unless defined($key);

    my $data = $self->fetch($key) or return undef;
    my $obj =
      CHI::CacheObject->unpack_from_data( $key, $data, $self->serializer );
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
    return unless defined($value);

    # Fill in $options if not passed, copy if passed, and apply defaults.
    #
    if ( !defined($options) ) {
        $options = $self->_default_set_options;
    }
    else {
        if ( !ref($options) ) {
            if ( $options eq 'never' ) {
                $options = { expires_at => Max_Time };
            }
            elsif ( $options eq 'now' ) {
                $options = { expires_in => 0 };
            }
            else {
                $options = { expires_in => $options };
            }
        }
        $options = { %{ $self->_default_set_options }, %$options };
    }

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
      : ( $expires_at == Max_Time )             ? Max_Time
      : $expires_at -
      ( ( $expires_at - $time ) * $options->{expires_variance} );

    # Pack into data, and store
    #
    my $obj =
      CHI::CacheObject->new( $key, $value, $created_at, $early_expires_at,
        $expires_at, $self->serializer );
    if ( defined( my $obj_ref = $options->{obj_ref} ) ) {
        $$obj_ref = $obj;
    }
    eval { $self->_set_object( $key, $obj ) };
    if ( my $error = $@ ) {
        my $log_expires_in =
          defined($expires_at) ? ( $expires_at - $created_at ) : undef;
        $self->_handle_set_error( $error, $key, $value, $log_expires_in );
        return;
    }

    # Log the set
    #
    my $log = $self->logger();
    if ( $log->is_debug ) {
        my $log_expires_in =
          defined($expires_at) ? ( $expires_at - $created_at ) : undef;
        $self->_log_set_result( $log, $key, $value, $log_expires_in );
    }

    return $value;
}

sub get_keys_iterator {
    my ($self) = @_;

    my @keys = $self->get_keys();
    return sub { shift(@keys) };
}

sub clear {
    my ($self) = @_;

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
        $self->_set_object( $key, $obj );
    }
}

# DEPRECATED
sub expire_if {
    my ( $self, $key, $code ) = @_;
    croak "must specify key and code" unless defined($key) && defined($code);

    if ( my $obj = $self->get_object($key) ) {
        my $retval = $code->($obj);
        if ($retval) {
            $self->expire($key);
        }
        return $retval;
    }
    else {
        return 1;
    }
}

sub compute {
    my ( $self, $key, $code, $set_options ) = @_;
    croak "must specify key and code" unless defined($key) && defined($code);

    my $value = $self->get($key);
    if ( !defined $value ) {
        $value = $code->();
        $self->set( $key, $value, $set_options );
    }
    return $value;
}

sub fetch_multi_hashref {
    my ( $self, $keys ) = @_;

    return { map { ( $_, $self->fetch($_) ) } @$keys };
}

sub get_multi_hashref {
    my ( $self, $keys ) = @_;
    croak "must specify keys" unless defined($keys);

    my $keyvals = $self->fetch_multi_hashref($keys);
    return { map { ( $_, $self->get( $_, data => $keyvals->{$_} ) ) } @$keys };
}

# DEPRECATED
sub get_multi_array {
    my $self = shift;
    return @{ $self->get_multi_arrayref(@_) };
}

sub get_multi_arrayref {
    my ( $self, $keys ) = @_;
    croak "must specify keys" unless defined($keys);

    my $keyvals = $self->get_multi_hashref($keys);
    return [ map { $keyvals->{$_} } @$keys ];
}

sub set_multi {
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

sub purge {
    my ($self) = @_;

    foreach my $key ( $self->get_keys() ) {
        if ( $self->get_object($key)->is_expired() ) {
            $self->remove($key);
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

{

    # Escape/unescape keys and namespaces for filename safety - used by various
    # drivers.  Adapted from URI::Escape, but use '+' for escape character, like Mason's
    # compress_path.
    #
    my %escapes;
    for ( 0 .. 255 ) {
        $escapes{ chr($_) } = sprintf( "+%02x", $_ );
    }

    my $_fail_hi = sub {
        my $chr = shift;
        Carp::croak( sprintf "Can't escape multibyte character \\x{%04X}",
            ord($chr) );
    };

    sub escape_for_filename {
        my ( $self, $text ) = @_;

        $text =~ s/([^\w\=\-\~])/$escapes{$1} || $_fail_hi->($1)/ge;
        $text;
    }

    sub unescape_for_filename {
        my ( $self, $str ) = @_;

        $str =~ s/\+([0-9A-Fa-f]{2})/chr(hex($1))/eg if defined $str;
        $str;
    }

    sub is_escaped_for_filename {
        my ( $self, $text ) = @_;

        return $self->escape_for_filename( $self->unescape_for_filename($text) )
          eq $text;
    }
}

sub is_subcache {
    my ($self) = @_;

    return defined( $self->subcache_type );
}

sub _set_object {
    my ( $self, $key, $obj ) = @_;

    my $data = $obj->pack_to_data();
    $self->store( $key, $data );
    return length($data);
}

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
    my $self  = shift;
    my $error = shift;
    my $key   = $_[0];

    my $msg =
      sprintf( "error during %s: %s", $self->_describe_cache_set(@_), $error );
    $self->_dispatch_error_msg( $msg, $error, $self->on_set_error(), $key );
}

sub _dispatch_error_msg {
    my ( $self, $msg, $error, $on_error, $key ) = @_;

    for ($on_error) {
        ( ref($_) eq 'CODE' ) && do { $_->( $msg, $key, $error ) };
        /^log$/
          && do { my $log = $self->logger; $log->error($msg) };
        /^ignore$/ && do { };
        /^warn$/   && do { carp $msg };
        /^die$/    && do { croak $msg };
    }
}

sub _describe_cache_get {
    my ( $self, $key ) = @_;

    return sprintf( "cache get for namespace='%s', key='%s', cache='%s'",
        $self->namespace, $key, $self->label );
}

sub _describe_cache_set {
    my ( $self, $key, $value, $expires_in ) = @_;

    return sprintf(
        "cache set for namespace='%s', key='%s', size=%d, expires='%s', cache='%s'",
        $self->namespace,
        $key,
        length($value),
        defined($expires_in)
        ? Time::Duration::concise(
            Time::Duration::duration_exact($expires_in)
          )
        : 'never',
        $self->label
    );
}

1;

__END__

=pod

=head1 NAME

CHI::Driver -- Base class for all CHI drivers.

=head1 DESCRIPTION

This is the base class that all CHI drivers inherit from. It provides the
methods that one calls on $cache handles, such as get() and set().

See L<CHI/METHODS> for documentation on $cache methods, and
L<CHI::Driver::Development|CHI::Driver::Development> for documentation on
creating new subclasses of CHI::Driver.

=head1 AUTHOR

Jonathan Swartz

=head1 COPYRIGHT & LICENSE

Copyright (C) 2007 Jonathan Swartz.

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
