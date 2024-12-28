/*
 * SPDX-FileCopyrightText: NONE
 * SPDX-License-Identifier: CC0-1.0
 */

#include "greet.h"
#include <stdio.h>

int main(void) {
    fprintf(stderr, "Entered main.c\n");

    helloFromC();
    helloFromCpp();
    helloFromZig();

    fprintf(stderr, "Leaving main.c\n");
    return 0;
}
