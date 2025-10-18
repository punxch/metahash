use std::{fmt, path::PathBuf, hash::{Hash, Hasher}};
use std::ffi::OsString;

use crate::loc::loc::Loc;

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct LocBuf {
    pub(super) inner: PathBuf,
    pub(super) uri:   usize,
	pub(super) urn:   usize,
}

impl From<PathBuf> for LocBuf {
	fn from(path: PathBuf) -> Self {
		let Loc { inner, uri, urn } = Loc::from(path.as_path());
		let len = inner.as_os_str().len();

		let mut bytes = path.into_os_string().into_encoded_bytes();
		bytes.truncate(len);
		Self {
			inner: PathBuf::from(unsafe { OsString::from_encoded_bytes_unchecked(bytes) }),
			uri,
			urn,
		}
	}
}

impl fmt::Display for LocBuf {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{:?}", self.inner)
    }
}

impl Hash for LocBuf {
	fn hash<H: Hasher>(&self, state: &mut H) { self.as_loc().hash(state) }
}

impl LocBuf {
#[inline]
pub fn as_loc<'a>(&'a self) -> Loc<'a> { Loc::from(self) }
}