package CHI::Driver::Role::Universal;
use CHI::Constants qw(CHI_Meta_Namespace);
use Moo::Role;
use strict;
use warnings;

around 'get_namespaces' => sub {
    my $orig = shift;
    my $self = shift;

    # Call driver get_namespaces, then filter out meta-namespace
    return grep { $_ ne CHI_Meta_Namespace } $self->$orig(@_);
};

foreach my $method (qw(remove append)) {
    around $method => sub {
        my ( $orig, $self, $key, @rest ) = @_;

        # Call transform_key before passing to method
        return $self->$orig( $self->transform_key($key), @rest );
    };
}

1;

__END__
