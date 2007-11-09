package CHI::Driver;
use CHI::CacheObject;
use CHI::Util;
use List::MoreUtils qw(pairwise);
use Storable;
use strict;
use warnings;
use base qw(Class::Accessor::Fast);

__PACKAGE__->mk_ro_accessors(
    qw(default_expires_at default_expires_in default_expires_window namespace on_set_error)
);

my $Metadata_Format = "LCCC";
my $Metadata_Length = 7;
my $Expire_Never    = 0xffffffff;

# These methods must be implemented by subclass
foreach my $method (qw(fetch store delete get_keys get_namespaces)) {
    no strict 'refs';
    *{ __PACKAGE__ . "::$method" } =
      sub { die "method '$method' must be implemented by subclass" };
}

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

    # TODO: validate:
    # on_set_error      => 'warn'   ('ignore', 'warn', 'die', sub { })

    return $self;
}

sub desc {
    my $self = shift;

    return ref($self) . " cache";
}

sub get {
    my ( $self, $key ) = @_;
    return unless defined($key);

    my $value_with_metadata = $self->fetch($key) or return;
    my $metadata = substr( $value_with_metadata, 0, $Metadata_Length );
    my ( $expire_time, $is_serialized ) = unpack( $Metadata_Format, $metadata );
    return if ( $expire_time <= time );

    my $value = substr( $value_with_metadata, $Metadata_Length );
    if ($is_serialized) {
        $value = $self->_deserialize($value);
    }

    return $value;
}

sub get_object {
    my ( $self, $key ) = @_;
    return unless defined($key);

    my $value_with_metadata = $self->fetch($key) or return;
    my $metadata = substr( $value_with_metadata, 0, $Metadata_Length );
    my ( $expire_time, $is_serialized ) = unpack( $Metadata_Format, $metadata );

    my $value = substr( $value_with_metadata, $Metadata_Length );
    if ($is_serialized) {
        $value = $self->_deserialize($value);
    }

    return CHI::CacheObject->new(
        {
            key            => $key,
            value          => $value,
            expires_at     => $expire_time,
            _is_serialized => $is_serialized,
        }
        );
}

sub get_expires_at {
    my ( $self, $key ) = @_;

    my $value_with_metadata = $self->fetch($key) or return;
    my $metadata = substr( $value_with_metadata, 0, $Metadata_Length );
    my ( $expire_time, $is_serialized ) = unpack( $Metadata_Format, $metadata );
    return $expire_time;
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

    if ( !defined($options) ) {
        $options = {};
    }
    elsif ( !ref($options) ) {
        $options = { expires_in => $options };
    }

    # Parse expiration options. This tedious series of conditionals is necessary because
    # (1) We have to account for both passed options and default values in $cache
    # (2) We have to be careful to check for undefined'ness, not falsity
    # (3) We don't have // yet. :)
    #
    my ( $expires_at, $expires_in );
    if ( !defined( $expires_at = delete( $options->{expires_at} ) ) ) {
        $expires_at = $self->{default_expires_at};
    }
    if ( !defined( $expires_in = delete( $options->{expires_in} ) ) ) {
        $expires_in = $self->{default_expires_in};
    }
    if ( defined $expires_in ) {
        $expires_at = time + parse_duration($expires_in);
    }
    if ( !defined($expires_at) ) {
        $expires_at = $Expire_Never;
    }

    my $is_serialized = 0;
    my $store_value   = $value;
    if ( ref($store_value) ) {
        $store_value   = $self->_serialize($store_value);
        $is_serialized = 1;
    }

    my $checksum = length($key) & 0xff;
    my $metadata =
      pack( $Metadata_Format, $expires_at, $is_serialized, $checksum );
    my $store_value_with_metadata = $metadata . $store_value;
    eval {
        $self->store( $key, $store_value_with_metadata, $expires_at, $options );
    };
    if ( my $error = $@ ) {
        $self->_handle_set_error( $key, $error );
        return;
    }

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

sub _handle_set_error {
    my ( $self, $key, $error ) = @_;

    my $msg =
      sprintf( "error setting key '%s' in %s: %s", $key, $self->desc, $error );
    for ( $self->on_set_error() ) {
        /ignore/ && do { };
        /warn/   && do { warn $msg };
        /die/    && do { die $msg };
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
