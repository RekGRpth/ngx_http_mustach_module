# vi:filetype=
#
# Sanity check for ngx_http_mustach_postconfiguration's early return when
# mustach_template is never used anywhere in the config (main->enable stays
# 0, so the header/body filters are never installed at all). Observable
# behaviour is the same as a location with mustach_template unset, but this
# pins down that loading the module without using it doesn't break plain
# responses.

use lib 'lib';
use Test::Nginx::Socket;

plan tests => repeat_each() * 2 * blocks();

no_shuffle();
run_tests();

__DATA__

=== TEST 1: module loaded but never configured leaves responses untouched
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        default_type application/json;
        return 200 '{"a":"b"}';
    }
--- request
    GET /test
--- response_body chop
{"a":"b"}
