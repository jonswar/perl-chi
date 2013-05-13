package CHI::Driver::Role::IsSubcache;
use Moo::Role;
use strict;
use warnings;

has 'parent_cache'  => ( is => 'ro', weak_ref => 1 );
has 'subcache_type' => ( is => 'ro' );

1;
