# vi:filetype=
#
# Regression test for mustach_max_json_size. The body filter held any upstream
# JSON in memory, twice while putting it together, with no limit. Now, like
# image_filter_buffer, a response over the limit (1m by default) gets a 500:
# up front when its Content-Length says so, otherwise as soon as it grows
# past the limit. 0 lifts the limit.

use lib 'lib';
use Test::Nginx::Socket;

plan tests => repeat_each() * 2 * blocks();

no_shuffle();
run_tests();

__DATA__

=== TEST 1: Content-Length over the limit
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /backend {
        default_type application/json;
        return 200 '{"a":"b","pad":"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"}';
    }
    location /test {
        mustach_template "[{{a}}]";
        mustach_max_json_size 32;
        proxy_pass http://127.0.0.1:$server_port/backend;
    }
--- request
GET /test
--- error_code: 500
--- error_log
larger than mustach_max_json_size 32

=== TEST 2: no Content-Length, grows past the limit
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
    load_module /etc/nginx/modules/ngx_http_echo_module.so;
--- config
    location /backend {
        default_type application/json;
        echo -n '{"a":"b","pad":"';
        echo_flush;
        echo_sleep 0.1;
        echo -n 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"}';
    }
    location /test {
        mustach_template "[{{a}}]";
        mustach_max_json_size 32;
        proxy_pass http://127.0.0.1:$server_port/backend;
        proxy_http_version 1.1;
        proxy_buffering off;
    }
--- request
GET /test
--- error_code: 500
--- error_log
larger than mustach_max_json_size 32

=== TEST 3: exactly at the limit is rendered
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /backend {
        default_type application/json;
        return 200 '{"a":"b","pad":"xxxxxxxxxxxxxx"}';
    }
    location /test {
        mustach_template "[{{a}}]";
        mustach_max_json_size 32;
        proxy_pass http://127.0.0.1:$server_port/backend;
    }
--- request
GET /test
--- response_body chop
[b]

=== TEST 4: the 1m default applies
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /data/ {
        alias html/;
        types { }
        default_type application/json;
    }
    location /test {
        mustach_template "[{{a}}]";
        proxy_pass http://127.0.0.1:$server_port/data/big.json;
    }
--- user_files eval
">>> big.json\n" . '{"a":"b","pad":"' . ('x' x 2000000) . '"}'
--- request
GET /test
--- error_code: 500
--- error_log
larger than mustach_max_json_size 1048576

=== TEST 5: 0 lifts the limit
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /data/ {
        alias html/;
        types { }
        default_type application/json;
    }
    location /test {
        mustach_template "[{{a}}]";
        mustach_max_json_size 0;
        proxy_pass http://127.0.0.1:$server_port/data/big.json;
    }
--- user_files eval
">>> big.json\n" . '{"a":"b","pad":"' . ('x' x 2000000) . '"}'
--- request
GET /test
--- response_body chop
[b]
