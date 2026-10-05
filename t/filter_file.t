# vi:filetype=
#
# Regression test for JSON bodies that reach the filter as file buffers.
# The module sits right below the copy filter but didn't set
# r->filter_need_in_memory, so with sendfile on the copy filter passed file
# buffers through unread, the body filter skipped them as not in memory, and
# the raw JSON went out unrendered.

use lib 'lib';
use Test::Nginx::Socket;

plan tests => repeat_each() * 8;

no_shuffle();
run_tests();

__DATA__

=== TEST 1: static JSON file with sendfile on is rendered
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    sendfile on;
    location /data/ {
        alias html/;
        types { }
        default_type application/json;
        mustach_template "[{{a}}]";
    }
--- user_files
>>> a.json
{"a":"b"}
--- request
GET /data/a.json
--- response_body chop
[b]

=== TEST 2: proxy_cache miss and hit with sendfile on are rendered
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- http_config
    proxy_cache_path cache keys_zone=mustach:1m;
--- config
    sendfile on;
    location /backend {
        default_type application/json;
        return 200 '{"a":"b"}';
    }
    location /test {
        mustach_template "[{{a}}]";
        proxy_cache mustach;
        proxy_cache_valid 200 1m;
        add_header X-Cache $upstream_cache_status;
        proxy_pass http://127.0.0.1:$server_port/backend;
    }
--- pipelined_requests eval
["GET /test", "GET /test"]
--- response_body eval
["[b]", "[b]"]
--- raw_response_headers_like eval
["X-Cache: MISS", "X-Cache: HIT"]
