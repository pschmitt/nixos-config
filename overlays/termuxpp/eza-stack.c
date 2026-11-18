#define _GNU_SOURCE
#include <errno.h>
#include <signal.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <unistd.h>

/* SIGSYS path translation needs more stack than Rust's alternate-stack default.
 * Keep this allocation per thread and process-lifetime: the runtime protects
 * registered signal stacks against munmap while a handler may be using them. */
static __thread void *owned;
static const size_t stack_size = 128 * 1024;

int sigaltstack(const stack_t *requested, stack_t *previous) {
  if (!requested || (requested->ss_flags & SS_DISABLE) || requested->ss_size >= stack_size)
    return syscall(SYS_sigaltstack, requested, previous);
  stack_t enlarged = *requested;
  void *memory = owned;
  if (!memory) {
    memory = mmap(NULL, stack_size, PROT_READ | PROT_WRITE,
                  MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (memory == MAP_FAILED) return -1;
  }
  enlarged.ss_sp = memory;
  enlarged.ss_size = stack_size;
  int result = syscall(SYS_sigaltstack, &enlarged, previous);
  if (result == 0) owned = memory;
  else if (!owned) {
    int saved = errno;
    munmap(memory, stack_size);
    errno = saved;
  }
  return result;
}
