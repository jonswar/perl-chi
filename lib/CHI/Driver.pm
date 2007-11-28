package CHI::Driver;
use CHI::CacheObject;
use CHI::Util;
use List::MoreUtils qw(pairwise);
use Storable;
use strict;
use warnings;
use base qw(Class::Accessor::Fast);

__PACKAGE__->mk_ro_accessors(
    qw(default_set_options short_driver_name namespace));
__PACKAGE__->mk_accessors(qw(is_subcache on_set_error));

# When these are set, call _compute_default_set_options again.
foreach my $field qw(expires_at expires_in expires_variance) {
    no strict 'refs';
    *{ __PACKAGE__ . "::$field" } = sub {
        my $self = shift;
        if (@_) {
            $self->{$field} = $_[0];
            $self->_compute_default_set_options();
        }
        else {
            return $self->{$field};
        }
    };
}

# These methods must be implemented by subclass
foreach my $method (qw(fetch store delete get_keys get_namespaces)) {
    no strict 'refs';
    *{ __PACKAGE__ . "::$method" } =
      sub { die "method '$method' must be implemented by subclass" };
}

my $Metadata_Format = "LLLCC";
my $Metadata_Length = 14;
my $Expires_Never   = 0xffffffff;
my $Cache_Version   = 1;

# To override time() for testing
our $Test_Time;

sub new {
    my $class = shift;

    my $self = $class->SUPER::new(@_);

    my %defaults = (
        driver       => 'Memory',
        on_set_error => 'log',
    );
    while ( my ( $key, $value ) = each(%defaults) ) {
        $self->{$key} = $value if !defined( $self->{$key} );
    }

    # Default the namespace to the first non-chi caller, or 'Default' if none found
    #
    my $level = 0;
    while ( !defined( $self->{namespace} ) ) {
        $level++;
        my $caller = caller($level);
        if ( !defined($caller) ) {
            $self->{namespace} = 'Default';
        }
        elsif (
            $caller =~ /^CHI(?::|$)/
            || ( UNIVERSAL::can( $caller, 'isa_chi_class' )
                && $caller->isa_chi_class() )
          )
        {
            next;
        }
        else {
            $self->{namespace} = $caller;
        }
    }

    $self->_compute_default_set_options();

    # TODO: validate:
    # on_set_error      => 'warn'   ('ignore', 'warn', 'die', sub { })

    ( $self->{short_driver_name} = ref($self) ) =~ s/^CHI::Driver:://;

    return $self;
}

sub _compute_default_set_options {
    my ($self) = @_;

    $self->{default_set_options}->{expires_at} = $self->{expires_at}
      || $Expires_Never;
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
    my ( $self, $key ) = @_;
    return undef unless defined($key);

    my $value_with_metadata = $self->fetch($key);
    if ( !defined $value_with_metadata ) {
        my $log = CHI->logger();
        $self->_log_get_result( $log, $key, "MISS (not in cache)" )
          if $log->is_debug;
        return undef;
    }
    return $self->_process_fetched_value( $key, $value_with_metadata );
}

sub _process_fetched_value {
    my ( $self, $key, $value_with_metadata ) = @_;

    my $log = CHI->logger();
    my $metadata = substr( $value_with_metadata, 0, $Metadata_Length );
    my ( $created_at, $early_expires_at, $expires_at, $is_serialized ) =
      unpack( $Metadata_Format, $metadata );

    # Determine whether item has expired, probabilistically if between early_expires_at and expires_at.
    #
    my $time = $Test_Time || time();
    if (
        $time >= $early_expires_at
        && (
            $time >= $expires_at
            || (
                rand() < (
                    ( $time - $early_expires_at ) /
                      ( $expires_at - $early_expires_at )
                )
            )
        )
      )
    {
        $self->_log_get_result( $log, $key, "MISS (expired)" )
          if $log->is_debug;
        return undef;
    }

    # Deserialize if necessary
    #
    $self->_log_get_result( $log, $key, "HIT" ) if $log->is_debug;
    my $value = substr( $value_with_metadata, $Metadata_Length );
    if ($is_serialized) {
        $value = $self->_deserialize($value);
    }

    return $value;
}

sub get_object {
    my ( $self, $key ) = @_;
    return unless defined($key);

    my $value_with_metadata = $self->fetch($key) or return undef;
    my $metadata = substr( $value_with_metadata, 0, $Metadata_Length );
    my ( $created_at, $early_expires_at, $expires_at, $is_serialized ) =
      unpack( $Metadata_Format, $metadata );

    my $value = substr( $value_with_metadata, $Metadata_Length );
    if ($is_serialized) {
        $value = $self->_deserialize($value);
    }

    return CHI::CacheObject->new(
        {
            key              => $key,
            value            => $value,
            early_expires_at => $early_expires_at,
            created_at       => $created_at,
            expires_at       => $expires_at,
            _is_serialized   => $is_serialized,
        }
    );
}

sub get_expires_at {
    my ( $self, $key ) = @_;

    my $value_with_metadata = $self->fetch($key) or return undef;
    my $metadata = substr( $value_with_metadata, 0, $Metadata_Length );
    my ( $created_at, $early_expires_at, $expires_at, $is_serialized ) =
      unpack( $Metadata_Format, $metadata );

    return $expires_at;
}

sub is_valid {
    my ( $self, $key ) = @_;

    if ( my $object = $self->get_object($key) ) {
        return !$object->is_expired;
    }
    else {
        return;
    }
}

sub set {
    my ( $self, $key, $value, $options ) = @_;
    return unless defined($key) && defined($value);

    # Fill in $options if not passed, copy if passed, and apply defaults.
    #
    if ( !defined($options) ) {
        $options = $self->default_set_options;
    }
    elsif ( !ref($options) ) {
        $options = { %{ $self->default_set_options }, expires_in => $options };
    }
    else {
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
      ( $expires_at == $Expires_Never )
      ? $Expires_Never
      : $expires_at -
      ( ( $expires_at - $time ) * $options->{expires_variance} );

    # Serialize if necessary
    #
    my $is_serialized = 0;
    my $store_value   = $value;
    if ( ref($store_value) ) {
        $store_value   = $self->_serialize($store_value);
        $is_serialized = 1;
    }

    # Prepend value with metadata, and store
    #
    my $metadata = pack( $Metadata_Format,
        $created_at, $early_expires_at, $expires_at, $is_serialized, $Cache_Version );
    my $store_value_with_metadata = $metadata . $store_value;
    eval {
        $self->store( $key, $store_value_with_metadata, $expires_at, $options );
    };
    if ( my $error = $@ ) {
        $self->_handle_set_error( $key, $error );
        return;
    }

    my $log = CHI->logger();
    $self->_log_set_result( $log, $key ) if $log->is_debug;

    return $value;
}

sub remove {
    my ( $self, $key ) = @_;

    $self->delete($key);
}

sub _serialize {
    my ( $self, $value ) = @_;

    return Storable::freeze($value);
}

sub _deserialize {
    my ( $self, $value ) = @_;

    return Storable::thaw($value);
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

sub _handle_set_error {
    my ( $self, $key, $error ) = @_;

    my $msg =
      sprintf( "error setting key '%s' in %s: %s", $key, $self->desc, $error );
    for ( $self->on_set_error() ) {
        /ignore/ && do { };
        /warn/   && do { warn $msg };
        /log/
          && do { my $log = CHI->logger; $log->debug($msg) if $log->is_debug };
        /die/ && do { die $msg };
        ( ref($_) eq 'CODE' ) && do { $_->( $msg, $key, $error ) };
    }
}

sub compute {
    my ( $self, $key, $code, $set_options ) = @_;

    my $value = $self->get($key);
    if ( !defined $value ) {
        $value = $code->();
        $self->set( $key, $value, $set_options );
    }
    return $value;
}

sub get_multi_arrayref {
    my ( $self, $keys ) = @_;

    return [ map { scalar( $self->get($_) ) } @$keys ];
}

sub get_multi_hashref {
    my ( $self, $keys ) = @_;

    my $values = $self->get_multi_arrayref($keys);
    my %hash = pairwise { ( $a => $b ) } @$keys, @$values;
    return \%hash;
}

sub set_multi {
    my ( $self, $key_values, $set_options ) = @_;

    while ( my ( $key, $value ) = each(%$key_values) ) {
        $self->set( $key, $value, $set_options );
    }
}

sub remove_multi {
    my ( $self, $keys ) = @_;

    foreach my $key (@$keys) {
        $self->remove($key);
    }
}

sub clear {
    my ($self) = @_;

    $self->remove_multi( $self->get_keys() );
}

sub purge {
    my ($self) = @_;

    foreach my $key ( @{ $self->get_keys() } ) {
        if ( $self->get_object($key)->is_expired() ) {
            $self->remove($key);
        }
    }
}

sub dump_as_hash {
    my ($self) = @_;

    return { map { my $value = $self->get($_); $value ? ( $_, $value ) : () }
          @{ $self->get_keys() } };
}

sub is_empty {
    my ($self) = @_;

    return !@{ $self->get_keys() };
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

Copyright (C) 2007 Jonathan Swartz, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
