// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

import Foundation

func isUsefulString(_ s: String?) -> Bool {
    return s != nil && !s!.isEmpty
}

func nop() {
        // "default label in a switch should have at least one executable statement"
}
