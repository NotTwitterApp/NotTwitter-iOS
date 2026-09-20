#ifndef NFBTokenRefreshPolicy_h
#define NFBTokenRefreshPolicy_h
#include <math.h>
#include <stdbool.h>

// Refresh near expiry, without rotating short-lived tokens on every request.
static inline double NFBTokenRefreshLead(double lifetime) {
    return fmin(60.0, fmax(1.0, lifetime * 0.1));
}
static inline bool NFBTokenLifetimeIsValid(double lifetime) {
    return isfinite(lifetime) && lifetime > 0.0;
}
static inline bool NFBTokenRefreshIsDue(double remaining, double lifetime,
                                      bool inFlight, double sinceAttempt) {
    if (inFlight) return true;
    if (remaining > NFBTokenRefreshLead(lifetime)) return false;
    // Failed refreshes are throttled even after expiry; retain the session.
    return sinceAttempt >= 60.0;
}
#endif
