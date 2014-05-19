package CHI::CacheObject;

use CHI::Constants qw(CHI_Max_Time);
use Encode;
use strict;
use warnings;

use constant f_key              => 0;
use constant f_raw_value        => 1;
use constant f_serializer       => 2;
use constant f_created_at       => 3;
use constant f_early_expires_at => 4;
use constant f_expires_at       => 5;
use constant f_is_transformed   => 6;
use constant f_cache_version    => 7;
use constant f_value            => 8;
use constant f_packed_data      => 9;
use constant f_size             => 10;

use constant T_SERIALIZED   => 1;
use constant T_UTF8_ENCODED => 2;
use constant T_COMPRESSED   => 4;

my $Metadata_Format = "LLLCC";
my $Metadata_Length = 14;

# Eschewing Moose and hash-based objects for this class to get the extra speed.
# Eventually will probably write in C anyway.

sub key              { $_[0]->[f_key] }
sub created_at       { $_[0]->[f_created_at] }
sub early_expires_at { $_[0]->[f_early_expires_at] }
sub expires_at       { $_[0]->[f_expires_at] }
sub serializer       { $_[0]->[f_serializer] }
sub _is_transformed  { $_[0]->[f_is_transformed] }
sub size             { $_[0]->[f_size] }

sub set_early_expires_at {
    $_[0]->[f_early_expires_at] = $_[1];
    undef $_[0]->[f_packed_data];
}

sub set_expires_at {
    $_[0]->[f_expires_at] = $_[1];
    undef $_[0]->[f_packed_data];
}

## no critic (ProhibitManyArgs)
sub new {
    my ( $class, $key, $value, $created_at, $early_expires_at, $expires_at,
        $serializer, $compress_threshold )
      = @_;

    # Serialize/encode value if necessary - does this belong here, or in
    # Driver.pm?
    #
    my $is_transformed = 0;
    my $raw_value      = $value;
    my $size;
    if ($serializer) {
        if ( ref($raw_value) ) {
            $raw_value = $serializer->serialize($raw_value);
            $is_transformed |= T_SERIALIZED;
        }
        elsif ( Encode::is_utf8($raw_value) ) {
            $raw_value = Encode::encode( utf8 => $raw_value );
            $is_transformed |= T_UTF8_ENCODED;
        }
        if ( defined($compress_threshold)
            && length($raw_value) > $compress_threshold )
        {
            require Compress::Zlib;
            $raw_value = Compress::Zlib::memGzip($raw_value);
            $is_transformed |= T_COMPRESSED;
        }
        $size = length($raw_value) + $Metadata_Length;
    }
    else {
        $size = 1;
    }

    # Not sure where this should be set and checked
    #
    my $cache_version = 1;

    return bless [
        $key,              $raw_value,  $serializer,     $created_at,
        $early_expires_at, $expires_at, $is_transformed, $cache_version,
        $value,            undef,       $size
    ], $class;
}

sub unpack_from_data {
    my ( $class, $key, $data, $serializer ) = @_;

    return $data if !$serializer;
    my $metadata  = substr( $data, 0, $Metadata_Length );
    my $raw_value = substr( $data, $Metadata_Length );
    my $obj       = bless [
        $key, $raw_value,
        $serializer, unpack( $Metadata_Format, $metadata )
      ],
      $class;
    $obj->[f_packed_data] = $data;
    $obj->[f_size]        = length($data);
    return $obj;
}

sub pack_to_data {
    my ($self) = @_;

    return $self if !$self->serializer;
    if ( !defined( $self->[f_packed_data] ) ) {
        my $data = pack( $Metadata_Format,
            ( @{$self} )[ f_created_at .. f_cache_version ] )
          . $self->[f_raw_value];
        $self->[f_packed_data] = $data;
    }
    return $self->[f_packed_data];
}

sub is_expired {
    my ($self) = @_;

    my $expires_at = $self->[f_expires_at];
    return undef if $expires_at == CHI_Max_Time;

    my $time = $CHI::Driver::Test_Time || time();
    my $early_expires_at = $self->[f_early_expires_at];

    return $time >= $early_expires_at
      && (
        $time >= $expires_at
        || (
            rand() < (
                ( $time - $early_expires_at ) /
                  ( $expires_at - $early_expires_at )
            )
        )
      );
}

sub value {
    my ($self) = @_;

    if ( !defined $self->[f_value] ) {
        my $value          = $self->[f_raw_value];
        my $is_transformed = $self->[f_is_transformed];
        if ( $is_transformed & T_COMPRESSED ) {
            require Compress::Zlib;
            $value = Compress::Zlib::memGunzip($value);
        }
        if ( $is_transformed & T_SERIALIZED ) {
            $value = $self->serializer->deserialize($value);
        }
        elsif ( $is_transformed & T_UTF8_ENCODED ) {
            $value = Encode::decode( utf8 => $value );
        }
        $self->[f_value] = $value;
    }
    return $self->[f_value];
}

# get_* aliases for backward compatibility with Cache::Cache
#
*get_created_at = \&created_at;
*get_expires_at = \&expires_at;

1;

__END__

=pod

=head1 NAME

CHI::CacheObject - Contains information about cache entries

=head1 SYNOPSIS

    my $object = $cache->get_object($key);
    
    my $key        = $object->key();
    my $value      = $object->value();
    my $expires_at = $object->expires_at();
    my $created_at = $object->created_at();

    if ($object->is_expired()) { ... }

=head1 DESCRIPTION

The L<CHI|get_object> method returns this object if the key exists.  The object
will be returned even if the entry has expired, as long as it has not been
removed.

There is currently no public API for creating one of these objects directly.

=head1 METHODS

All methods are read-only. The get_* methods are provided for backward
compatibility with Cache::Cache's Cache::Object.

=over

=item key

The key.

=item value

The value.

=item expires_at

=item get_expires_at

Epoch time at which item expires.

=item created_at

=item get_created_at

Epoch time at which item was last written to.

=item is_expired

Returns boolean indicating whether item has expired. This may be
probabilistically determined if an L</expires_variance> was used.

=back

=cut
