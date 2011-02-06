#!/usr/bin/perl
#
# Write permcache - for xt/author/file-driver.t and possibly other tests.
#
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
        'large'   => scalar( 'ab' x 256 ),
        'empty'   => 'empty',
    );

    %values = map {
        ( $_, ref( $keys{$_} ) ? $keys{$_} : scalar( reverse( $keys{$_} ) ) )
    } keys(%keys);
    $values{empty} = '';

    return ( \%keys, \%values );
}

my ( $keys, $values ) = set_standard_keys_and_values();
my $perm_cache =
  CHI->new( driver => 'File', root_dir => "permcache", on_set_error => 'die' );
$perm_cache->clear();
foreach my $keyname ( sort keys(%$keys) ) {
    $perm_cache->set( $keys->{$keyname}, $values->{$keyname} );

    use d;
    dp [ $keys->{$keyname}, $perm_cache->path_to_key( $keys->{$keyname} ) ];
}
