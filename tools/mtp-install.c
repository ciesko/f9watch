#define _POSIX_C_SOURCE 200809L
#include <libmtp.h>
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>
#include <unistd.h>

static void find_apps(LIBMTP_folder_t *folder, uint32_t garmin,
                      uint32_t *apps, uint32_t *storage, int *matches) {
    for (; folder; folder = folder->sibling) {
        uint32_t parent = garmin;
        if ((folder->parent_id == 0 || folder->parent_id == LIBMTP_FILES_AND_FOLDERS_ROOT) &&
            strcasecmp(folder->name, "Garmin") == 0)
            parent = folder->folder_id;
        if (garmin && folder->parent_id == garmin && strcasecmp(folder->name, "Apps") == 0) {
            *apps = folder->folder_id;
            *storage = folder->storage_id;
            (*matches)++;
        }
        find_apps(folder->child, parent, apps, storage, matches);
    }
}

static int same_file(const char *left, const char *right) {
    FILE *a = fopen(left, "rb"), *b = fopen(right, "rb");
    int ok = a && b;
    if (ok) {
        int x, y;
        do {
            x = fgetc(a);
            y = fgetc(b);
            if (x != y) { ok = 0; break; }
        } while (x != EOF);
        if (ferror(a) || ferror(b)) ok = 0;
    }
    if (a) fclose(a);
    if (b) fclose(b);
    return ok;
}

static int rename_file(LIBMTP_mtpdevice_t *device, uint32_t id, const char *name) {
    LIBMTP_file_t *file = LIBMTP_Get_Filemetadata(device, id);
    if (!file) return -1;
    int result = LIBMTP_Set_File_Name(device, file, name);
    LIBMTP_destroy_file_t(file);
    return result;
}

int main(int argc, char **argv) {
    const char *name = "MARSWATCH.PRG";
    const char *staging = "MARSWATCH-STAGING.PRG";
    const char *backup = "MARSWATCH-BACKUP.PRG";
    struct stat statbuf;
    if (argc != 2 || stat(argv[1], &statbuf) != 0 ||
        !S_ISREG(statbuf.st_mode) || statbuf.st_size <= 0) {
        fprintf(stderr, "Expected a nonempty compiled PRG file.\n");
        return 1;
    }
    LIBMTP_Init();
    LIBMTP_raw_device_t *raw = NULL;
    int count = 0, selected = -1, garmins = 0;
    if (LIBMTP_Detect_Raw_Devices(&raw, &count) != LIBMTP_ERROR_NONE) {
        fprintf(stderr, "No accessible MTP device. Check data cable and USB mode.\n");
        free(raw);
        return 1;
    }
    for (int i = 0; i < count; i++) {
        if (raw[i].device_entry.vendor_id == 0x091e) { selected = i; garmins++; }
    }
    if (garmins != 1) {
        fprintf(stderr, "Expected one Garmin MTP device; found %d.\n", garmins);
        free(raw);
        return 1;
    }
    LIBMTP_mtpdevice_t *device = LIBMTP_Open_Raw_Device_Uncached(&raw[selected]);
    free(raw);
    if (!device) {
        fprintf(stderr, "Cannot open watch. Close other Garmin/MTP applications.\n");
        return 1;
    }

    int result = 1;
    char *model = LIBMTP_Get_Modelname(device);
    char normalized[256] = {0};
    size_t j = 0;
    if (model) {
        for (size_t i = 0; model[i] && j + 1 < sizeof(normalized); i++)
            if (isalnum((unsigned char)model[i]))
                normalized[j++] = (char)tolower((unsigned char)model[i]);
    }
    printf("Connected watch: %s\n", model ? model : "(unknown)");
    free(model);
    if ((!strstr(normalized, "fenix9pro") && !strstr(normalized, "fnix9pro")) || strstr(normalized, "solar") ||
        strstr(normalized, "47mm") || strstr(normalized, "43mm")) {
        fprintf(stderr, "Not the expected fenix 9 Pro AMOLED. No files written.\n");
        goto done;
    }
    char answer[16];
    printf("Confirm this is your 51 mm AMOLED watch; install Mars Watch? [y/N] ");
    fflush(stdout);
    if (!fgets(answer, sizeof(answer), stdin) || (answer[0] != 'y' && answer[0] != 'Y')) {
        puts("Nothing written.");
        result = 2;
        goto done;
    }

    uint32_t apps = 0, storage = 0;
    int matches = 0;
    LIBMTP_folder_t *folders = LIBMTP_Get_Folder_List(device);
    find_apps(folders, 0, &apps, &storage, &matches);
    LIBMTP_destroy_folder_t(folders);
    if (matches != 1) {
        fprintf(stderr, "Could not uniquely identify existing Garmin/Apps folder. No files written.\n");
        goto done;
    }
    uint32_t old_id = 0;
    int old_count = 0;
    int leftovers = 0;
    LIBMTP_Clear_Errorstack(device);
    LIBMTP_file_t *files = LIBMTP_Get_Files_And_Folders(device, storage, apps);
    if (LIBMTP_Get_Errorstack(device)) goto done;
    while (files) {
        LIBMTP_file_t *next = files->next;
        if (files->filename && strcasecmp(files->filename, name) == 0) {
            old_id = files->item_id;
            old_count++;
        }
        if (files->filename && (strcasecmp(files->filename, staging) == 0 ||
                                strcasecmp(files->filename, backup) == 0))
            leftovers++;
        LIBMTP_destroy_file_t(files);
        files = next;
    }
    if (old_count > 1 || leftovers) {
        fprintf(stderr, "Ambiguous or interrupted Mars Watch install; no files written.\n");
        goto done;
    }

    LIBMTP_file_t *upload = LIBMTP_new_file_t();
    if (!upload) goto done;
    upload->filename = strdup(staging);
    upload->filesize = (uint64_t)statbuf.st_size;
    upload->filetype = LIBMTP_FILETYPE_UNKNOWN;
    upload->parent_id = apps;
    upload->storage_id = storage;
    int sent = LIBMTP_Send_File_From_File(device, argv[1], upload, NULL, NULL);
    uint32_t new_id = upload->item_id;
    LIBMTP_destroy_file_t(upload);
    if (sent != 0 || !new_id || new_id == old_id) {
        fprintf(stderr, "Upload failed; existing build has not been deleted.\n");
        if (new_id && new_id != old_id) LIBMTP_Delete_Object(device, new_id);
        goto done;
    }

    char verify[] = "/tmp/f9watch-verify-XXXXXX";
    int fd = mkstemp(verify);
    int verified = 0;
    if (fd >= 0) {
        close(fd);
        verified = LIBMTP_Get_File_To_File(device, new_id, verify, NULL, NULL) == 0 &&
                   same_file(argv[1], verify);
        unlink(verify);
    }
    if (!verified) {
        fprintf(stderr, "Read-back verification failed; preserving the old build.\n");
        LIBMTP_Delete_Object(device, new_id);
        goto done;
    }
    // Keep the old binary until the verified staging upload has its final name.
    if (old_id && rename_file(device, old_id, backup) != 0) {
        fprintf(stderr, "Could not stage replacement; preserving the old build.\n");
        LIBMTP_Delete_Object(device, new_id);
        goto done;
    }
    if (rename_file(device, new_id, name) != 0) {
        fprintf(stderr, "Could not finalize upload; restoring the previous filename.\n");
        if (old_id && rename_file(device, old_id, name) != 0)
            fprintf(stderr, "Old build remains in MARSWATCH-BACKUP.PRG; recover it manually.\n");
        LIBMTP_Delete_Object(device, new_id);
        goto done;
    }
    if (old_id && LIBMTP_Delete_Object(device, old_id) != 0) {
        fprintf(stderr, "New build installed and verified; old backup could not be removed.\n");
        goto done;
    }
    puts("MARSWATCH.PRG uploaded and byte-for-byte verified.");
    result = 0;

done:
    if (result == 1) LIBMTP_Dump_Errorstack(device);
    LIBMTP_Release_Device(device);
    return result;
}
