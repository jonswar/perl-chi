package CHI::Driver::Null;
use Moose;
use strict;
use warnings;

extends 'CHI::Driver';
__PACKAGE__->meta->make_immutable();

sub fetch          { undef }
sub store          { undef }
sub remove         { undef }
sub clear          { undef }
sub get_keys       { return () }
sub get_namespaces { return () }

1;

__END__

=pod

=head1 NAME

CHI::Driver::Null - nothing is cached

=head1 SYNOPSIS

    use CHI;

    my $cache = CHI->new(driver => 'Null');
    $cache->set('key', 5);
    my $value = $cache->get('key');   # returns undef

=head1 DESCRIPTION

This cache driver implements the full CHI interface without ever actually
storing items. Useful for disabling caching in an application, for example.

=head1 AUTHOR

Jonathan Swartz

=head1 COPYRIGHT & LICENSE

Copyright (C) 2007 Jonathan Swartz.

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
