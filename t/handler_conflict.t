# vi:filetype=
#
# Regression test for the config-time check that mustach_json does not
# silently lose to another content handler already claimed for the same
# location. It used to install ngx_http_mustach_handler only if
# core->handler was still unset, so a location combining mustach_json with
# e.g. proxy_pass would keep the OTHER handler with no warning at all,
# leaving mustach_json's value completely unused.

use lib 'lib';
use Test::Nginx::Socket;

plan tests => repeat_each() * 4;

no_shuffle();
run_tests();

__DATA__

=== TEST 1: mustach_json after proxy_pass fails to start
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_template "{{a}}";
        proxy_pass http://127.0.0.1:1;
        mustach_json '{"a":"b"}';
    }
--- must_die
--- suppress_stderr
--- error_log
"mustach_json" directive conflicts with another content handler already set for this location

=== TEST 2: mustach_json alone still starts fine
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
