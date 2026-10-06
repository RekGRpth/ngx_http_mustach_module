# vi:filetype=
#
# Regression test for the slice module in front of a rendering location. slice
# fetches the response in ranges: the main request gets the first piece, its
# body ending with last_in_chain rather than last_buf, and subrequests fetch
# the rest. This filter took last_in_chain for the end of the JSON and rendered
# the first piece alone: 500 "invalid json". The rest never passes through the
# main request's filter, so the JSON can't be had whole: the response is now
# sent as it is, subrequest pieces included, with a warning.

use lib 'lib';
use Test::Nginx::Socket;

plan tests => repeat_each() * 4 * blocks();

no_shuffle();
run_tests();

__DATA__

=== TEST 1: a sliced response passes through whole, with a warning
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /data/ {
        alias html/;
        types { }
        default_type application/json;
    }
    location /test {
        slice 16;
        mustach_template "[{{a}}]";
        proxy_set_header Range $slice_range;
        proxy_pass http://127.0.0.1:$server_port/data/a.json;
    }
--- user_files
>>> a.json
{"a":"first-second-and-more"}
--- request
GET /test
--- response_body
{"a":"first-second-and-more"}
--- error_log
not rendering a response assembled from subrequests
--- no_error_log
[error]
