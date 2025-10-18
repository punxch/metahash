use std::{
    hash::{Hash, Hasher},
    path::{Path, PathBuf},
};

use crate::cha::Cha;

#[derive(Debug)]
pub struct File {
    pub path: PathBuf,
    pub cha: Cha,
}

impl File {
    pub fn from_path(path: &Path) -> std::io::Result<Self> {
        let metadata = path.metadata()?;
        Ok(Self {
            path: path.to_owned(),
            cha: Cha::from_metadata(&metadata),
        })
    }
}

impl Hash for File {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.path.hash(state);
        self.cha.len.hash(state);
        self.cha.btime.hash(state);
        self.cha.ctime.hash(state);
        // 0usize.hash(state);
        self.cha.mtime.hash(state);
    }
}