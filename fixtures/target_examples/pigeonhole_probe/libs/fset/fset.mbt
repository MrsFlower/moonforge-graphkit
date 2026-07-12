/// Opaque finite-set carrier used by the set proofs; the abstraction keeps the proof_reasoning
/// focused on membership laws, not representation details.
///
/// The original `verified/libs/fset` also defines `impl Eq for Fset[T]`
/// (calling the `.mbtp`-side `raw_fset_eq` `#proof_import` logic function
/// from ordinary `.mbt` code). That call is itself rejected — a
/// `#proof_import` function is proof-only and unbound outside a `.mbtp`
/// file (real error 4021: "The value identifier raw_fset_eq is unbound"),
/// and even routing through the `.mbtp`-side `Fset::eq` wrapper still
/// fails (real error 4015: "Type Fset has no method eq" — plain `.mbt`
/// code cannot resolve a method defined only in the paired `.mbtp`
/// file). This probe's real target (`scratch_set`'s pigeonhole bound)
/// never compares two `Fset`s with `==`, so the `impl Eq` block — and the
/// `.mbtp` parser bug it was moved here to sidestep — is simply dropped
/// rather than worked around further.
#proof_external("set.Fset", "fset")
pub type Fset[T]
