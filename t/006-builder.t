use strict;
use warnings;

use Test::More tests => 1;
use Arepa::Builder;

eval {
    Arepa::Builder->ui_module("Arepa::UI::IDontExist");
};
ok($@, "You shouldn't be able to set an invalid UI module");
