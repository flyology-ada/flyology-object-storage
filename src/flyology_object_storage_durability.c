#include <errno.h>

#ifdef _WIN32
#include <windows.h>

void flyology_object_storage_core_crash_process(void) {
    (void)TerminateProcess(GetCurrentProcess(), 137);
}

static int sync_path(const char *path, int directory) {
    DWORD flags = directory ? FILE_FLAG_BACKUP_SEMANTICS : 0;
    HANDLE handle = CreateFileA(path, GENERIC_WRITE,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        NULL, OPEN_EXISTING, flags, NULL);
    if (handle == INVALID_HANDLE_VALUE) {
        return (int)GetLastError();
    }
    if (!FlushFileBuffers(handle)) {
        int error = (int)GetLastError();
        (void)CloseHandle(handle);
        return error;
    }
    if (!CloseHandle(handle)) {
        return (int)GetLastError();
    }
    return 0;
}
#else
#include <fcntl.h>
#include <signal.h>
#include <unistd.h>

void flyology_object_storage_core_crash_process(void) {
    (void)kill(getpid(), SIGKILL);
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
        (void)close(descriptor);
        return error;
    }
    if (close(descriptor) != 0) {
        return errno;
    }
    return 0;
}
#endif

int flyology_object_storage_core_sync_file(const char *path) {
    return sync_path(path, 0);
}

int flyology_object_storage_core_sync_directory(const char *path) {
    return sync_path(path, 1);
}
