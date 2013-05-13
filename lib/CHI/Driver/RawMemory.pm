package CHI::Driver::RawMemory;
use Moo;
use strict;
use warnings;

extends 'CHI::Driver::Memory';

has 'serializer' => ( is => 'ro', init_arg => undef );

sub append {
    my ( $self, $key, $new ) = @_;

    return "append not yet supported in this driver";
}

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
references to data structures directly instead of serializing / deserializing. 
This makes the cache faster at getting and setting complex data structures, but
unlike most drivers, modifications to the original data structure I<will>
affect the data structure stored in the cache, and vice versa. e.g.

    my $cache = CHI->new( driver => 'Memory', global => 1 );
    my $lst = ['foo'];
    $cache->set('key' => $lst);   # serializes $lst before storing
    $cache->get('key');   # returns ['foo']
    $lst->[0] = 'bar';
    $cache->get('key');   # returns ['foo']

    my $cache = CHI->new( driver => 'RawMemory', global => 1 );
    my $lst = ['foo'];
    $cache->set('key' => $lst);   # stores $lst directly
    $cache->get('key');   # returns ['foo']
    $lst->[0] = 'bar';
    $cache->get('key');   # returns ['bar']!

=head1 CONSTRUCTOR OPTIONS

Same as L<CHI::Driver::Memory|CHI::Driver::Memory>.

=head1 SIZE AWARENESS

For the purpose of L<size-awareness|CHI/SIZE AWARENESS>, all items count as
size 1 for this driver. (Because data structures are not serialized, there's no
good way to determine their size.)

    # Keep a maximum of 10 items in cache
    #
    my $cache = CHI->new( driver => 'RawMemory', datastore => {}, max_size => 10 );

=head1 ACKNOWLEDGMENTS

Thanks to Yuval Kogman whose L<Cache::Ref> inspired me to do this.

=head1 SEE ALSO

L<CHI::Driver::Memory>, L<CHI>

=cut
