#ifndef SEEKER_PROBE_LOGIC_H
#define SEEKER_PROBE_LOGIC_H
#include <stdbool.h>
#include <errno.h>

enum SKPresence { SKUnknown = -1, SKAbsent = 0, SKPresent = 1 };
static inline enum SKPresence SKPresenceFromCall(int result, int error) {
    if (result >= 0) return SKPresent;
    return (error == ENOENT || error == ENOTDIR) ? SKAbsent : SKUnknown;
}
static inline bool SKDisagrees(enum SKPresence a, enum SKPresence b) {
    return a != SKUnknown && b != SKUnknown && a != b;
}
static inline const char *SKState(bool found, bool incomplete) {
    return found ? "FIRED" : incomplete ? "UNAVAILABLE" : "NOT OBSERVED";
}
#endif
