#ifndef LIBSMB2_WRAPPER_H
#define LIBSMB2_WRAPPER_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SMB2_TYPE_FILE      0x00000000
#define SMB2_TYPE_DIRECTORY 0x00000001
#define SMB2_TYPE_LINK      0x00000002

struct smb2_stat_64 {
    uint32_t smb2_type;
    uint32_t smb2_nlink;
    uint64_t smb2_ino;
    uint64_t smb2_size;
    uint64_t smb2_atime;
    uint64_t smb2_atime_nsec;
    uint64_t smb2_mtime;
    uint64_t smb2_mtime_nsec;
    uint64_t smb2_ctime;
    uint64_t smb2_ctime_nsec;
    uint64_t smb2_btime;
    uint64_t smb2_btime_nsec;
};

struct smb2dirent {
    const char *name;
    struct smb2_stat_64 st;
};

struct smb2_context;
struct smb2dir;
struct smb2fh;

struct smb2_context *smb2_init_context(void);
void smb2_destroy_context(struct smb2_context *smb2);
const char *smb2_get_error(struct smb2_context *smb2);
void smb2_set_timeout(struct smb2_context *smb2, int timeout);
void smb2_set_domain(struct smb2_context *smb2, const char *domain);
void smb2_set_user(struct smb2_context *smb2, const char *user);
void smb2_set_password(struct smb2_context *smb2, const char *password);

int smb2_connect_share(struct smb2_context *smb2, const char *server,
                       const char *share, const char *user);
int smb2_disconnect_share(struct smb2_context *smb2);

struct smb2dir *smb2_opendir(struct smb2_context *smb2, const char *path);
struct smb2dirent *smb2_readdir(struct smb2_context *smb2,
                                struct smb2dir *smb2dir);
int smb2_closedir(struct smb2_context *smb2, struct smb2dir *smb2dir);

struct smb2fh *smb2_open(struct smb2_context *smb2, const char *path, int flags);
int smb2_close(struct smb2_context *smb2, struct smb2fh *fh);

int smb2_pread(struct smb2_context *smb2, struct smb2fh *fh,
               uint8_t *buf, uint32_t count, uint64_t offset);
int smb2_pwrite(struct smb2_context *smb2, struct smb2fh *fh,
                const uint8_t *buf, uint32_t count, uint64_t offset);
int smb2_read(struct smb2_context *smb2, struct smb2fh *fh,
              uint8_t *buf, uint32_t count);
int smb2_write(struct smb2_context *smb2, struct smb2fh *fh,
               const uint8_t *buf, uint32_t count);

int smb2_stat(struct smb2_context *smb2, const char *path,
              struct smb2_stat_64 *st);
int smb2_fstat(struct smb2_context *smb2, struct smb2fh *fh,
               struct smb2_stat_64 *st);

int smb2_mkdir(struct smb2_context *smb2, const char *path);
int smb2_rmdir(struct smb2_context *smb2, const char *path);
int smb2_unlink(struct smb2_context *smb2, const char *path);
int smb2_rename(struct smb2_context *smb2, const char *oldpath,
                const char *newpath);

uint64_t smb2_lseek(struct smb2_context *smb2, struct smb2fh *fh,
                    uint64_t offset, int whence);

int smb2_get_max_read_size(struct smb2_context *smb2);
int smb2_get_max_write_size(struct smb2_context *smb2);

int native_poll(int fd, int events, int timeout);
int get_errno_value(void);

#ifdef __cplusplus
}
#endif

#endif
