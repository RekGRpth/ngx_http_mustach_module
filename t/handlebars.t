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

=== TEST 1: array-each
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template '{{#names}}{{name}}{{/names}}';
        mustach_content text/html;
        return 200 '{
    "names": [
        {
            "name": "Moe"
        },
        {
            "name": "Larry"
        },
        {
            "name": "Curly"
        },
        {
            "name": "Shemp"
        }
    ]
}';
    }
--- request
    GET /test
--- response_body chop
MoeLarryCurlyShemp
=== TEST 2: complex
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template '<h1>{{header}}</h1>
{{#hasItems}}
  <ul>
    {{#items}}
      {{#current}}
        <li><strong>{{name}}</strong></li>
      {{/current}}
      {{^current}}
        <li><a href="{{url}}">{{name}}</a></li>
      {{/current}}
    {{/items}}
  </ul>
{{/hasItems}}
';
        mustach_content text/html;
        return 200 '{
    "header": "Colors",
    "hasItems": true,
    "items": [
        {
            "name": "red",
            "current": true,
            "url": "#Red"
        },
        {
            "name": "green",
            "current": false,
            "url": "#Green"
        },
        {
            "name": "blue",
            "current": false,
            "url": "#Blue"
        }
    ]
}';
    }
--- request
    GET /test
--- response_body eval
'<h1>Colors</h1>

  <ul>
    
      
        <li><strong>red</strong></li>
      
      
    
      
      
        <li><a href="#Green">green</a></li>
      
    
      
      
        <li><a href="#Blue">blue</a></li>
      
    
  </ul>

'
=== TEST 3: data
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template '{{#names}}{{@index}}{{name}}{{/names}}';
        mustach_content text/html;
        return 200 '{
    "names": [
        {
            "name": "Moe"
        },
        {
            "name": "Larry"
        },
        {
            "name": "Curly"
        },
        {
            "name": "Shemp"
        }
    ]
}';
    }
--- request
    GET /test
--- response_body chop
MoeLarryCurlyShemp
=== TEST 4: depth-1
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template '{{#names}}{{foo}}{{/names}}';
        mustach_content text/html;
        return 200 '{
    "names": [
        {
            "name": "Moe"
        },
        {
            "name": "Larry"
        },
        {
            "name": "Curly"
        },
        {
            "name": "Shemp"
        }
    ],
    "foo": "bar"
}';
    }
--- request
    GET /test
--- response_body chop
barbarbarbar
=== TEST 5: depth-2
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template '{{#names}}{{#name}}{{bat}}{{foo}}{{/name}}{{/names}}';
        mustach_content text/html;
        return 200 '{
    "names": [
        {
            "bat": "foo",
            "name": [
                "Moe"
            ]
        },
        {
            "bat": "foo",
            "name": [
                "Larry"
            ]
        },
        {
            "bat": "foo",
            "name": [
                "Curly"
            ]
        },
        {
            "bat": "foo",
            "name": [
                "Shemp"
            ]
        }
    ],
    "foo": "bar"
}';
    }
--- request
    GET /test
--- response_body chop
foobarfoobarfoobarfoobar
=== TEST 6: object
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template '{{#person}}{{name}}{{age}}{{/person}}';
        mustach_content text/html;
        return 200 '{
    "person": {
        "name": "Larry",
        "age": 45
    }
}';
    }
--- request
    GET /test
--- response_body chop
Larry45
=== TEST 7: object-mustache
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template '{{#person}}{{name}}{{age}}{{/person}}';
        mustach_content text/html;
        return 200 '{
    "person": {
        "name": "Larry",
        "age": 45
    }
}';
    }
--- request
    GET /test
--- response_body chop
Larry45
=== TEST 8: partial
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template '{{#peeps}}{{>variables}}{{/peeps}}';
        mustach_content text/html;
        return 200 '{
    "peeps": [
        {
            "name": "Moe",
            "count": 15
        },
        {
            "name": "Larry",
            "count": 5
        },
        {
            "name": "Curly",
            "count": 1
        }
    ]
}';
    }
--- request
    GET /test
--- response_body chop
Hello Moe! You have 15 new messages.Hello Larry! You have 5 new messages.Hello Curly! You have 1 new messages.
=== TEST 9: partial-recursion
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template '{{name}}{{#kids}}{{>recursion}}{{/kids}}';
        mustach_content text/html;
        return 200 '{
    "name": "1",
    "kids": [
        {
            "name": "1.1",
            "kids": [
                {
                    "name": "1.1.1",
                    "kids": []
                }
            ]
        }
    ]
}';
    }
--- request
    GET /test
--- response_body chop
11.11.1.1
=== TEST 10: paths
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template '{{person.name.bar.baz}}{{person.age}}{{person.foo}}{{animal.age}}';
        mustach_content text/html;
        return 200 '{
  "person": {
    "name": {
      "bar": {
        "baz": "Larry"
      }
    },
    "age": 45
  }
}';
    }
--- request
    GET /test
--- response_body chop
Larry45
=== TEST 11: string
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template 'Hello world';
        mustach_content text/html;
        return 200 '{}';
    }
--- request
    GET /test
--- response_body chop
Hello world
=== TEST 12: variables
--- main_config eval: $::main_config
--- config
    location /test {
        default_type application/json;
        mustach_template 'Hello {{name}}! You have {{count}} new messages.';
        mustach_content text/html;
        return 200 '{
    "name": "Mick",
    "count": 30
}';
    }
--- request
    GET /test
--- response_body chop
Hello Mick! You have 30 new messages.
