#define _POSIX_C_SOURCE 200809L
#include <libmtp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char old_name[64] = "MARSWATCH.PRG";
static char new_name[64] = "";
static const char *source;
static int read_back;
static int scenario(const char *name) {
    const char *value = getenv("MTP_TEST");
    return value && strcmp(value, name) == 0;
}
static void log_call(const char *call, uint32_t id, const char *name) {
    FILE *log = fopen(getenv("MTP_TEST_LOG"), "a");
    if (log) { fprintf(log, "%s %u %s\n", call, id, name ? name : ""); fclose(log); }
}
static LIBMTP_file_t *file(uint32_t id, const char *name) {
    LIBMTP_file_t *f = calloc(1, sizeof(*f));
    f->item_id = id; f->parent_id = 2; f->storage_id = 7;
    f->filename = strdup(name);
    return f;
}

void LIBMTP_Init(void) {}
LIBMTP_error_number_t LIBMTP_Detect_Raw_Devices(LIBMTP_raw_device_t **raw, int *count) {
    *count = scenario("multiple") ? 3 : 2;
    *raw = calloc((size_t)*count, sizeof(**raw));
    (*raw)[0].device_entry.vendor_id = 0x1234;
    (*raw)[1].device_entry.vendor_id = 0x091e;
    if (*count == 3) (*raw)[2].device_entry.vendor_id = 0x091e;
    return LIBMTP_ERROR_NONE;
}
LIBMTP_mtpdevice_t *LIBMTP_Open_Raw_Device_Uncached(LIBMTP_raw_device_t *raw) {
    log_call("open", raw->device_entry.vendor_id, "");
    return calloc(1, sizeof(LIBMTP_mtpdevice_t));
}
void LIBMTP_Release_Device(LIBMTP_mtpdevice_t *d) { free(d); }
char *LIBMTP_Get_Modelname(LIBMTP_mtpdevice_t *d) {
    (void)d;
    return strdup(scenario("wrong-model") ? "fenix 5X" : "fenix 9 Pro 51mm");
}
LIBMTP_error_t *LIBMTP_Get_Errorstack(LIBMTP_mtpdevice_t *d) { (void)d; return NULL; }
void LIBMTP_Clear_Errorstack(LIBMTP_mtpdevice_t *d) { (void)d; }
void LIBMTP_Dump_Errorstack(LIBMTP_mtpdevice_t *d) { (void)d; }
LIBMTP_folder_t *LIBMTP_Get_Folder_List(LIBMTP_mtpdevice_t *d) {
    (void)d;
    if (scenario("missing-folder")) return NULL;
    LIBMTP_folder_t *root = calloc(1, sizeof(*root));
    root->name = strdup("GARMIN"); root->folder_id = 1; root->storage_id = 7;
    root->child = calloc(1, sizeof(*root));
    root->child->name = strdup("APPS"); root->child->folder_id = 2;
    root->child->parent_id = 1; root->child->storage_id = 7;
    return root;
}
void LIBMTP_destroy_folder_t(LIBMTP_folder_t *f) {
    if (!f) return;
    LIBMTP_destroy_folder_t(f->child); LIBMTP_destroy_folder_t(f->sibling);
    free(f->name); free(f);
}
LIBMTP_file_t *LIBMTP_Get_Files_And_Folders(LIBMTP_mtpdevice_t *d, uint32_t storage, uint32_t parent) {
    (void)d;
    if (storage != 7 || parent != 2) abort();
    LIBMTP_file_t *first = file(77, "OTHER.PRG");
    if (!scenario("fresh")) {
        first->next = file(10, old_name);
        if (scenario("duplicate")) first->next->next = file(11, old_name);
    }
    return first;
}
LIBMTP_file_t *LIBMTP_new_file_t(void) { return calloc(1, sizeof(LIBMTP_file_t)); }
void LIBMTP_destroy_file_t(LIBMTP_file_t *f) { if (f) { free(f->filename); free(f); } }
int LIBMTP_Send_File_From_File(LIBMTP_mtpdevice_t *d, const char *path, LIBMTP_file_t *f,
                              LIBMTP_progressfunc_t cb, const void *data) {
    (void)d; (void)cb; (void)data;
    if (f->parent_id != 2 || f->storage_id != 7) abort();
    log_call("send", 20, f->filename);
    if (scenario("upload-failure")) return -1;
    source = path; f->item_id = 20;
    snprintf(new_name, sizeof(new_name), "%s", f->filename);
    return 0;
}
int LIBMTP_Get_File_To_File(LIBMTP_mtpdevice_t *d, uint32_t id, const char *path,
                           LIBMTP_progressfunc_t cb, const void *data) {
    (void)d; (void)cb; (void)data;
    log_call("read", id, "");
    FILE *out = fopen(path, "wb"), *in = fopen(source, "rb");
    if (!out || !in) abort();
    int ch;
    if (scenario("corrupt")) fputc('!', out);
    while ((ch = fgetc(in)) != EOF) fputc(ch, out);
    fclose(in); fclose(out);
    read_back = 1;
    return 0;
}
LIBMTP_file_t *LIBMTP_Get_Filemetadata(LIBMTP_mtpdevice_t *d, uint32_t id) {
    (void)d;
    return file(id, id == 10 ? old_name : new_name);
}
int LIBMTP_Set_File_Name(LIBMTP_mtpdevice_t *d, LIBMTP_file_t *f, const char *name) {
    (void)d;
    if (!read_back) abort();
    log_call("rename", f->item_id, name);
    if (scenario("rename-failure") && f->item_id == 20) return -1;
    if (f->item_id == 10) snprintf(old_name, sizeof(old_name), "%s", name);
    else snprintf(new_name, sizeof(new_name), "%s", name);
    return 0;
}
int LIBMTP_Delete_Object(LIBMTP_mtpdevice_t *d, uint32_t id) {
    (void)d;
    if (id != 10 && id != 20) abort();
    if (id == 10 && (!read_back || strcmp(new_name, "MARSWATCH.PRG") != 0)) abort();
    log_call("delete", id, "");
    return 0;
}
