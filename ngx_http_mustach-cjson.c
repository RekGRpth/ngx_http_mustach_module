#include "ngx_http_mustach_module.h"
#include <mustach/mustach-cjson.h>

int ngx_http_mustach_process_cjson(ngx_http_request_t *r, const char *template, const char *value, size_t buffer_length, FILE *file) {
    cJSON *root;
    int rc = -1;
    if (!(root = cJSON_ParseWithLength(value, buffer_length))) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "!cJSON_ParseWithLength"); goto ret; }
    rc = mustach_cJSON_file(template, root, Mustach_With_AllExtensions, file);
    cJSON_Delete(root);
ret:
    return rc;
}
