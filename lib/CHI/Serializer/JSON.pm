# Default key serializer class, so that we don't have to depend on Data::Serializer.
# Recommend Data::Serializer for other serializers, rather than reinventing the wheel.
#
package CHI::Serializer::JSON;
use Moose;
use JSON::XS;
use strict;
use warnings;

__PACKAGE__->meta->make_immutable;

my $json = JSON::XS->new->utf8->canonical;

sub serialize {
    return $json->encode( $_[1] );
}

sub deserialize {
    return $json->decode( $_[1] );
}

1;
