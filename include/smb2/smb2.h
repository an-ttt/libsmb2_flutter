#ifndef SMB2_H
#define SMB2_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SMB2_STATUS_SUCCESS 0x00000000
#define SMB2_STATUS_NO_SUCH_FILE 0xC000000F
#define SMB2_STATUS_OBJECT_NAME_NOT_FOUND 0xC0000034
#define SMB2_STATUS_OBJECT_PATH_NOT_FOUND 0xC000003A
#define SMB2_STATUS_ACCESS_DENIED 0xC0000022
#define SMB2_STATUS_LOGON_FAILURE 0xC000006D

#define SMB2_FILE_ATTRIBUTE_DIRECTORY 0x00000010
#define SMB2_FILE_ATTRIBUTE_NORMAL 0x00000080

#define O_RDONLY 0x0000
#define O_WRONLY 0x0001
#define O_RDWR   0x0002
#define O_CREAT  0x0100
#define O_EXCL   0x0200
#define O_TRUNC  0x0400
#define O_APPEND 0x0008

#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2

struct smb2_context;
struct smb2_url;
struct smb2dir;
struct smb2fh;

struct smb2_stat_64 {
    uint64_t smb2_type;
    uint64_t smb2_nlink;
    uint64_t smb2_ino;
    uint64_t smb2_size;
    uint64_t smb2_atime;
    uint64_t smb2_atime_nsec;
    uint64_t smb2_mtime;
    uint64_t smb2_mtime_nsec;
    uint64_t smb2_ctime;
    uint64_t smb2_ctime_nsec;
};

struct smb2dirent {
    char *name;
    uint32_t st_type;
    struct smb2_stat_64 st;
};

typedef void (*smb2_command_cb)(struct smb2_context *smb2, int status,
                                void *command_data, void *cb_data);

struct smb2_context *smb2_init_context(void);
void smb2_destroy_context(struct smb2_context *smb2);

const char *smb2_get_error(struct smb2_context *smb2);
int smb2_get_fd(struct smb2_context *smb2);
int smb2_service(struct smb2_context *smb2, int revents);

struct smb2_url *smb2_parse_url(struct smb2_context *smb2, const char *url);
void smb2_destroy_url(struct smb2_url *url);

void smb2_set_security_mode(struct smb2_context *smb2, uint16_t mode);
void smb2_set_domain(struct smb2_context *smb2, const char *domain);
void smb2_set_user(struct smb2_context *smb2, const char *user);
void smb2_set_password(struct smb2_context *smb2, const char *password);
void smb2_set_workstation(struct smb2_context *smb2, const char *workstation);
void smb2_set_timeout(struct smb2_context *smb2, int seconds);

int smb2_connect_share_async(struct smb2_context *smb2, const char *server,
                             const char *share, const char *user,
                             smb2_command_cb cb, void *cb_data);

int smb2_disconnect_share_async(struct smb2_context *smb2,
                                smb2_command_cb cb, void *cb_data);

int smb2_opendir_async(struct smb2_context *smb2, const char *path,
                       smb2_command_cb cb, void *cb_data);

struct smb2dirent *smb2_readdir(struct smb2_context *smb2, struct smb2dir *dir);

int smb2_closedir_async(struct smb2_context *smb2, struct smb2dir *dir,
                        smb2_command_cb cb, void *cb_data);

int smb2_open_async(struct smb2_context *smb2, const char *path, int flags,
                    smb2_command_cb cb, void *cb_data);

int smb2_read_async(struct smb2_context *smb2, struct smb2fh *fh,
                    uint8_t *buf, uint64_t count,
                    smb2_command_cb cb, void *cb_data);

int smb2_write_async(struct smb2_context *smb2, struct smb2fh *fh,
                     const uint8_t *buf, uint64_t count,
                     smb2_command_cb cb, void *cb_data);

int smb2_close_async(struct smb2_context *smb2, struct smb2fh *fh,
                     smb2_command_cb cb, void *cb_data);

int smb2_pread_async(struct smb2_context *smb2, struct smb2fh *fh,
                     uint8_t *buf, uint64_t count, uint64_t offset,
                     smb2_command_cb cb, void *cb_data);

int smb2_pwrite_async(struct smb2_context *smb2, struct smb2fh *fh,
                      const uint8_t *buf, uint64_t count, uint64_t offset,
                      smb2_command_cb cb, void *cb_data);

int smb2_stat_async(struct smb2_context *smb2, const char *path,
                    struct smb2_stat_64 *st,
                    smb2_command_cb cb, void *cb_data);

int smb2_mkdir_async(struct smb2_context *smb2, const char *path,
                     smb2_command_cb cb, void *cb_data);

int smb2_rmdir_async(struct smb2_context *smb2, const char *path,
                     smb2_command_cb cb, void *cb_data);

int smb2_unlink_async(struct smb2_context *smb2, const char *path,
                      smb2_command_cb cb, void *cb_data);

int smb2_rename_async(struct smb2_context *smb2, const char *oldpath,
                      const char *newpath, smb2_command_cb cb, void *cb_data);

int64_t smb2_lseek(struct smb2_context *smb2, struct smb2fh *fh,
                   int64_t offset, int whence);

int smb2_fstat_async(struct smb2_context *smb2, struct smb2fh *fh,
                     struct smb2_stat_64 *st,
                     smb2_command_cb cb, void *cb_data);

int smb2_get_max_read_size(struct smb2_context *smb2);
int smb2_get_max_write_size(struct smb2_context *smb2);
void smb2_set_readahead(struct smb2_context *smb2, int readahead);

#ifdef __cplusplus
}
#endif

#endif
