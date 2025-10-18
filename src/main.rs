use std::{
    hash::{Hash, Hasher},
    path::PathBuf,
};

use anyhow::Result;
use clap::Parser;
use metahash::{cha, file};

use file::File;

#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)]
struct Args {
    /// File path to calculate metadata hash
    #[arg(value_name = "FILE")]
    file: PathBuf,
}

struct Twox128(twox_hash::XxHash3_128);

impl Default for Twox128 {
    fn default() -> Self {
        Self(twox_hash::XxHash3_128::new())
    }
}

impl Twox128 {
    pub fn finish_128(self) -> u128 {
        self.0.finish_128()
    }
}

impl Hasher for Twox128 {
    fn write(&mut self, bytes: &[u8]) {
        self.0.write(bytes)
    }

    fn finish(&self) -> u64 {
        unimplemented!()
    }
}

fn calculate_hash(file: &File) -> u128 {
    let mut hasher = Twox128::default();
    file.hash(&mut hasher);
    hasher.finish_128()
}

fn main() -> Result<()> {
    let args = Args::parse();
    
    let file = File::from_path(&args.file)?;
    println!("File metadata: {:?}", file);
    
    let hash = calculate_hash(&file);
    // println!("Metadata hash: {:032x}", hash);
    println!("Metadata hash: {:x}", hash);
    
    Ok(())
}
