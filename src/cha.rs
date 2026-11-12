use std::{
    fs::Metadata,
    time::SystemTime,
};

#[cfg(unix)]
use std::{
    os::unix::fs::MetadataExt,
    time::{Duration, UNIX_EPOCH},
};

use crate::unix_either;

#[derive(Clone, Debug)]
pub struct Cha {
    pub len: u64,
    pub btime: Option<SystemTime>,
    pub ctime: Option<SystemTime>,
    pub mtime: Option<SystemTime>,
}

impl Cha {
    pub fn from_metadata(metadata: &Metadata) -> Self {
        Self {
            len: metadata.len(),
            btime: metadata.created().ok(),
            ctime: unix_either!(
                UNIX_EPOCH.checked_add(Duration::new(metadata.ctime() as u64, metadata.ctime_nsec() as u32)),
                None
            ),
            mtime: metadata.modified().ok(),
        }
    }
}
