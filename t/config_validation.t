# vi:filetype=
#
# Regression test for the config-time check that mustach_json requires
# mustach_template in the same location. Without it, ngx_http_mustach_handler
# passes a NULL location->template into ngx_http_complex_value(), which
# dereferences it unconditionally and segfaults the worker on every request.

use lib 'lib';
use Test::Nginx::Socket;

plan tests => repeat_each() * 4;

no_shuffle();
run_tests();

__DATA__

=== TEST 1: mustach_json without mustach_template fails to start
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_json '{"a":"b"}';
    }
--- must_die
--- suppress_stderr
--- error_log
"mustach_json" requires "mustach_template" to be set in the same location

=== TEST 2: mustach_json with mustach_template starts fine
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_template "{{a}}";
        mustach_json '{"a":"b"}';
    }
--- request
    GET /test
--- response_body chop
b
