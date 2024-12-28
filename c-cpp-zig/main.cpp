// SPDX-FileCopyrightText: NONE
// SPDX-License-Identifier: CC0-1.0

#include "greet.h"
#include <iostream>

int main(void) {
    std::cerr << "Entered main.cpp\n";

    helloFromC();
    helloFromCpp();
    helloFromZig();

    std::cerr << "Leaving main.cpp\n";
    return 0;
}
