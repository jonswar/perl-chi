package CHI::CacheObject;
use strict;
use warnings;
use base qw(Class::Accessor::Fast);

__PACKAGE__->mk_ro_accessors(
    qw(key value created_at expires_at early_expires_at _is_serialized));

sub is_expired {
    my ($self) = @_;

    my $time = $CHI::Driver::Test_Time || time();
    return $time >= $self->expires_at;
}

1;

__END__

=pod

=head1 NAME

CHI::CacheObject -- Contains information about cache entries.

=head1 SYNOPSIS

    my $object = $cache->get_object($key);
    
    my $key        = $object->key();
    my $value      = $object->value();
    my $expires_at = $object->expires_at();
    my $created_at = $object->created_at();

=head1 DESCRIPTION

The L<CHI|get_object> method returns this object if the key exists.  The object will be
returned even if the entry has expired, as long as it has not been removed.

=head1 METHODS

All methods are read-only.

=over

=item key

=item value

=item expires_at

=item created_at

=back

=head1 SEE ALSO

CHI

=head1 AUTHOR

Jonathan Swartz

=head1 COPYRIGHT & LICENSE

Copyright (C) 2007 Jonathan Swartz, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
