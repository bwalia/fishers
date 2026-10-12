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
        Self::bad_request(say(&err))
    }
}

/// What a failed validation should sound like to the person who typed it.
///
/// `ValidationErrors::to_string()` is a debug dump of the crate's own structs,
/// and it went out as the API's `error` field — which every client shows
/// verbatim, because it is the one place the server gets to explain itself.
/// Signing up with a number in the email box answered:
///
/// ```text
/// email: Validation error: email [{"value": String("+447700900123")}]
/// password: Validation error: length [{"value": String("short"), "min": Number(8), ...}]
/// ```
///
/// Both the web and the iOS app put that in front of people. They are club
/// cricketers; `String(...)` and `Number(8)` are the API talking about its
/// crates. Fixing it here fixes every client at once, which is why it is here
/// and not in either of them.
fn say(errors: &validator::ValidationErrors) -> String {
    let mut lines: Vec<String> = errors
        .field_errors()
        .iter()
        .flat_map(|(field, errs)| errs.iter().map(move |e| sentence(field, e)))
        .collect();
    // field_errors() is a HashMap, so without this the same bad form answers
    // in a different order each time — and a test could only ever be flaky.
    lines.sort();
    lines.join(" ")
}

/// One field's failure, as a sentence.
fn sentence(field: &str, e: &validator::ValidationError) -> String {
    // A `custom` validator that set its own message has already said it better
    // than anything here could: it knows the rule it was checking.
    if let Some(message) = &e.message {
        return format!("{} {message}.", label(field));
    }
    let n = |key: &str| e.params.get(key).and_then(serde_json::Value::as_i64);
    let detail = match e.code.as_ref() {
        "email" => "does not look like an email address".to_string(),
        "url" => "must be a web address".to_string(),
        "required" => "is required".to_string(),
        "length" => match (n("min"), n("max")) {
            (Some(1), None) => "cannot be empty".to_string(),
            (Some(min), Some(max)) => format!("must be between {min} and {max} characters"),
            (Some(min), None) => format!("must be at least {min} characters"),
            (None, Some(max)) => format!("must be {max} characters or fewer"),
            (None, None) => "is the wrong length".to_string(),
        },
        "range" => match (n("min"), n("max")) {
            (Some(min), Some(max)) => format!("must be between {min} and {max}"),
            (Some(min), None) => format!("must be {min} or more"),
            (None, Some(max)) => format!("must be {max} or less"),
            (None, None) => "is out of range".to_string(),
        },
        _ => "is not valid".to_string(),
    };
    format!("{} {detail}.", label(field))
}

/// A field name as a person would write it. `phone` is the one the app calls
/// something else on screen, so it is named here rather than humanised.
fn label(field: &str) -> String {
    if field == "phone" {
        return "Mobile number".to_string();
    }
    let spaced = field.replace('_', " ");
    let mut chars = spaced.chars();
    match chars.next() {
        Some(first) => first.to_uppercase().collect::<String>() + chars.as_str(),
        None => "That".to_string(),
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
    use super::{say, taken};
    use validator::Validate;

    #[derive(Validate)]
    struct Signup<'a> {
        #[validate(email)]
        email: &'a str,
        #[validate(length(min = 8, max = 128))]
        password: &'a str,
    }

    #[derive(Validate)]
    struct Innings {
        #[validate(range(min = 1, max = 99))]
        overs: u8,
        #[validate(length(min = 1))]
        name: String,
    }

    /// The report that started this: a mobile number typed into the email box
    /// on sign-up, with a short password. It used to answer
    /// `email: Validation error: email [{"value": String("+447700900123")}]`.
    #[test]
    fn a_bad_signup_reads_as_sentences() {
        let err = Signup { email: "+447700900123", password: "short" }
            .validate()
            .unwrap_err();
        assert_eq!(
            say(&err),
            "Email does not look like an email address. Password must be between 8 and 128 characters."
        );
    }

    #[test]
    fn nothing_leaks_the_crate_s_debug_shape() {
        let err = Signup { email: "nope", password: "" }.validate().unwrap_err();
        let said = say(&err);
        for leak in ["Validation error", "String(", "Number(", "params", "[{"] {
            assert!(!said.contains(leak), "{said:?} still contains {leak:?}");
        }
    }

    #[test]
    fn numbers_and_lengths_each_get_their_own_wording() {
        let err = Innings { overs: 0, name: String::new() }.validate().unwrap_err();
        assert_eq!(say(&err), "Name cannot be empty. Overs must be between 1 and 99.");
    }

    /// field_errors() is a HashMap, so the order has to be imposed somewhere.
    #[test]
    fn the_same_bad_form_always_answers_the_same_way() {
        let once = {
            let err = Signup { email: "nope", password: "x" }.validate().unwrap_err();
            say(&err)
        };
        for _ in 0..50 {
            let err = Signup { email: "nope", password: "x" }.validate().unwrap_err();
            assert_eq!(say(&err), once);
        }
    }

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
