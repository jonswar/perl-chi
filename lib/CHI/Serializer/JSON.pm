# Default key serializer class, so that we don't have to depend on Data::Serializer.
# Recommend Data::Serializer for other serializers, rather than reinventing the wheel.
#
package CHI::Serializer::JSON;
use Moose;
use JSON;
use strict;
use warnings;

__PACKAGE__->meta->make_immutable;

my $json_version = JSON->VERSION;
my $json = $json_version < 2 ? JSON->new : JSON->new->utf8->canonical;

sub serialize {
    return $json_version < 2
      ? $json->objToJson( $_[1] )
      : $json->encode( $_[1] );
}

sub deserialize {
    return $json_version < 2
      ? $json->jsonToObj( $_[1] )
      : $json->decode( $_[1] );
}

1;
