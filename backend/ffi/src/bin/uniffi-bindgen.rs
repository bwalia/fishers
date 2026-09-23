//! The binding generator, as its own binary so the Gradle build can run it
//! without a separately installed tool at a version nobody pinned.
fn main() {
    uniffi::uniffi_bindgen_main()
}
