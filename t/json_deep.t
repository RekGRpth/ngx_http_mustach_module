# vi:filetype=
#
# Regression test for quadratic / recursive work on large JSON:
# - jsmn walked up through every already-closed ancestor on each closing
#   bracket, quadratic in nesting depth (a 1MB `[[[...]]]` took minutes), and
#   the recursive skip() could overflow the worker's stack on such input;
# - skip() re-walked a whole subtree on every name lookup, so a section over
#   a big array that looks up a root-level name placed after it was quadratic
#   in the array size.
# Both bodies come from a proxied static file: they're far beyond what fits
# in a config-file string for mustach_json.

use lib 'lib';
use Test::Nginx::Socket;

plan tests => 2 * blocks();

no_shuffle();
run_tests();

__DATA__

=== TEST 1: deeply nested JSON is parsed in linear time
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /data/ {
        alias html/;
        types { }
        default_type application/json;
    }
    location /test {
        mustach_template "{{a}}";
        proxy_pass http://127.0.0.1:$server_port/data/deep.json;
        proxy_max_temp_file_size 0;
    }
--- user_files eval
">>> deep.json\n" . '{"x":' . ('[' x 1000000) . (']' x 1000000) . ',"a":"ok"}'
--- request
    GET /test
--- timeout: 10
--- response_body chop
ok

=== TEST 2: lookup of a root name after a big array is not quadratic
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /data/ {
        alias html/;
        types { }
        default_type application/json;
    }
    location /test {
        mustach_template "{{#items}}{{z}}{{/items}}";
        proxy_pass http://127.0.0.1:$server_port/data/wide.json;
        proxy_max_temp_file_size 0;
    }
--- user_files eval
">>> wide.json\n" . '{"items":[' . join(',', ('{}') x 200000) . '],"z":"!"}'
--- request
    GET /test
--- timeout: 10
--- response_body eval
"!" x 200000
