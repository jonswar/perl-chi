package CHI::Driver;
use Carp;
use CHI::CacheObject;
use CHI::Util qw(parse_duration);
use List::MoreUtils qw(pairwise);
use Moose;
use Moose::Util::TypeConstraints;
use strict;
use warnings;

# Call this when updating default set options
my @trigger_set_options =
  ( trigger => sub { $_[0]->_compute_default_set_options() } );

type OnError => where { ref($_) eq 'CODE' || /^(?:ignore|warn|die|log)/ };

has 'default_set_options' => ( is => 'ro' );
has 'expires_at'          => ( is => 'rw', @trigger_set_options );
has 'expires_in'          => ( is => 'rw', @trigger_set_options );
has 'expires_variance'    => ( is => 'rw', @trigger_set_options );
has 'is_subcache'         => ( is => 'rw' );
has 'namespace'           => ( is => 'ro', isa => 'Str', default => 'Default' );
has 'on_get_error'        => ( is => 'rw', isa => 'OnError', default => 'log' );
has 'on_set_error'        => ( is => 'rw', isa => 'OnError', default => 'log' );
has 'short_driver_name'   => ( is => 'ro' );

__PACKAGE__->meta->make_immutable();

# These methods must be implemented by subclass
foreach my $method (qw(fetch store remove get_keys get_namespaces)) {
    no strict 'refs';
    *{ __PACKAGE__ . "::$method" } =
      sub { die "method '$method' must be implemented by subclass" }; ## no critic (RequireCarping)
}

use constant Max_Time => 0xffffffff;

# To override time() for testing - must be writable in a dynamically scoped way from tests
our $Test_Time;    ## no critic (ProhibitPackageVars)

sub BUILD {
    my ( $self, $params ) = @_;

    $self->_compute_default_set_options();

    ( $self->{short_driver_name} = ref($self) ) =~ s/^CHI::Driver:://;
}

sub _compute_default_set_options {
    my ($self) = @_;

    $self->{default_set_options}->{expires_at} = $self->{expires_at}
      || Max_Time;
    $self->{default_set_options}->{expires_in} =
      defined( $self->{expires_in} )
      ? parse_duration( $self->{expires_in} )
      : undef;
    $self->{default_set_options}->{expires_variance} = $self->{expires_variance}
      || 0.0;
}

sub desc {
    my $self = shift;

    return sprintf(
        "CHI cache (driver=%s, namespace=%s)",
        $self->{short_driver_name},
        $self->{namespace}
    );
}

sub get {
    my ( $self, $key, %params ) = @_;
    croak "must specify key" unless defined($key);

    my $log = CHI->logger();

    # Fetch cache object
    #
    my $data = $params{data} || eval { $self->fetch($key) };
    if ( my $error = $@ ) {
        $self->_handle_error( $key, $error, 'getting', $self->on_get_error() );
        return;
    }

    if ( !defined $data ) {
        $self->_log_get_result( $log, $key, "MISS (not in cache)" )
          if $log->is_debug;
        return undef;
    }
    my $obj = CHI::CacheObject->unpack_from_data( $key, $data );

    # Handle expire_if
    #
    if ( defined( my $code = $params{expire_if} ) ) {
        my $retval = $code->($obj);
        if ($retval) {
            $self->expire($key);
            return undef;
        }
    }

    # Check if expired
    #
    if ( $obj->is_expired() ) {
        $self->_log_get_result( $log, $key, "MISS (expired)" )
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

    # Success
    #
    $self->_log_get_result( $log, $key, "HIT" ) if $log->is_debug;
    return $obj->value;
}

sub get_object {
    my ( $self, $key ) = @_;
    croak "must specify key" unless defined($key);

    my $data = $self->fetch($key) or return undef;
    my $obj = CHI::CacheObject->unpack_from_data( $key, $data );
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

sub set {
    my ( $self, $key, $value, $options ) = @_;
    croak "must specify key" unless defined($key);
    return unless defined($value);

    # Fill in $options if not passed, copy if passed, and apply defaults.
    #
    if ( !defined($options) ) {
        $options = $self->default_set_options;
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
        $options = { %{ $self->default_set_options }, %$options };
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
      ( $expires_at == Max_Time )
      ? Max_Time
      : $expires_at -
      ( ( $expires_at - $time ) * $options->{expires_variance} );

    # Pack into data, and store
    #
    my $obj =
      CHI::CacheObject->new( $key, $value, $created_at, $early_expires_at,
        $expires_at );
    eval { $self->_set_object( $key, $obj ) };
    if ( my $error = $@ ) {
        $self->_handle_error( $key, $error, 'setting', $self->on_set_error() );
        return;
    }

    my $log = CHI->logger();
    $self->_log_set_result( $log, $key ) if $log->is_debug;

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

sub _set_object {
    my ( $self, $key, $obj ) = @_;

    my $data = $obj->pack_to_data();
    $self->store( $key, $data );
}

sub _log_get_result {
    my ( $self, $log, $key, $msg ) = @_;

    # if $log->is_debug - done in caller
    if ( !$self->is_subcache ) {
        $log->debug(
            sprintf(
                "cache get for namespace='%s', key='%s', driver='%s': %s",
                $self->{namespace}, $key, $self->{short_driver_name}, $msg
            )
        );
    }
}

sub _log_set_result {
    my ( $self, $log, $key ) = @_;

    # if $log->is_debug - done in caller
    if ( !$self->is_subcache ) {
        $log->debug(
            sprintf(
                "cache set for namespace='%s', key='%s', driver='%s'",
                $self->{namespace}, $key, $self->{short_driver_name}
            )
        );
    }
}

sub _handle_error {
    my ( $self, $key, $error, $action, $on_error ) = @_;

    my $msg = sprintf( "error %s key '%s' in %s: %s",
        $action, $key, $self->desc, $error );

    for ($on_error) {
        ( ref($_) eq 'CODE' ) && do { $_->( $msg, $key, $error ) };
        /^log$/
          && do { my $log = CHI->logger; $log->error($msg) };
        /^ignore$/ && do { };
        /^warn$/   && do { carp $msg };
        /^die$/    && do { croak $msg };
    }
}

1;

__END__

=pod

=head1 NAME

CHI::Driver -- Base class for all CHI drivers.

=head1 DESCRIPTION

This is the base class that all CHI drivers inherit from. It provides the methods
that one calls on $cache handles, such as get() and set().

See L<CHI|METHODS> for documentation on $cache methods, and L<CHI|IMPLEMENTING NEW DRIVERS>
for documentation on creating new subclasses of CHI::Driver.

=head1 AUTHOR

Jonathan Swartz

=head1 COPYRIGHT & LICENSE

Copyright (C) 2007 Jonathan Swartz.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
