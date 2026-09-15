use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde_json::json;

#[derive(Debug)]
pub struct ApiError {
    pub status: StatusCode,
    pub message: String,
    /// A stable reason a client can branch on, where the message is for
    /// people. "unverified" means: send them to verify, not to an error page.
    pub code: Option<&'static str>,
}

impl ApiError {
    pub fn bad_request(msg: impl Into<String>) -> Self {
        Self {
            status: StatusCode::BAD_REQUEST,
            message: msg.into(),
            code: None,
        }
    }

    pub fn unauthorized(msg: impl Into<String>) -> Self {
        Self {
            status: StatusCode::UNAUTHORIZED,
            message: msg.into(),
            code: None,
        }
    }

    pub fn forbidden(msg: impl Into<String>) -> Self {
        Self {
            status: StatusCode::FORBIDDEN,
            message: msg.into(),
            code: None,
        }
    }

    pub fn not_found(msg: impl Into<String>) -> Self {
        Self {
            status: StatusCode::NOT_FOUND,
            message: msg.into(),
            code: None,
        }
    }

    pub fn conflict(msg: impl Into<String>) -> Self {
        Self {
            status: StatusCode::CONFLICT,
            message: msg.into(),
            code: None,
        }
    }

    pub fn internal(msg: impl Into<String>) -> Self {
        Self {
            status: StatusCode::INTERNAL_SERVER_ERROR,
            message: msg.into(),
            code: None,
        }
    }
}

impl ApiError {
    pub fn with_code(mut self, code: &'static str) -> Self {
        self.code = Some(code);
        self
    }

    pub fn too_many(msg: impl Into<String>) -> Self {
        Self {
            status: StatusCode::TOO_MANY_REQUESTS,
            message: msg.into(),
            code: None,
        }
    }

    pub fn unavailable(msg: impl Into<String>) -> Self {
        Self {
            status: StatusCode::SERVICE_UNAVAILABLE,
            message: msg.into(),
            code: None,
        }
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let body = Json(match self.code {
            Some(code) => json!({ "error": self.message, "code": code }),
            None => json!({ "error": self.message }),
        });
        (self.status, body).into_response()
    }
}

impl From<sqlx::Error> for ApiError {
    fn from(err: sqlx::Error) -> Self {
        match err {
            sqlx::Error::RowNotFound => Self::not_found("resource not found"),
            sqlx::Error::Database(db) if db.constraint().is_some() => Self::conflict(
                db.constraint()
                    .and_then(taken)
                    .map_or_else(|| db.message().to_string(), str::to_string),
            ),
            other => {
                tracing::error!(error = %other, "database error");
                Self::internal("database error")
            }
        }
    }
}

impl From<validator::ValidationErrors> for ApiError {
    fn from(err: validator::ValidationErrors) -> Self {
        Self::bad_request(err.to_string())
    }
}

pub type ApiResult<T> = Result<T, ApiError>;

/// The sentence for a value somebody else already has. Postgres says
/// `duplicate key value violates unique constraint "users_phone_key"`, which
/// reached a person typing their number into the app word for word.
fn taken(constraint: &str) -> Option<&'static str> {
    match constraint {
        "users_phone_key" => Some("that mobile number is already on another account"),
        "users_email_key" => Some("that email is already on another account"),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::taken;

    #[test]
    fn a_taken_number_reads_as_a_sentence() {
        assert_eq!(
            taken("users_phone_key"),
            Some("that mobile number is already on another account")
        );
        assert_eq!(
            taken("users_email_key"),
            Some("that email is already on another account")
        );
        assert_eq!(taken("some_other_key"), None);
    }
}
