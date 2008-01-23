#!perl -w
use strict;
use warnings;
use lib 't/lib';
use CHI::t::Driver::Multilevel;
CHI::t::Driver::Multilevel->runtests;
