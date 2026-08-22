#if defined(__APPLE__)
#define _DARWIN_C_SOURCE
#else
#define _POSIX_C_SOURCE 200809L
#endif

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#if defined(__linux__)
#include <sys/random.h>
#endif
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

int flyology_object_storage_server_random(void *data, size_t length)
{
#if defined(__APPLE__)
    arc4random_buf(data, length);
    return 0;
#elif defined(__linux__)
    unsigned char *cursor = (unsigned char *)data;
    size_t offset = 0U;
    while (offset < length) {
        ssize_t received = getrandom(cursor + offset, length - offset, 0U);
        if (received < 0) {
            if (errno == EINTR) {
                continue;
            }
            return -1;
        }
        offset += (size_t)received;
    }
    return 0;
#else
#error "A platform CSPRNG implementation is required"
#endif
}

static int write_complete(int descriptor, const char *data, size_t length)
{
    size_t offset = 0U;
    while (offset < length) {
        ssize_t written = write(descriptor, data + offset, length - offset);
        if (written < 0) {
            if (errno == EINTR) {
                continue;
            }
            return -1;
        }
        if (written == 0) {
            errno = EIO;
            return -1;
        }
        offset += (size_t)written;
    }
    return 0;
}

static int sync_parent(const char *path)
{
    char parent[PATH_MAX];
    char *slash;
    int descriptor;
    size_t length = strlen(path);
    if (length >= sizeof(parent)) {
        errno = ENAMETOOLONG;
        return -1;
    }
    memcpy(parent, path, length + 1U);
    slash = strrchr(parent, '/');
    if (slash == NULL) {
        memcpy(parent, ".", 2U);
    } else if (slash == parent) {
        slash[1] = '\0';
    } else {
        *slash = '\0';
    }
    descriptor = open(parent, O_RDONLY);
    if (descriptor < 0) {
        return -1;
    }
    if (fsync(descriptor) != 0) {
        int saved = errno;
        (void)close(descriptor);
        errno = saved;
        return -1;
    }
    return close(descriptor);
}

int flyology_object_storage_server_publish_credentials(
    const char *path, const char *data, size_t length)
{
    char temporary[PATH_MAX];
    int descriptor;
    int status;
    int count = snprintf(temporary, sizeof(temporary), "%s.tmp.%ld",
                         path, (long)getpid());
    if (count < 0 || (size_t)count >= sizeof(temporary)) {
        errno = ENAMETOOLONG;
        return -1;
    }
    descriptor = open(temporary, O_WRONLY | O_CREAT | O_EXCL, 0600);
    if (descriptor < 0) {
        return -1;
    }
    status = write_complete(descriptor, data, length);
    if (status == 0) {
        status = fsync(descriptor);
    }
    if (close(descriptor) != 0 && status == 0) {
        status = -1;
    }
    if (status != 0) {
        int saved = errno;
        (void)unlink(temporary);
        errno = saved;
        return -1;
    }
    if (link(temporary, path) != 0) {
        int saved = errno;
        (void)unlink(temporary);
        if (saved == EEXIST) {
            return 0;
        }
        errno = saved;
        return -1;
    }
    status = unlink(temporary);
    if (sync_parent(path) != 0) {
        status = -1;
    }
    /* The target is already atomically published. Return a distinct positive
       result when its cleanup/directory sync was imperfect so the caller
       still reveals the only usable bootstrap password and avoids lockout. */
    return status == 0 ? 1 : 2;
}

int flyology_object_storage_server_credentials_secure(const char *path)
{
    struct stat value;
    if (lstat(path, &value) != 0) {
        return -1;
    }
    if (!S_ISREG(value.st_mode) || value.st_uid != geteuid()) {
        return 0;
    }
    return (value.st_mode & 0777) == 0600 ? 1 : 0;
}
