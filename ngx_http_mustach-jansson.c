#include "ngx_http_mustach_module.h"

#if __has_include("mustach/mustach-jansson.h")
#include "mustach/mustach-jansson.h"

int ngx_http_mustach_process_jansson(ngx_http_request_t *r, const char *template, size_t length, const char *buffer, size_t buflen, FILE *file) {
    int rc = -1;
    json_error_t error;
    json_t *root;
    if (!(root = json_loadb(buffer, buflen, JSON_DECODE_ANY, &error))) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "!json_loadb and %s", error.text); goto ret; }
    rc = mustach_jansson_file(template, length, root, Mustach_With_AllExtensions, file);
    json_decref(root);
ret:
    return rc;
}
#else
int ngx_http_mustach_process_jansson(ngx_http_request_t *r, const char *template, size_t length, const char *buffer, size_t buflen, FILE *file) {
    ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "!mustach_jansson");
    return -1;
}
#endif
