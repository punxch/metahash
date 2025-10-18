use std::{borrow::Cow, ffi::OsStr, fmt::{Debug, Formatter}, path::{Path, PathBuf}, str::FromStr, sync::OnceLock};

use anyhow::Result;

// use crate::{loc::locbuf::LocBuf, pool::Pool, scheme::Scheme, url::{AsUrl, Encode, EncodeTilded, Url, UrlCow}};
use crate::{loc::locbuf::LocBuf, pool::Pool, scheme::Scheme};
use crate::url::url::Url;

#[derive(Clone, Default, Hash, PartialEq, Debug)]
pub struct UrlBuf {
	pub loc:    LocBuf,
	pub scheme: Scheme,
}

impl From<LocBuf> for UrlBuf {
	fn from(loc: LocBuf) -> Self { Self { loc, scheme: Scheme::Regular } }
}

impl From<PathBuf> for UrlBuf {
	fn from(path: PathBuf) -> Self { LocBuf::from(path).into() }
}

impl From<&Url<'_>> for UrlBuf {
	fn from(url: &Url<'_>) -> Self { Self { loc: url.loc.into(), scheme: url.scheme.into() } }
}

impl From<Url<'_>> for UrlBuf {
	fn from(url: Url<'_>) -> Self { Self { loc: url.loc.into(), scheme: url.scheme.into() } }
}

impl From<&Self> for UrlBuf {
	fn from(url: &Self) -> Self { url.clone() }
}

impl From<&PathBuf> for UrlBuf {
	fn from(path: &PathBuf) -> Self { path.to_owned().into() }
}

impl From<&Path> for UrlBuf {
	fn from(path: &Path) -> Self { path.to_path_buf().into() }
}

// impl FromStr for UrlBuf {
// 	type Err = anyhow::Error;

// 	fn from_str(s: &str) -> Result<Self, Self::Err> { Ok(UrlCow::try_from(s)?.into_owned()) }
// }

impl AsRef<Self> for UrlBuf {
	fn as_ref(&self) -> &Self { self }
}

impl<'a> From<&'a UrlBuf> for Cow<'a, UrlBuf> {
	fn from(url: &'a UrlBuf) -> Self { Cow::Borrowed(url) }
}

impl From<UrlBuf> for Cow<'_, UrlBuf> {
	fn from(url: UrlBuf) -> Self { Cow::Owned(url) }
}

impl From<Cow<'_, Self>> for UrlBuf {
	fn from(url: Cow<'_, Self>) -> Self { url.into_owned() }
}

impl UrlBuf {
	#[inline]
	pub fn new() -> &'static Self {
		static U: OnceLock<UrlBuf> = OnceLock::new();
		U.get_or_init(Self::default)

		// FIXME: use `LocBuf::empty()` when Rust 1.91.0 released
		// static U: UrlBuf = UrlBuf { loc: LocBuf::empty(), scheme: Scheme::Regular
		// }; &U
	}

	// #[inline]
	// pub fn into_path(self) -> Option<PathBuf> {
	// 	Some(self.loc.into_path()).filter(|_| !self.scheme.is_virtual())
	// }

	// #[inline]
	// pub fn set_name(&mut self, name: impl AsRef<OsStr>) { self.loc.set_name(name); }

	// #[inline]
	// pub fn rebase(&self, base: &Path) -> Self {
	// 	Self { loc: self.loc.rebase(base), scheme: self.scheme.clone() }
	// }
}

impl UrlBuf {
	// --- Regular
	// #[inline]
	// pub fn is_regular(&self) -> bool { self.as_url().is_regular() }

	// #[inline]
	// pub fn to_regular(&self) -> Self { self.as_url().into_regular().into() }

	// #[inline]
	// pub fn into_regular(mut self) -> Self {
	// 	self.loc = self.loc.into_path().into();
	// 	self.scheme = Scheme::Regular;
	// 	self
	// }

	// --- Search
	#[inline]
	pub fn is_search(&self) -> bool { matches!(self.scheme, Scheme::Search(_)) }

	// #[inline]
	// pub fn to_search(&self, domain: impl AsRef<str>) -> Self {
	// 	Self {
	// 		loc:    LocBuf::zeroed(self.loc.to_path()),
	// 		scheme: Scheme::Search(Pool::<str>::intern(domain)),
	// 	}
	// }

	// #[inline]
	// pub fn into_search(mut self, domain: impl AsRef<str>) -> Self {
	// 	self.loc = LocBuf::zeroed(self.loc.into_path());
	// 	self.scheme = Scheme::Search(Pool::<str>::intern(domain));
	// 	self
	// }

	// --- Archive
	#[inline]
	pub fn is_archive(&self) -> bool { matches!(self.scheme, Scheme::Archive(_)) }

	// --- Internal
	// #[inline]
	// pub fn is_internal(&self) -> bool {
	// 	match self.scheme {
	// 		Scheme::Regular | Scheme::Sftp(_) => true,
	// 		Scheme::Search(_) => !self.loc.uri().is_empty(),
	// 		Scheme::Archive(_) => false,
	// 	}
	// }
}

// impl Debug for UrlBuf {
// 	fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result { self.as_url().fmt(f) }
// }
