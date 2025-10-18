use crate::mod_flat;
use hashbrown;
use foldhash;
use parking_lot;
use crate::RoCell;  // Now this will work

pub use self::{pool::Pool, symbol::Symbol};
use self::ptr::SymbolPtr;

mod_flat!(pool ptr symbol);

static SYMBOLS: RoCell<
    parking_lot::Mutex<hashbrown::HashMap<SymbolPtr, u64, foldhash::fast::FixedState>>,
> = RoCell::new();

pub(super) fn init() { SYMBOLS.with(<_>::default); }

#[inline]
pub(super) fn compute_hash<T: std::hash::Hash>(value: T) -> u64 {
    use core::hash::BuildHasher;
    foldhash::fast::FixedState::default().hash_one(value)
}

pub trait InternStr {
    fn intern(&self) -> Symbol<str>;
}

impl<T: AsRef<str>> InternStr for T {
    fn intern(&self) -> Symbol<str> { Pool::<str>::intern(self) }
}
