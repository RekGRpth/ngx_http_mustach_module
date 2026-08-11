# vi:filetype=
#
# Coverage for the mustach_type directive and its two non-default JSON
# backends (mustach_process_cjson / mustach_process_jansson in
# mustach-cjson.c / mustach-jansson.c). The rest of the suite only
# exercises the default json-c backend.

use lib 'lib';
use Test::Nginx::Socket;

plan tests => repeat_each() * 2 * blocks();

no_shuffle();
run_tests();

__DATA__

=== TEST 1: mustach_type cjson
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_content text/html;
        mustach_template '<ul>{{#people}}<li>{{firstName}} {{lastName}}</li>{{/people}}</ul>';
        mustach_type cjson;
        mustach_json '{"people":[{"firstName":"Yehuda","lastName":"Katz"},{"firstName":"Carl","lastName":"Lerche"}]}';
    }
--- request
    GET /test
--- response_body chop
<ul><li>Yehuda Katz</li><li>Carl Lerche</li></ul>

=== TEST 2: mustach_type jansson
# Currently broken: variable lookups always resolve to the whole JSON
# document instead of the named field's value. Root cause (confirmed via
# LD_DEBUG=bindings): libmustach.so links cjson + json-c + jansson into one
# shared object, and json-c's json_object_get(obj) (refcount increment,
# 1 arg) and jansson's json_object_get(obj, key) (field lookup, 2 args)
# share the same symbol name. The dynamic linker resolves mustach-jansson.c's
# calls to json-c's version process-wide, so the "key" argument is silently
# dropped and every lookup just returns the input object unchanged -- hence
# the whole document coming back instead of a field. This is an upstream
# mustach/json-c/jansson linking hazard (needs a fix in mustach-jansson.c
# in the sibling mustach repo, or a linking-scheme change), not a bug in
# this module's own code. Kept (skipped) so a future fix gets noticed.
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_content text/html;
        mustach_template '<ul>{{#people}}<li>{{firstName}} {{lastName}}</li>{{/people}}</ul>';
        mustach_type jansson;
        mustach_json '{"people":[{"firstName":"Yehuda","lastName":"Katz"},{"firstName":"Carl","lastName":"Lerche"}]}';
    }
--- request
    GET /test
--- response_body chop
<ul><li>Yehuda Katz</li><li>Carl Lerche</li></ul>
--- SKIP

=== TEST 3: mustach_type json-c (explicit, same as default)
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_content text/html;
        mustach_template '<ul>{{#people}}<li>{{firstName}} {{lastName}}</li>{{/people}}</ul>';
        mustach_type json-c;
        mustach_json '{"people":[{"firstName":"Yehuda","lastName":"Katz"},{"firstName":"Carl","lastName":"Lerche"}]}';
    }
--- request
    GET /test
--- response_body chop
<ul><li>Yehuda Katz</li><li>Carl Lerche</li></ul>

=== TEST 4: invalid mustach_type value is rejected
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_template "{{a}}";
        mustach_type bogus;
        mustach_json '{"a":"b"}';
    }
--- must_die
--- suppress_stderr
--- error_log
invalid value "bogus"
