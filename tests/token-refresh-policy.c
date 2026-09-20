#include "../NFBTokenRefreshPolicy.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    assert(!NFBTokenRefreshIsDue(299, 300, false, INFINITY));
    assert(NFBTokenRefreshIsDue(30, 300, false, INFINITY));
    assert(!NFBTokenRefreshIsDue(31, 300, false, INFINITY));
    assert(NFBTokenRefreshIsDue(60, 3600, false, 60));
    assert(!NFBTokenRefreshIsDue(-10, 300, false, 59));
    assert(NFBTokenRefreshIsDue(-10, 300, false, 60));
    assert(NFBTokenRefreshIsDue(299, 300, true, 0));
    assert(!NFBTokenLifetimeIsValid(NAN));
    assert(!NFBTokenLifetimeIsValid(INFINITY));
    assert(!NFBTokenLifetimeIsValid(0));
    assert(!NFBTokenLifetimeIsValid(-1));
    assert(NFBTokenLifetimeIsValid(300));
    puts("Token refresh policy: 12 checks passed");
}
