# vi:filetype=
#
# Regression test for name lookups in objects with many members. They were a
# linear scan, so a loop over a big array that looks up a name not found in
# its items -- and so searched again in a big enclosing object -- was
# quadratic: 27s of worker time for one 840KB request body. Objects with more
# than a few members now get a hash index on their first lookup; lookups
# still compare raw key text, and the first of duplicate keys still wins.

use lib 'lib';
use Test::Nginx::Socket;

plan tests => repeat_each() * 2 * blocks();

no_shuffle();
run_tests();

__DATA__

=== TEST 1: many root keys x big array, a name missing from the items
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        client_max_body_size 2m;
        client_body_buffer_size 2m;
        mustach_template "{{#items}}{{z}}{{/items}}";
        mustach_content text/plain;
        mustach_json $request_body;
    }
--- request eval
"POST /test\n" . '{' . join(',', map { qq{"k$_":0} } 1..50000) . ',"items":[' . join(',', ('{}') x 100000) . ']}'
--- timeout: 10
--- response_body chop

=== TEST 2: the first of duplicate keys wins in a big object
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_template "[{{k3}}][{{k12}}][{{nope}}]";
        mustach_content text/plain;
        mustach_json '{"k1":1,"k2":2,"k3":"first","k4":4,"k5":5,"k6":6,"k7":7,"k8":8,"k9":9,"k10":10,"k3":"second","k11":11,"k12":"last"}';
    }
--- request
GET /test
--- response_body chop
[first][last][]

=== TEST 3: dotted lookup through nested big objects
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_template "[{{o.p.q}}][{{o.p.nope}}][{{#o.p}}{{q}}{{a1}}{{/o.p}}]";
        mustach_content text/plain;
        mustach_json '{"a1":"root","o":{"a1":1,"a2":2,"a3":3,"a4":4,"a5":5,"a6":6,"a7":7,"a8":8,"a9":9,"p":{"b1":1,"b2":2,"b3":3,"b4":4,"b5":5,"b6":6,"b7":7,"b8":8,"b9":9,"q":"deep"}}}';
    }
--- request
GET /test
--- response_body chop
[deep][][deeproot]
