#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <dirent.h>

int main(int argc, char **argv) {
    uid_t uid = getuid();
    gid_t gid = getgid();

    if (setuid(0) != 0) return 1;

    // Select the GitHub token secret deterministically. Exactly one gh_* file
    // is expected (docker-compose mounts a single randomized gh_<id>). readdir
    // order is not sorted, so on the (mis)configured multi-match case pick the
    // lexicographically smallest name for a stable choice, and report the
    // anomaly on stderr. Zero matches is not fatal: gh still runs, just
    // unauthenticated, which is preferable to bricking the CLI.
    DIR *d = opendir("/run/secrets");
    if (d) {
        struct dirent *dir;
        char chosen[256] = {0};
        int matches = 0;
        while ((dir = readdir(d)) != NULL) {
            if (strncmp(dir->d_name, "gh_", 3) == 0) {
                matches++;
                if (chosen[0] == 0 || strcmp(dir->d_name, chosen) < 0) {
                    snprintf(chosen, sizeof(chosen), "%s", dir->d_name);
                }
            }
        }
        closedir(d);

        if (matches == 0) {
            fprintf(stderr, "[gh-vault] warning: no gh_* secret in /run/secrets; gh will run unauthenticated\n");
        } else {
            if (matches > 1) {
                fprintf(stderr, "[gh-vault] warning: %d gh_* secrets found; using %s\n", matches, chosen);
            }
            char path[512];
            snprintf(path, sizeof(path), "/run/secrets/%s", chosen);
            FILE *f = fopen(path, "r");
            if (f) {
                char t[256];
                if (fgets(t, sizeof(t), f)) {
                    t[strcspn(t, "\r\n")] = 0;
                    setenv("GITHUB_TOKEN", t, 1);
                    setenv("GH_TOKEN", t, 1);
                }
                fclose(f);
            } else {
                fprintf(stderr, "[gh-vault] warning: cannot open %s\n", path);
            }
        }
    }

    // Drop the group before the user: once the effective uid is no longer root
    // the process may lack the privilege to change groups.
    if (setresgid(gid, gid, gid) != 0) { perror("setresgid"); return 1; }
    if (setresuid(uid, uid, uid) != 0) { perror("setresuid"); return 1; }

    argv[0] = "/usr/local/bin/gh-guard";
    execv("/usr/local/bin/gh-guard", argv);
    
    return 1;
}