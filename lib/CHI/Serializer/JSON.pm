# Default key serializer class, so that we don't have to depend on Data::Serializer.
# Recommend Data::Serializer for other serializers, rather than reinventing the wheel.
#
package CHI::Serializer::JSON;
use CHI::Util qw(json_encode json_decode);
use Moose;
use strict;
use warnings;

__PACKAGE__->meta->make_immutable;

sub serialize {
    return json_encode( $_[1] );
}

sub deserialize {
    return json_decode( $_[1] );
}

1;
