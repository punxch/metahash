use std::{fmt, hash::{Hash, Hasher}, path::{Path, PathBuf}, borrow::Cow};
use crate::loc::locbuf::LocBuf;
use crate::scheme::Scheme;

#[derive(Clone, Default, Eq, PartialEq)]
pub struct UrlBuf {
    pub inner: LocBuf,
    pub scheme: Scheme,
}

impl From<PathBuf> for UrlBuf {
    fn from(p: PathBuf) -> Self {
        Self {
            inner: LocBuf::from(p),
            scheme: Scheme::Regular,
        }
    }
}

impl From<&Path> for UrlBuf {
    fn from(p: &Path) -> Self {
        Self {
            inner: LocBuf::from(p.to_path_buf()),
            scheme: Scheme::Regular,
        }
    }
}

impl UrlBuf {
    /// Return owned PathBuf when URL is a regular file-like URL.
    /// Here we always return Some for the simplified wrapper.
    pub fn into_path(&self) -> Option<PathBuf> {
        if self.scheme.is_virtual() {
            None
        } else {
            Some(self.inner.inner.clone())
        }
    }

    pub fn to_string_lossy(&self) -> Cow<'_, str> {
        self.inner.inner.to_string_lossy()
    }
}

impl Hash for UrlBuf {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.inner.hash(state);
        self.scheme.hash(state);
    }
}

impl fmt::Debug for UrlBuf {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{:?}", self.inner)
    }
}