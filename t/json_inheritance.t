# vi:filetype=
#
# Regression test for where mustach_json applies. It used to be allowed at
# http/server level and inherited by nested locations, but the content
# handler it installs is only set where the directive is written, so an
# inherited mustach_json silently did nothing. It now behaves like proxy_pass:
# location and if-in-location only, not inherited by nested locations, but
# kept by the unnamed blocks (if, limit_except) in which the enclosing
# location's handler keeps running.

use lib 'lib';
use Test::Nginx::Socket;

plan tests => repeat_each() * 2 * blocks();

no_shuffle();
run_tests();

__DATA__

=== TEST 1: mustach_json at http level is a configuration error
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- http_config
    mustach_json '{"a":"b"}';
--- config
    location /test {
        mustach_template "[{{a}}]";
    }
--- must_die
--- suppress_stderr
--- error_log
"mustach_json" directive is not allowed here

=== TEST 2: an if block inside the location keeps mustach_json
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_template "[{{a}}]";
        mustach_content text/plain;
        mustach_json '{"a":"b"}';
        if ($arg_x) {
            add_header X-If yes;
        }
    }
--- request
GET /test?x=1
--- response_body chop
[b]

=== TEST 3: a limit_except block inside the location keeps mustach_json
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_template "[{{a}}]";
        mustach_content text/plain;
        mustach_json '{"a":"b"}';
        limit_except POST {
            allow all;
        }
    }
--- request
GET /test
--- response_body chop
[b]

=== TEST 4: a nested location is an ordinary one, filtering with the inherited template
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /p/ {
        mustach_template "[{{a}}]";
        mustach_content text/plain;
        mustach_json '{"a":"handler"}';
        location /p/data/ {
            alias html/;
            types { }
            default_type application/json;
        }
    }
--- user_files
>>> a.json
{"a":"file"}
--- request
GET /p/data/a.json
--- response_body chop
[file]
