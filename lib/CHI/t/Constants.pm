package CHI::t::Constants;
use strict;
use warnings;
use CHI::Test;
use base qw(CHI::Test::Class);

sub test_import : Test(4) {
    {

        package Foo;
        use CHI::Constants qw(CHI_Meta_Namespace);
    }
    {

        package Bar;
        use CHI::Constants qw(:all);
    }
    {

        package Baz;
    }
    is( Foo::CHI_Meta_Namespace, '_CHI_METACACHE' );
    is( Bar::CHI_Meta_Namespace, '_CHI_METACACHE' );
    ok( Bar->can('CHI_Meta_Namespace') );
    ok( !Baz->can('CHI_Meta_Namespace') );
}

1;
