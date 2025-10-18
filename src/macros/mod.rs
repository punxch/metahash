// 删除错误的模块声明
// pub mod macros;  // 这行应该被删除

#[macro_export]
macro_rules! unix_either {
    ($a:expr, $b:expr) => {{
        #[cfg(unix)]
        {
            $a
        }
        #[cfg(not(unix))]
        {
            $b
        }
    }};
}

#[macro_export]
macro_rules! win_either {
    ($a:expr, $b:expr) => {{
        #[cfg(windows)]
        {
            $a
        }
        #[cfg(not(windows))]
        {
            $b
        }
    }};
}

#[macro_export]
macro_rules! mod_pub {
    [ $( $name:ident $(,)? )+ ] => {
        $(
            pub mod $name;
        )+
    };
}

#[macro_export]
macro_rules! mod_flat {
    [ $( $name:ident $(,)? )+ ] => {
        $(
            mod $name;
            pub use $name::*;
        )+
    };
}

