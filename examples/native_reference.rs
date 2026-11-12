use std::{
    env,
    fs::{self, FileTimes},
    path::Path,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use anyhow::{Result, bail};
use metahash::{
    file::File,
    url::{buf::UrlBuf, traits::UrlLike},
};
use soft_canonicalize::soft_canonicalize;

fn format_time(time: Option<SystemTime>) -> String {
    let Some(time) = time else { return "-".into() };
    let (seconds, nanos) = match time.duration_since(UNIX_EPOCH) {
        Ok(duration) => (i128::from(duration.as_secs()), duration.subsec_nanos()),
        Err(error) => {
            let duration = error.duration();
            let seconds = -i128::from(duration.as_secs());
            match duration.subsec_nanos() {
                0 => (seconds, 0),
                nanos => (seconds - 1, 1_000_000_000 - nanos),
            }
        }
    };
    format!("{seconds}:{nanos}")
}

fn snapshot(path: &Path) -> Result<()> {
    let url = UrlBuf::from(soft_canonicalize(path)?);
    let file = File::from_url(&url)?;
    let encoded_path: String = url
        .as_path()
        .unwrap()
        .as_os_str()
        .as_encoded_bytes()
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect();
    let cha = file.cha;
    println!(
        "{encoded_path}\t{}\t{}\t{}\t{}",
        cha.len,
        format_time(cha.btime),
        format_time(cha.ctime),
        format_time(cha.mtime)
    );
    Ok(())
}

fn main() -> Result<()> {
    let args: Vec<_> = env::args_os().skip(1).collect();
    match args.as_slice() {
        [path] => snapshot(Path::new(path)),
        [flag, path, side] if flag == "--set-mtime" => {
            // These fractions exercise precision finer than Dart DateTime.
            let time = match side.to_str() {
                Some("positive") => {
                    let nanos = if cfg!(windows) {
                        123_456_700
                    } else {
                        123_456_789
                    };
                    UNIX_EPOCH + Duration::new(1_700_000_000, nanos)
                }
                Some("negative") => {
                    let nanos = if cfg!(windows) {
                        987_654_300
                    } else {
                        987_654_321
                    };
                    UNIX_EPOCH - Duration::new(2, nanos)
                }
                _ => bail!("expected positive or negative"),
            };
            fs::OpenOptions::new()
                .write(true)
                .open(path)?
                .set_times(FileTimes::new().set_modified(time))?;
            Ok(())
        }
        _ => bail!("Usage: native_reference <FILE> | --set-mtime <FILE> positive|negative"),
    }
}
