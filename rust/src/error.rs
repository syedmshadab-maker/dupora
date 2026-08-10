use std::io;

/// Stable C ABI status codes returned across the FFI boundary.
/// Keep in sync with `lib/core/native/status_code.dart`.
#[repr(i32)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StatusCode {
    Ok = 0,
    Cancelled = 1,
    NotFound = 2,
    PermissionDenied = 3,
    IoError = 4,
    InvalidArgument = 5,
    Unexpected = 6,
}

#[derive(thiserror::Error, Debug)]
pub enum EngineError {
    #[error("operation cancelled")]
    Cancelled,
    #[error("file not found: {0}")]
    NotFound(String),
    #[error("permission denied: {0}")]
    PermissionDenied(String),
    #[error("io error: {0}")]
    Io(#[from] io::Error),
    #[error("invalid argument: {0}")]
    InvalidArgument(String),
}

impl EngineError {
    pub fn status_code(&self) -> StatusCode {
        match self {
            EngineError::Cancelled => StatusCode::Cancelled,
            EngineError::NotFound(_) => StatusCode::NotFound,
            EngineError::PermissionDenied(_) => StatusCode::PermissionDenied,
            EngineError::Io(e) => match e.kind() {
                io::ErrorKind::NotFound => StatusCode::NotFound,
                io::ErrorKind::PermissionDenied => StatusCode::PermissionDenied,
                _ => StatusCode::IoError,
            },
            EngineError::InvalidArgument(_) => StatusCode::InvalidArgument,
        }
    }

    /// Classify a raw io::Error that occurred while opening/reading `path`.
    pub fn from_io_at(err: io::Error, path: &str) -> Self {
        match err.kind() {
            io::ErrorKind::NotFound => EngineError::NotFound(path.to_string()),
            io::ErrorKind::PermissionDenied => EngineError::PermissionDenied(path.to_string()),
            _ => EngineError::Io(err),
        }
    }
}

pub type EngineResult<T> = Result<T, EngineError>;
