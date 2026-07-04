#define _GNU_SOURCE
#include <stdio.h>
#include <string.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <unistd.h>

static int (*real_open)(const char *, int, ...) = NULL;

static void init_hook() {
    if (!real_open) {
        real_open = dlsym(RTLD_NEXT, "open");
    }
}

int is_blocked(const char *pathname) {
    if (!pathname) return 0;

    if (strstr(pathname, "auth.json") != NULL) {
        init_hook();
        if (!real_open) return 0; // Failsafe

        int fd = real_open("/proc/self/cmdline", O_RDONLY);
        if (fd >= 0) {
            char cmdline[512] = {0};
            ssize_t bytes = read(fd, cmdline, 511);
            close(fd);

            if (bytes > 0) {
                // /proc/self/cmdline is a NUL-separated argv vector. Walk it
                // token by token and allow ONLY if a WHOLE argv token equals a
                // known pi identifier. A substring match (the previous
                // approach) let any process whose argv merely contained the
                // bytes "pi " — e.g. `cat "x pi y" auth.json` — read the file.
                // Ensure the buffer is NUL-terminated so the final token is
                // bounded even when the read filled it completely.
                if (bytes < (ssize_t)sizeof(cmdline)) {
                    cmdline[bytes] = '\0';
                } else {
                    cmdline[sizeof(cmdline) - 1] = '\0';
                }
                for (ssize_t i = 0; i < bytes; ) {
                    const char *tok = &cmdline[i];
                    size_t len = strlen(tok); // safe: buffer is NUL-terminated
                    if (len == 0) { i++; continue; }
                    if (strcmp(tok, "/usr/local/bin/pi") == 0 ||
                        strcmp(tok, "pi") == 0 ||
                        strstr(tok, "/pi-coding-agent/dist/cli.js") != NULL) {
                        return 0;
                    }
                    i += (ssize_t)len + 1; // advance past this token and its NUL
                }
            }
        }
        return 1;
    }
    return 0;
}

FILE *fopen(const char *pathname, const char *mode) {
    if (is_blocked(pathname)) {
        errno = EACCES;
        return NULL;
    }
    FILE* (*orig)(const char*, const char*) = dlsym(RTLD_NEXT, "fopen");
    return orig(pathname, mode);
}

int open(const char *pathname, int flags, ...) {
    if (is_blocked(pathname)) {
        errno = EACCES;
        return -1;
    }
    int (*orig)(const char*, int, ...) = dlsym(RTLD_NEXT, "open");
    if (flags & O_CREAT) {
        va_list args;
        va_start(args, flags);
        mode_t mode = va_arg(args, mode_t);
        va_end(args);
        return orig(pathname, flags, mode);
    }
    return orig(pathname, flags);
}

int openat(int dirfd, const char *pathname, int flags, ...) {
    if (is_blocked(pathname)) {
        errno = EACCES;
        return -1;
    }
    int (*orig)(int, const char*, int, ...) = dlsym(RTLD_NEXT, "openat");
    if (flags & O_CREAT) {
        va_list args;
        va_start(args, flags);
        mode_t mode = va_arg(args, mode_t);
        va_end(args);
        return orig(dirfd, pathname, flags, mode);
    }
    return orig(dirfd, pathname, flags);
}

FILE *fopen64(const char *pathname, const char *mode) {
    if (is_blocked(pathname)) {
        errno = EACCES;
        return NULL;
    }
    FILE* (*orig)(const char*, const char*) = dlsym(RTLD_NEXT, "fopen64");
    return orig(pathname, mode);
}

int open64(const char *pathname, int flags, ...) {
    if (is_blocked(pathname)) {
        errno = EACCES;
        return -1;
    }
    int (*orig)(const char*, int, ...) = dlsym(RTLD_NEXT, "open64");
    if (flags & O_CREAT) {
        va_list args;
        va_start(args, flags);
        mode_t mode = va_arg(args, mode_t);
        va_end(args);
        return orig(pathname, flags, mode);
    }
    return orig(pathname, flags);
}

int openat64(int dirfd, const char *pathname, int flags, ...) {
    if (is_blocked(pathname)) {
        errno = EACCES;
        return -1;
    }
    int (*orig)(int, const char*, int, ...) = dlsym(RTLD_NEXT, "openat64");
    if (flags & O_CREAT) {
        va_list args;
        va_start(args, flags);
        mode_t mode = va_arg(args, mode_t);
        va_end(args);
        return orig(dirfd, pathname, flags, mode);
    }
    return orig(dirfd, pathname, flags);
}