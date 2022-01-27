#ifndef _NGX_HTTP_MUSTACH_MODULE_H
#define _NGX_HTTP_MUSTACH_MODULE_H

#include <nginx.h>
#include <ngx_http.h>
#include <stddef.h>
#include <stdio.h>

int ngx_http_mustach_process_cjson(ngx_http_request_t *r, const char *template, size_t length, const char *value, size_t buffer_length, int flags, FILE *file);
int ngx_http_mustach_process_jansson(ngx_http_request_t *r, const char *template, size_t length, const char *buffer, size_t buflen, int flags, FILE *file);
int ngx_http_mustach_process_json_c(ngx_http_request_t *r, const char *template, size_t length, const char *str, size_t len, int flags, FILE *file);

#endif // _NGX_HTTP_MUSTACH_MODULE_H
