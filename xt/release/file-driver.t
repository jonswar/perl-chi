#!perl
#
use strict;
use warnings;
use File::Basename;
use File::Temp qw(tempdir);
use Test::More;
use Test::Exception;
use CHI;

my $root_dir = tempdir( "file-digest-XXXX", TMPDIR => 1, CLEANUP => 1 );
my $cache;
my ($keys, $values) = set_standard_keys_and_values();
my @keynames = sort keys (%$keys);

plan tests => (scalar(@keynames) * 2 + 1);

# Test key_digest (old name for key_digester) and file_extension
#
$cache = CHI->new(
    driver         => 'File',
    root_dir       => $root_dir,
    key_digest     => 'SHA-1',
    file_extension => '.sha'
);
my $key  = scalar( 'ab' x 256 );
my $file = basename( $cache->path_to_key($cache->transform_key($key)) );
is( $file, 'db62ffe116024a7a4e1bd949c0e30dbae9b5db77.sha', 'SHA-1 digest' );

# Test that we can retrieve from a permanent cache in this directory.  If
# key escaping or metadata format changes between versions, this will break
# - we at least want to know about it to warn users.
#
my $perm_cache = CHI->new(driver => 'File', root_dir => "xt/release/permcache");
foreach my $keyname (@keynames) {
    is($perm_cache->get($keys->{$keyname}), $values->{$keyname}, "get $keyname from perm test cache");
    my $obj = $perm_cache->get_object($keys->{$keyname});
    is($obj->created_at, 1275657865);
}

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

