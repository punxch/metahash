use std::{fmt, path::PathBuf, hash::{Hash, Hasher}};

#[derive(Clone, Debug, Default, Eq, PartialEq, Hash)]
pub struct LocBuf {
    pub inner: PathBuf,
}

impl From<PathBuf> for LocBuf {
    fn from(p: PathBuf) -> Self { Self { inner: p } }
}

impl fmt::Display for LocBuf {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{:?}", self.inner)
    }
}