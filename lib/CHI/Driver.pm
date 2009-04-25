package CHI::Driver;
use Carp;
use CHI::CacheObject;
use CHI::Serializer::Storable;
use CHI::Util qw(parse_duration dp);
use Hash::MoreUtils qw(slice_exists);
use List::MoreUtils qw(pairwise);
use Module::Load::Conditional qw(can_load);
use Mouse;
use Mouse::Util::TypeConstraints;
use Scalar::Util qw(blessed weaken);
use Time::Duration;
use strict;
use warnings;

type OnError => where { ref($_) eq 'CODE' || /^(?:ignore|warn|die|log)$/ };

subtype Duration => as 'Int' => where { $_ > 0 };

subtype UnblessedHashRef => as 'HashRef' => where { !blessed($_) };

coerce 'Duration' => from 'Str' => via { parse_duration($_) };

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

has 'chi_root_class' => ( is => 'ro' );
has 'label'          => ( is => 'rw', builder => '_build_label' );
has 'expires_at'     => ( is => 'rw', default => Max_Time );
has 'expires_in'     => ( is => 'rw', isa => 'Duration', coerce => 1 );
has 'expires_variance' => ( is => 'rw', default => 0.0 );
has 'l1_cache'         => ( is => 'ro', isa     => 'UnblessedHashRef' );
has 'mirror_cache'     => ( is => 'ro', isa     => 'UnblessedHashRef' );
has 'namespace' => ( is => 'ro', isa => 'Str', default => 'Default' );
has 'on_get_error' => ( is => 'rw', isa => 'OnError', default => 'log' );
has 'on_set_error' => ( is => 'rw', isa => 'OnError', default => 'log' );
has 'parent_cache' => ( is => 'ro' );
has 'serializer'   => (
    is      => 'ro',
    isa     => 'Serializer',
    coerce  => 1,
    default => sub { $default_serializer }
);
has 'short_driver_name' =>
  ( is => 'ro', builder => '_build_short_driver_name' );
has 'subcache_type' => ( is => 'ro' );
has 'subcaches' => ( is => 'ro', default => sub { [] } );

__PACKAGE__->meta->make_immutable();

# Given a hash of params, return the subset that are not in CHI's common parameters.
#
my %common_params =
  map { ( $_, 1 ) } keys( %{ __PACKAGE__->meta->get_attribute_map } );

# List of parameter keys that initialize a subcache
#
my @subcache_types = qw(l1_cache mirror_cache);

# List of parameters that are automatically inherited by a subcache
#
my @subcache_inherited_param_keys = (
    qw(expires_at expires_in expires_variance namespace on_get_error on_set_error)
);

sub non_common_constructor_params {
    my ( $class, $params ) = @_;

    return {
        map { ( $_, $params->{$_} ) }
          grep { !$common_params{$_} } keys(%$params)
    };
}

# These methods must be implemented by subclass
foreach my $method (qw(fetch store remove get_keys get_namespaces)) {
    no strict 'refs';
    *{ __PACKAGE__ . "::$method" } =
      sub { die "method '$method' must be implemented by subclass" }; ## no critic (RequireCarping)
}

sub declare_unsupported_methods {
    my ( $class, @methods ) = @_;

    foreach my $method (@methods) {
        no strict 'refs';
        *{ $class . "::$method" } =
          sub { croak "method '$method' not supported by '$class'" };
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

    return $self->_build_short_driver_name;
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

    # Create subcaches as necessary (l1_cache, mirror_cache)
    # Eventually might allow existing caches to be passed
    #
    foreach my $subcache_type (@subcache_types) {
        if ( my $subcache_params = $params->{$subcache_type} ) {
            my $chi_root_class = $self->chi_root_class;
            my %inherited_params =
              slice_exists( $params, @subcache_inherited_param_keys );
            my $default_label = $self->label . ":$subcache_type";
            my $subcache      = $chi_root_class->new(
                label => $default_label,
                %inherited_params, %$subcache_params
            );
            $subcache->{subcache_type} = $subcache_type;
            $subcache->{parent_cache}  = $self;
            weaken( $subcache->{parent_cache} );
            $self->{$subcache_type} = $subcache;
            push( @{ $self->{subcaches} }, $subcache );
        }
    }
}

sub logger {
    my ($self) = @_;

    ## no critic (ProhibitPackageVars)
    return $CHI::Logger;
}

sub get {
    my ( $self, $key, %params ) = @_;
    croak "must specify key" unless defined($key);
    my $l1_cache = $self->{l1_cache};

    # Consult l1 cache first if present
    #
    if ( defined($l1_cache) ) {
        if ( defined( my $result = $l1_cache->get( $key, %params ) ) ) {
            return $result;
        }
    }

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

    # Success - write back to l1 cache if present, and return result
    #
    if ( defined($l1_cache) ) {

        # ** Should call store directly if caches are object-compatible
        $l1_cache->set(
            $key,
            $obj->value,
            {
                expires_at       => $obj->expires_at,
                early_expires_at => $obj->early_expires_at
            }
        );
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

    my $log = $self->logger();
    if ( $log->is_debug ) {
        my $log_expires_in =
          defined($expires_at) ? ( $expires_at - $created_at ) : undef;
        $self->_log_set_result( $log, $key, $value, $log_expires_in );
    }

    $self->call_method_on_subcaches( 'set', @_ );

    return $value;
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

sub get_multi_arrayref {
    my ( $self, $keys ) = @_;
    croak "must specify keys" unless defined($keys);

    return [ map { scalar( $self->get($_) ) } @$keys ];
}

sub get_multi_array {
    my $self = shift;
    return @{ $self->get_multi_arrayref(@_) };
}

sub get_multi_hashref {
    my ( $self, $keys ) = @_;
    croak "must specify keys" unless defined($keys);

    my $values = $self->get_multi_arrayref($keys);
    my %hash = pairwise { ( $a => $b ) } @$keys, @$values;
    return \%hash;
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

sub clear {
    my ($self) = @_;

    $self->remove_multi( [ $self->get_keys() ] );
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
}

sub call_method_on_subcaches {
    my $self      = shift;
    my $method    = shift;
    my $subcaches = $self->subcaches;
    return unless $subcaches;

    foreach my $subcache (@$subcaches) {
        $subcache->$method(@_);
    }
}

sub is_subcache {
    my ($self) = @_;

    return defined( $self->{subcache_type} );
}

sub _set_object {
    my ( $self, $key, $obj ) = @_;

    my $data = $obj->pack_to_data();
    $self->store( $key, $data );
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
        $self->{namespace}, $key, $self->{label} );
}

sub _describe_cache_set {
    my ( $self, $key, $value, $expires_in ) = @_;

    return sprintf(
        "cache set for namespace='%s', key='%s', size=%d, expires='%s', cache='%s'",
        $self->{namespace},
        $key,
        length($value),
        defined($expires_in)
        ? Time::Duration::concise(
            Time::Duration::duration_exact($expires_in)
          )
        : 'never',
        $self->{label}
    );
}

1;

__END__

=pod

=head1 NAME

CHI::Driver -- Base class for all CHI drivers.

=head1 DESCRIPTION

This is the base class that all CHI drivers inherit from. It provides the methods
that one calls on $cache handles, such as get() and set().

See L<CHI/METHODS> for documentation on $cache methods, and L<CHI::Driver::Development|CHI::Driver::Development>
for documentation on creating new subclasses of CHI::Driver.

=head1 AUTHOR

Jonathan Swartz

=head1 COPYRIGHT & LICENSE

Copyright (C) 2007 Jonathan Swartz.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
