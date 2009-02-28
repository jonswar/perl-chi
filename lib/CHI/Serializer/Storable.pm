# Default serializer class, so that we don't have to depend on Data::Serializer.
# Recommend Data::Serializer for other serializers, rather than reinventing the wheel.
#
package CHI::Serializer::Storable;
use Mouse;
use Storable;
use strict;
use warnings;

sub serialize {
    return Storable::freeze( $_[1] );
}

sub deserialize {
    return Storable::thaw( $_[1] );
}

1;
