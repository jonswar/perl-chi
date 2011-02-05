#!/usr/bin/perl
use CHI;
use warnings;
use strict;

sub set_standard_keys_and_values {
    my $self = shift;

    my ( %keys, %values );
    my @mixed_chars = ( 32 .. 48, 57 .. 65, 90 .. 97, 122 .. 126, 240 );

    %keys = (
        'space'   => ' ',
        'newline' => "\n",
        'char'    => 'a',
        'zero'    => 0,
        'one'     => 1,
        'medium'  => 'medium',
        'mixed'   => join( "", map { chr($_) } @mixed_chars ),
        'empty'   => 'empty',
    );

    %values = map {
        ( $_, ref( $keys{$_} ) ? $keys{$_} : scalar( reverse( $keys{$_} ) ) )
    } keys(%keys);
    $values{empty} = '';

    return ( \%keys, \%values );
}

my $perm_cache = CHI->new(driver => 'File', root_dir => "permcache", on_set_error => 'die');
my ($keys, $values) = set_standard_keys_and_values();
foreach my $keyname (sort keys (%$keys)) {
    printf("%10s: %s\n", $keyname, $perm_cache->path_to_key($keys->{$keyname}));
}
