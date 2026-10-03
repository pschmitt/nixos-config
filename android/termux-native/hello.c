#include <stdio.h>
#include <unistd.h>

#ifndef __BIONIC__
#error "This probe must be compiled against Android Bionic"
#endif

int main(void) {
    printf("Hello from a Nix-built native Bionic executable! API floor=%d, page size=%ld\n",
           __ANDROID_API__, sysconf(_SC_PAGESIZE));
    return 0;
}
