/// Compares doubles within an absolute tolerance. Never compare computed doubles with `==`.
func isApproximately(_ actual: Double, _ expected: Double, tolerance: Double = 1e-9) -> Bool {
    abs(actual - expected) <= tolerance
}
