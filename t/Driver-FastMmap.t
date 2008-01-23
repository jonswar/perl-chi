#!perl -w
use strict;
use warnings;
use lib 't/lib';
use CHI::t::Driver::FastMmap;
CHI::t::Driver::FastMmap->runtests;
