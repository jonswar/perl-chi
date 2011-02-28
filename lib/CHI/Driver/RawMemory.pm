package CHI::Driver::RawMemory;
use Moose;
use strict;
use warnings;

extends 'CHI::Driver::Memory';

has 'serializer' => ( is => 'ro', default => undef, init_arg => undef );

__PACKAGE__->meta->make_immutable();

1;

__END__

=pod

=head1 NAME

CHI::Driver::RawMemory - In-process memory cache that stores direct references

=head1 SYNOPSIS

    use CHI;

    my $hash = {};
    my $cache = CHI->new( driver => 'RawMemory', datastore => $hash );

    my $cache = CHI->new( driver => 'RawMemory', global => 1 );

=head1 DESCRIPTION

This is a subclass of L<CHI::Driver::Memory|CHI::Driver::Memory> that stores
references directly instead of deep-copying on set and get.  This makes the
cache significantly faster (as it avoids a serialization and deserialization),
but unlike most drivers, modifications to the original data structure I<will>
affect the data structure stored in the cache, and vica versa. e.g.

    my $cache = CHI->new( driver => 'RawMemory', global => 1 );
    my $lst = ['foo'];
    $cache->set('key' => $lst);   # stores $lst directly, no copying
    $cache->get('key');   # returns ['foo']
    $lst->[0] = 'bar';
    $cache->get('key');   # returns ['bar']!

Besides this change, constructor options and behavior are the same as
L<CHI::Driver::Memory|CHI::Driver::Memory>.

=cut
