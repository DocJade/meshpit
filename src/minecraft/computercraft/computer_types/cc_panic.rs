// When computers panic they return a special type.
// See panicking.md
struct CCPanic {
    stack_trace: String,
    locals: Vec<???>,
    up_values: Vec<???>
}



// =========
// Deserialization
// =========

// We do not implement serialization,
// since we wont send these to computers.