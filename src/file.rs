use std::{
    hash::{Hash, Hasher},
    path::Path,
};

use crate::cha::Cha;
use crate::url::buf::UrlBuf;
use crate::url::traits::UrlLike;


#[derive(Debug, Clone)]
pub struct File {
    pub url: UrlBuf,
    pub cha: Cha,
}

impl File {
    /// Create File from UrlBuf (attempt to get underlying path)
    pub fn from_url(url: &UrlBuf) -> std::io::Result<Self> {
        let path = url.as_path().ok_or_else(|| {
            std::io::Error::new(std::io::ErrorKind::InvalidInput, "url cannot be converted to path")
        })?;
        let metadata = path.metadata()?;
        Ok(Self {
            url: url.clone(),
            cha: Cha::from_metadata(&metadata),
        })
    }
}
impl Hash for File {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.url.hash(state);
        self.cha.len.hash(state);
        self.cha.btime.hash(state);
        self.cha.ctime.hash(state);
        self.cha.mtime.hash(state);
    }
}