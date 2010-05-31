package CHI::Driver::Role::Universal;
use CHI::Constants qw(CHI_Meta_Namespace);
use Moose::Role;
use strict;
use warnings;

around 'get_namespaces' => sub {
    my $orig = shift;
    my $self = shift;

    # Call driver get_namespaces, then filter out meta-namespace
    return grep { $_ ne CHI_Meta_Namespace } $self->$orig(@_);
};

around 'remove' => sub {
    my ( $orig, $self, $key ) = @_;

    # Call transform_key before passing to remove
    return $self->$orig( $self->transform_key($key) );
};

1;

__END__

=pod

=head1 NAME

CHI::Driver::Role::Universal -- Universal role applied as the innermost role to
all CHI drivers

=head1 AUTHOR

Jonathan Swartz

=head1 COPYRIGHT & LICENSE

Copyright (C) 2007 Jonathan Swartz, all rights reserved.

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
