# vi:filetype=

use lib 'lib';
use Test::Nginx::Socket;

repeat_each(2);

plan tests => repeat_each() * 2 * blocks();

#$Test::Nginx::LWP::LogLevel = 'debug';

our $main_config = <<'_EOC_';
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
_EOC_

no_shuffle();
run_tests();

__DATA__

=== TEST 1: Truthy
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template "\"{{#boolean}}This should be rendered.{{/boolean}}\"";
        mustach_content text/html;
        return 200 '{
        "boolean": true
      }';
    }
--- request
    GET /test
--- response_body eval
"\"This should be rendered.\""
=== TEST 2: Falsey
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template "\"{{#boolean}}This should not be rendered.{{/boolean}}\"";
        mustach_content text/html;
        return 200 '{
        "boolean": false
      }';
    }
--- request
    GET /test
--- response_body eval
"\"\""
=== TEST 3: Null is falsey
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template "\"{{#null}}This should not be rendered.{{/null}}\"";
        mustach_content text/html;
        return 200 '{
        "null": null
      }';
    }
--- request
    GET /test
--- response_body eval
"\"\""
=== TEST 4: Context
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template "\"{{#context}}Hi {{name}}.{{/context}}\"";
        mustach_content text/html;
        return 200 '{
        "context": {
          "name": "Joe"
        }
      }';
    }
--- request
    GET /test
--- response_body eval
"\"Hi Joe.\""
=== TEST 5: Parent contexts
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template "\"{{#sec}}{{a}}, {{b}}, {{c.d}}{{/sec}}\"";
        mustach_content text/html;
        return 200 '{
        "a": "foo",
        "b": "wrong",
        "sec": {
          "b": "bar"
        },
        "c": {
          "d": "baz"
        }
      }';
    }
--- request
    GET /test
--- response_body eval
"\"foo, bar, baz\""
=== TEST 6: Variable test
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template "\"{{#foo}}{{.}} is {{foo}}{{/foo}}\"";
        mustach_content text/html;
        return 200 '{
        "foo": "bar"
      }';
    }
--- request
    GET /test
--- response_body eval
"\"bar is bar\""
=== TEST 7: List Contexts
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template "{{#tops}}{{#middles}}{{tname.lower}}{{mname}}.{{#bottoms}}{{tname.upper}}{{mname}}{{bname}}.{{/bottoms}}{{/middles}}{{/tops}}";
        mustach_content text/html;
        return 200 '{
        "tops": [
          {
            "tname": {
              "upper": "A",
              "lower": "a"
            },
            "middles": [
              {
                "mname": "1",
                "bottoms": [
                  {
                    "bname": "x"
                  },
                  {
                    "bname": "y"
                  }
                ]
              }
            ]
          }
        ]
      }';
    }
--- request
    GET /test
--- response_body eval
"a1.A1x.A1y."
=== TEST 8: Deeply Nested Contexts
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template "{{#a}}\n{{one}}\n{{#b}}\n{{one}}{{two}}{{one}}\n{{#c}}\n{{one}}{{two}}{{three}}{{two}}{{one}}\n{{#d}}\n{{one}}{{two}}{{three}}{{four}}{{three}}{{two}}{{one}}\n{{#five}}\n{{one}}{{two}}{{three}}{{four}}{{five}}{{four}}{{three}}{{two}}{{one}}\n{{one}}{{two}}{{three}}{{four}}{{.}}6{{.}}{{four}}{{three}}{{two}}{{one}}\n{{one}}{{two}}{{three}}{{four}}{{five}}{{four}}{{three}}{{two}}{{one}}\n{{/five}}\n{{one}}{{two}}{{three}}{{four}}{{three}}{{two}}{{one}}\n{{/d}}\n{{one}}{{two}}{{three}}{{two}}{{one}}\n{{/c}}\n{{one}}{{two}}{{one}}\n{{/b}}\n{{one}}\n{{/a}}\n";
        mustach_content text/html;
        return 200 '{
        "a": {
          "one": 1
        },
        "b": {
          "two": 2
        },
        "c": {
          "three": 3,
          "d": {
            "four": 4,
            "five": 5
          }
        }
      }';
    }
--- request
    GET /test
--- response_body eval
"1\n121\n12321\n1234321\n123454321\n12345654321\n123454321\n1234321\n12321\n121\n1\n"
=== TEST 9: List
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template "\"{{#list}}{{item}}{{/list}}\"";
        mustach_content text/html;
        return 200 '{
        "list": [
          {
            "item": 1
          },
          {
            "item": 2
          },
          {
            "item": 3
          }
        ]
      }';
    }
--- request
    GET /test
--- response_body eval
"\"123\""
=== TEST 10: Empty List
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template "\"{{#list}}Yay lists!{{/list}}\"";
        mustach_content text/html;
        return 200 '{
        "list": [
        ]
      }';
    }
--- request
    GET /test
--- response_body eval
"\"\""
=== TEST 11: Doubled
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template "{{#bool}}\n* first\n{{/bool}}\n* {{two}}\n{{#bool}}\n* third\n{{/bool}}\n";
        mustach_content text/html;
        return 200 '{
        "bool": true,
        "two": "second"
      }';
    }
--- request
    GET /test
--- response_body eval
"* first\n* second\n* third\n"
=== TEST 12: Nested (Truthy)
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template "| A {{#bool}}B {{#bool}}C{{/bool}} D{{/bool}} E |";
        mustach_content text/html;
        return 200 '{
        "bool": true
      }';
    }
--- request
    GET /test
--- response_body eval
"| A B C D E |"
=== TEST 13: Nested (Falsey)
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template "| A {{#bool}}B {{#bool}}C{{/bool}} D{{/bool}} E |";
        mustach_content text/html;
        return 200 '{
        "bool": false
      }';
    }
--- request
    GET /test
--- response_body eval
"| A  E |"
=== TEST 14: Context Misses
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template "[{{#missing}}Found key 'missing'!{{/missing}}]";
        mustach_content text/html;
        return 200 '{
      }';
    }
--- request
    GET /test
--- response_body eval
"[]"
=== TEST 15: Implicit Iterator - String
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template "\"{{#list}}({{.}}){{/list}}\"";
        mustach_content text/html;
        return 200 '{
        "list": [
          "a",
          "b",
          "c",
          "d",
          "e"
        ]
      }';
    }
--- request
    GET /test
--- response_body eval
"\"(a)(b)(c)(d)(e)\""
=== TEST 16: Implicit Iterator - Integer
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template "\"{{#list}}({{.}}){{/list}}\"";
        mustach_content text/html;
        return 200 '{
        "list": [
          1,
          2,
          3,
          4,
          5
        ]
      }';
    }
--- request
    GET /test
--- response_body eval
"\"(1)(2)(3)(4)(5)\""
=== TEST 17: Implicit Iterator - Decimal
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template "\"{{#list}}({{.}}){{/list}}\"";
        mustach_content text/html;
        return 200 '{
        "list": [
          1.1,
          2.2,
          3.3,
          4.4,
          5.5
        ]
      }';
    }
--- request
    GET /test
--- response_body eval
"\"(1.1)(2.2)(3.3)(4.4)(5.5)\""
=== TEST 18: Implicit Iterator - Array
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template "\"{{#list}}({{#.}}{{.}}{{/.}}){{/list}}\"";
        mustach_content text/html;
        return 200 '{
        "list": [
          [
            1,
            2,
            3
          ],
          [
            "a",
            "b",
            "c"
          ]
        ]
      }';
    }
--- request
    GET /test
--- response_body eval
"\"(123)(abc)\""
=== TEST 19: Dotted Names - Truthy
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template "\"{{#a.b.c}}Here{{/a.b.c}}\" == \"Here\"";
        mustach_content text/html;
        return 200 '{
        "a": {
          "b": {
            "c": true
          }
        }
      }';
    }
--- request
    GET /test
--- response_body eval
"\"Here\" == \"Here\""
=== TEST 20: Dotted Names - Falsey
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template "\"{{#a.b.c}}Here{{/a.b.c}}\" == \"\"";
        mustach_content text/html;
        return 200 '{
        "a": {
          "b": {
            "c": false
          }
        }
      }';
    }
--- request
    GET /test
--- response_body eval
"\"\" == \"\""
=== TEST 21: Dotted Names - Broken Chains
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template "\"{{#a.b.c}}Here{{/a.b.c}}\" == \"\"";
        mustach_content text/html;
        return 200 '{
        "a": {
        }
      }';
    }
--- request
    GET /test
--- response_body eval
"\"\" == \"\""
=== TEST 22: Surrounding Whitespace
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template " | {{#boolean}}\t|\t{{/boolean}} | \n";
        mustach_content text/html;
        return 200 '{
        "boolean": true
      }';
    }
--- request
    GET /test
--- response_body eval
" | \t|\t | \n"
=== TEST 23: Internal Whitespace
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template " | {{#boolean}} {{! Important Whitespace }}\n {{/boolean}} | \n";
        mustach_content text/html;
        return 200 '{
        "boolean": true
      }';
    }
--- request
    GET /test
--- response_body eval
" |  \n  | \n"
=== TEST 24: Indented Inline Sections
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template " {{#boolean}}YES{{/boolean}}\n {{#boolean}}GOOD{{/boolean}}\n";
        mustach_content text/html;
        return 200 '{
        "boolean": true
      }';
    }
--- request
    GET /test
--- response_body eval
" YES\n GOOD\n"
=== TEST 25: Standalone Lines
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template "| This Is\n{{#boolean}}\n|\n{{/boolean}}\n| A Line\n";
        mustach_content text/html;
        return 200 '{
        "boolean": true
      }';
    }
--- request
    GET /test
--- response_body eval
"| This Is\n|\n| A Line\n"
=== TEST 26: Indented Standalone Lines
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template "| This Is\n  {{#boolean}}\n|\n  {{/boolean}}\n| A Line\n";
        mustach_content text/html;
        return 200 '{
        "boolean": true
      }';
    }
--- request
    GET /test
--- response_body eval
"| This Is\n|\n| A Line\n"
=== TEST 27: Standalone Line Endings
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template "|\r\n{{#boolean}}\r\n{{/boolean}}\r\n|";
        mustach_content text/html;
        return 200 '{
        "boolean": true
      }';
    }
--- request
    GET /test
--- response_body eval
"|\r\n|"
=== TEST 28: Standalone Without Previous Line
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template "  {{#boolean}}\n#{{/boolean}}\n/";
        mustach_content text/html;
        return 200 '{
        "boolean": true
      }';
    }
--- request
    GET /test
--- response_body eval
"#\n/"
=== TEST 29: Standalone Without Newline
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template "#{{#boolean}}\n/\n  {{/boolean}}";
        mustach_content text/html;
        return 200 '{
        "boolean": true
      }';
    }
--- request
    GET /test
--- response_body eval
"#\n/\n"
=== TEST 30: Padding
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template "|{{# boolean }}={{/ boolean }}|";
        mustach_content text/html;
        return 200 '{
        "boolean": true
      }';
    }
--- request
    GET /test
--- response_body eval
"|=|"
