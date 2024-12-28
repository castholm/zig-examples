// SPDX-FileCopyrightText: NONE
// SPDX-License-Identifier: CC0-1.0

#include "greet.h"
#include <iostream>

extern "C" void helloFromCpp() {
    std::cerr << "Hello from C++!\n";
}
