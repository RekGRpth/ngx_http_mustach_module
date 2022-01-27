#include "ngx_http_mustach_module.h"

#if __has_include("mustach/mustach-cjson.h")
#include "mustach/mustach-cjson.h"

int ngx_http_mustach_process_cjson(ngx_http_request_t *r, const char *template, size_t length, const char *value, size_t buffer_length, int flags, FILE *file) {
    cJSON *root;
    int rc = MUSTACH_ERROR_USER(1);
    if (!(root = cJSON_ParseWithLength(value, buffer_length))) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "!cJSON_ParseWithLength"); goto ret; }
    rc = mustach_cJSON_file(template, length, root, flags, file);
    cJSON_Delete(root);
ret:
    return rc;
}
#else
int ngx_http_mustach_process_cjson(ngx_http_request_t *r, const char *template, size_t length, const char *value, size_t buffer_length, int flags, FILE *file) {
    ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "!mustach_cjson");
    return MUSTACH_ERROR_USER(1);
}
#endif
