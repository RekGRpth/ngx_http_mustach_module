# vi:filetype=
#
# Regression test for the charset of a rendered response. The upstream's
# Content-Type charset ("application/json; charset=utf-8") stays in
# r->headers_out.charset, and the header filter appends it to the type: a
# mustach_content with a charset of its own came out with two,
# "text/html; charset=koi8-r; charset=utf-8". Such a type now replaces the
# upstream's charset; a type without one still gets it. Without
# mustach_content at all, the upstream's type itself came out with the
# charset twice, "application/json; charset=utf-8; charset=utf-8".

use lib 'lib';
use Test::Nginx::Socket;

plan tests => repeat_each() * 2 * blocks();

no_shuffle();
run_tests();

__DATA__

=== TEST 1: mustach_content with its own charset replaces the upstream one
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /backend {
        default_type application/json;
        charset utf-8;
        charset_types application/json;
        return 200 '{"a":"b"}';
    }
    location /test {
        mustach_template "[{{a}}]";
        mustach_content "text/html; charset=koi8-r";
        proxy_pass http://127.0.0.1:$server_port/backend;
    }
--- request
GET /test
--- response_headers
Content-Type: text/html; charset=koi8-r

=== TEST 2: mustach_content without a charset keeps the upstream one
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /backend {
        default_type application/json;
        charset utf-8;
        charset_types application/json;
        return 200 '{"a":"b"}';
    }
    location /test {
        mustach_template "[{{a}}]";
        mustach_content text/html;
        proxy_pass http://127.0.0.1:$server_port/backend;
    }
--- request
GET /test
--- response_headers
Content-Type: text/html; charset=utf-8

=== TEST 3: without mustach_content the upstream type keeps a single charset
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /backend {
        default_type application/json;
        charset utf-8;
        charset_types application/json;
        return 200 '{"a":"b"}';
    }
    location /test {
        mustach_template "[{{a}}]";
        proxy_pass http://127.0.0.1:$server_port/backend;
    }
--- request
GET /test
--- response_headers
Content-Type: application/json; charset=utf-8

=== TEST 4: HEAD without mustach_content keeps a single charset too
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /backend {
        default_type application/json;
        charset utf-8;
        charset_types application/json;
        return 200 '{"a":"b"}';
    }
    location /test {
        mustach_template "[{{a}}]";
        proxy_pass http://127.0.0.1:$server_port/backend;
    }
--- request
HEAD /test
--- response_headers
Content-Type: application/json; charset=utf-8
