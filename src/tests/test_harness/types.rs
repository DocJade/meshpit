// miscellaneous types used only in tests.

/// The area that a test occupies. Will make a floor under the test of the size specified.
#[derive(Clone, Copy)]
pub struct TestArea {
    /// How many blocks long (east direction) this test needs
    pub size_x: u16,
    /// How many blocks wide (south direction) this test needs
    pub size_z: u16,
}
