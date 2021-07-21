# vi:filetype=

use lib 'lib';
use Test::Nginx::Socket;

repeat_each(2);

plan tests => repeat_each() * 2 * blocks();

#$Test::Nginx::LWP::LogLevel = 'debug';

our $main_config = <<'_EOC_';
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
    load_module /etc/nginx/modules/ngx_http_eval_module.so;
_EOC_

no_shuffle();
run_tests();

__DATA__

=== TEST 1: content json
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template "{{a}}";
        mustach_content text/html;
        return 200 '{"a":"b"}';
    }
--- request
    GET /test
--- response_body chop
b
=== TEST 2: content json
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template '<ul>{{#people}}<li>{{firstName}} {{lastName}}</li>{{/people}}</ul>';
        mustach_content text/html;
        return 200 '{"people":[{"firstName":"Yehuda","lastName":"Katz"},{"firstName":"Carl","lastName":"Lerche"},{"firstName":"Alan","lastName":"Johnson"}]}';
    }
--- request
    GET /test
--- response_body chop
<ul><li>Yehuda Katz</li><li>Carl Lerche</li><li>Alan Johnson</li></ul>
=== TEST 3: variable json
--- main_config eval: $::main_config
--- config
    location /test {
        mustach_template "{{a}}";
        mustach_content text/html;
        mustach_json '{"a":"b"}';
    }
--- request
    GET /test
--- response_body chop
b
=== TEST 4: variable json
--- main_config eval: $::main_config
--- config
    location /test {
        mustach_template '<ul>{{#people}}<li>{{firstName}} {{lastName}}</li>{{/people}}</ul>';
        mustach_content text/html;
        mustach_json '{"people":[{"firstName":"Yehuda","lastName":"Katz"},{"firstName":"Carl","lastName":"Lerche"},{"firstName":"Alan","lastName":"Johnson"}]}';
    }
--- request
    GET /test
--- response_body chop
<ul><li>Yehuda Katz</li><li>Carl Lerche</li><li>Alan Johnson</li></ul>
=== TEST 5: eval json
--- main_config eval: $::main_config
--- config
    location /test {
        eval $json {
            return 200 '{"a":"b"}';
        }
        mustach_template "{{a}}";
        mustach_content text/html;
        mustach_json $json;
    }
--- request
    GET /test
--- response_body chop
b
=== TEST 6: eval json
--- main_config eval: $::main_config
--- config
    location /test {
        eval $json {
            return 200 '{"people":[{"firstName":"Yehuda","lastName":"Katz"},{"firstName":"Carl","lastName":"Lerche"},{"firstName":"Alan","lastName":"Johnson"}]}';
        }
        mustach_template '<ul>{{#people}}<li>{{firstName}} {{lastName}}</li>{{/people}}</ul>';
        mustach_content text/html;
        mustach_json $json;
    }
--- request
    GET /test
--- response_body chop
<ul><li>Yehuda Katz</li><li>Carl Lerche</li><li>Alan Johnson</li></ul>
=== TEST 7: eval template
--- main_config eval: $::main_config
--- config
    location /test {
        eval $template {
            return 200 '{{a}}';
        }
        mustach_template $template;
        mustach_content text/html;
        mustach_json '{"a":"b"}';
    }
--- request
    GET /test
--- response_body chop
b
=== TEST 8: eval template
--- main_config eval: $::main_config
--- config
    location /test {
        eval $template {
            return 200 '<ul>{{#people}}<li>{{firstName}} {{lastName}}</li>{{/people}}</ul>';
        }
        mustach_template $template;
        mustach_content text/html;
        mustach_json '{"people":[{"firstName":"Yehuda","lastName":"Katz"},{"firstName":"Carl","lastName":"Lerche"},{"firstName":"Alan","lastName":"Johnson"}]}';
    }
--- request
    GET /test
--- response_body chop
<ul><li>Yehuda Katz</li><li>Carl Lerche</li><li>Alan Johnson</li></ul>
