#include <errno.h>
#include <stdlib.h>

#ifdef _WIN32
#include <windows.h>

struct root_lock {
    HANDLE handle;
};

void *flyology_object_storage_acquire_root_lock(const char *path) {
    struct root_lock *lock;
    HANDLE handle = CreateFileA(path, GENERIC_READ | GENERIC_WRITE, 0,
        NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (handle == INVALID_HANDLE_VALUE) {
        return NULL;
    }
    lock = malloc(sizeof(*lock));
    if (lock == NULL) {
        CloseHandle(handle);
        return NULL;
    }
    lock->handle = handle;
    return lock;
}

void flyology_object_storage_release_root_lock(void *opaque) {
    struct root_lock *lock = opaque;
    if (lock != NULL) {
        CloseHandle(lock->handle);
        free(lock);
    }
}

static int sync_path(const char *path, int directory) {
    DWORD flags = directory ? FILE_FLAG_BACKUP_SEMANTICS : 0;
    HANDLE handle = CreateFileA(path, GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        NULL, OPEN_EXISTING, flags, NULL);
    if (handle == INVALID_HANDLE_VALUE) {
        return (int)GetLastError();
    }
    if (!FlushFileBuffers(handle)) {
        int error = (int)GetLastError();
        CloseHandle(handle);
        return error;
    }
    CloseHandle(handle);
    return 0;
}
#else
#include <fcntl.h>
#include <sys/file.h>
#include <unistd.h>

struct root_lock {
    int descriptor;
};

void *flyology_object_storage_acquire_root_lock(const char *path) {
    int flags = O_RDWR | O_CREAT;
    int descriptor;
    struct root_lock *lock;
#ifdef O_CLOEXEC
    flags |= O_CLOEXEC;
#endif
    descriptor = open(path, flags, 0600);
    if (descriptor < 0) {
        return NULL;
    }
#ifndef O_CLOEXEC
    if (fcntl(descriptor, F_SETFD, FD_CLOEXEC) != 0) {
        close(descriptor);
        return NULL;
    }
#endif
    if (flock(descriptor, LOCK_EX | LOCK_NB) != 0) {
        close(descriptor);
        return NULL;
    }
    lock = malloc(sizeof(*lock));
    if (lock == NULL) {
        close(descriptor);
        return NULL;
    }
    lock->descriptor = descriptor;
    return lock;
}

void flyology_object_storage_release_root_lock(void *opaque) {
    struct root_lock *lock = opaque;
    if (lock != NULL) {
        close(lock->descriptor);
        free(lock);
    }
}

static int sync_path(const char *path, int directory) {
    int flags = O_RDONLY;
    int descriptor;
    int result;
    (void)directory;
#ifdef O_CLOEXEC
    flags |= O_CLOEXEC;
#endif
    descriptor = open(path, flags);
    if (descriptor < 0) {
        return errno;
    }
#ifdef F_FULLFSYNC
    result = fcntl(descriptor, F_FULLFSYNC);
    if (result != 0)
#endif
    {
        result = fsync(descriptor);
    }
    if (result != 0) {
        int error = errno;
        close(descriptor);
        return error;
    }
    if (close(descriptor) != 0) {
        return errno;
    }
    return 0;
}
#endif

int flyology_object_storage_sync_file(const char *path) {
    return sync_path(path, 0);
}

int flyology_object_storage_sync_directory(const char *path) {
    return sync_path(path, 1);
}
