package CHI::Driver::Wrapper;
use CHI::Util qw(dp);
use Carp;
use strict;
use warnings;

# Call the specified $method on the native driver class, e.g. CHI::Driver::Memory.  SUPER
# cannot be used because it refers to the superclass(es) of the current package and not to
# the superclass(es) of the object - see perlobj.
#
sub call_native_driver {
    my $self                 = shift;
    my $method               = shift;
    my $native_driver_method = join( "::", $self->driver_class, $method );
    $self->$native_driver_method(@_);
}

my %wrapped_driver_classes;

# Get the wrapper class for this driver class, creating it if necessary. Called from CHI->new.
#
sub create_wrapped_driver_class {
    my ( $proto, $driver_class ) = @_;
    carp "internal class method" if ref($proto);

    if ( !$wrapped_driver_classes{$driver_class} ) {
        my $wrapped_driver_class      = "CHI::Wrapped::$driver_class";
        my $wrapped_driver_class_decl = join( "\n",
            "package $wrapped_driver_class;",
            "use strict;",
            "use warnings;",
            "use base qw(CHI::Driver::Wrapper $driver_class);",
            "sub driver_class { '$driver_class' }",
            "1;" );
        eval($wrapped_driver_class_decl);    ## no critic ProhibitStringyEval
        die $@ if $@;                        ## no critic RequireCarping
        $wrapped_driver_classes{$driver_class} = $wrapped_driver_class;
    }
    return $wrapped_driver_classes{$driver_class};
}

1;

__END__

=pod

=head1 NAME

CHI::Driver::Wrapper -- wrapper class for all CHI drivers

=head1 DESCRIPTION

This package contains 'wrappers' for certain driver methods. The wrappers will
be called first, and then have the opportunity to call the native driver
methods.

How this works: when each driver is used for the first time, e.g.
CHI::Driver::Memory:

   my $cache = CHI->new('Memory');

CHI autogenerates a new class called CHI::Wrapped::CHI::Driver::Memory, which
inherits from

   ('CHI::Driver::Wrapper', 'CHI::Driver::Memory')

then blesses the actual cache object (and future cache objects of this driver)
as CHI::Wrapped::CHI::Driver::Memory.

Now, when we call a method like get() or remove(), CHI::Driver::Wrapper has an
opportunity to handle it first; if not, it goes to the native driver, in this
case CHI::Driver::Memory.

This is an accidental reinvention of Moose's runtime application of roles to
instances (see Moose::Cookbook::Roles::Recipe3), which is not currently
supported by Mouse.

=head1 SEE ALSO

CHI

=head1 AUTHOR

Jonathan Swartz

=head1 COPYRIGHT & LICENSE

Copyright (C) 2007 Jonathan Swartz, all rights reserved.

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
