#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>

extern char **environ;

static int valid_component(const char *value) {
  if (value[0] == '\0' || strcmp(value, ".") == 0 || strcmp(value, "..") == 0) {
    return 0;
  }
  for (const char *cursor = value; *cursor != '\0'; cursor++) {
    if (!(('a' <= *cursor && *cursor <= 'z') ||
          ('A' <= *cursor && *cursor <= 'Z') ||
          ('0' <= *cursor && *cursor <= '9') || *cursor == '.' ||
          *cursor == '_' || *cursor == '+' || *cursor == '-')) {
      return 0;
    }
  }
  return 1;
}

static int valid_binary_path(const char *value) {
  if (strncmp(value, "bin/", 4) != 0) {
    return 0;
  }
  const char *component = value;
  for (const char *cursor = value;; cursor++) {
    if (*cursor == '/' || *cursor == '\0') {
      size_t length = (size_t)(cursor - component);
      if (length == 0 || length >= NAME_MAX) {
        return 0;
      }
      char part[NAME_MAX];
      memcpy(part, component, length);
      part[length] = '\0';
      if (!valid_component(part)) {
        return 0;
      }
      if (*cursor == '\0') {
        break;
      }
      component = cursor + 1;
    }
  }
  return 1;
}

static int fail(const char *message) {
  fprintf(stderr, "termux-native launcher: %s\n", message);
  return 126;
}

int main(int argc, char **argv) {
  (void)argc;
  const char *generation = getenv("TERMUX_GENERATION");
  const char *home = getenv("HOME");
  if (generation == NULL || generation[0] == '\0') {
    if (home == NULL || home[0] == '\0') {
      return fail("HOME is not set");
    }
    static char current[PATH_MAX];
    int written = snprintf(current, sizeof(current),
                           "%s/.local/share/termux-native/current", home);
    if (written < 0 || (size_t)written >= sizeof(current)) {
      return fail("generation path is too long");
    }
    generation = current;
  }

  const char *command = strrchr(argv[0], '/');
  command = command == NULL ? argv[0] : command + 1;
  if (!valid_component(command)) {
    return fail("invalid command name");
  }

  char config_path[PATH_MAX];
  int written = snprintf(config_path, sizeof(config_path),
                         "%s/launchers/%s", generation, command);
  if (written < 0 || (size_t)written >= sizeof(config_path)) {
    return fail("launcher configuration path is too long");
  }

  FILE *config = fopen(config_path, "r");
  if (config == NULL) {
    fprintf(stderr, "termux-native launcher: open %s: %s\n", config_path,
            strerror(errno));
    return 126;
  }

  char package[NAME_MAX];
  char binary[PATH_MAX];
  int fields = fscanf(config, "%254s %4095s", package, binary);
  fclose(config);
  if (fields != 2 || !valid_component(package) ||
      !valid_binary_path(binary)) {
    return fail("invalid launcher configuration");
  }

  char target[PATH_MAX];
  written = snprintf(target, sizeof(target), "%s/native/%s/%s", generation,
                     package, binary);
  if (written < 0 || (size_t)written >= sizeof(target)) {
    return fail("target path is too long");
  }

  const char *existing_library_path = getenv("LD_LIBRARY_PATH");
  size_t library_path_size = strlen(generation) * 2 + strlen(package) * 2 +
                             sizeof("/native//lib:/native//lib64") + 1;
  if (existing_library_path != NULL) {
    library_path_size += strlen(existing_library_path) + 1;
  }
  char *library_path = malloc(library_path_size);
  if (library_path == NULL) {
    return fail("out of memory");
  }
  written = snprintf(library_path, library_path_size,
                     "%s/native/%s/lib:%s/native/%s/lib64%s%s", generation,
                     package, generation, package,
                     existing_library_path == NULL ? "" : ":",
                     existing_library_path == NULL ? "" :
                                                     existing_library_path);
  if (written < 0 || (size_t)written >= library_path_size ||
      setenv("LD_LIBRARY_PATH", library_path, 1) != 0) {
    free(library_path);
    return fail("could not set package library path");
  }
  free(library_path);

  argv[0] = (char *)command;
  syscall(SYS_execve, target, argv, environ);
  fprintf(stderr, "termux-native launcher: exec %s: %s\n", target,
          strerror(errno));
  return errno == ENOENT ? 127 : 126;
}
