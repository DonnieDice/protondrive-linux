//! Proton SRP Authentication module
//!
//! Handles Proton's SRP-based authentication flow using the official proton-srp crate.

use proton_srp::{SRPAuth, SRPProofB64};
use serde::{Deserialize, Serialize};
use thiserror::Error;
use tokio::sync::RwLock;

#[derive(Error, Debug)]
pub enum AuthError {
    #[error("Network error: {0}")]
    Network(#[from] reqwest::Error),
    #[error("SRP error: {0}")]
    Srp(String),
    #[error("Invalid response: {0}")]
    InvalidResponse(String),
    #[error("2FA required")]
    TwoFactorRequired,
    #[error("Invalid credentials")]
    InvalidCredentials,
    #[error("Not authenticated")]
    NotAuthenticated,
    #[error("Human verification required")]
    HumanVerificationRequired,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuthSession {
    pub uid: String,
    pub access_token: String,
    pub refresh_token: String,
    pub token_type: String,
}

// API Response structures
#[derive(Debug, Deserialize)]
#[serde(rename_all = "PascalCase")]
struct AuthInfoResponse {
    code: i32,
    modulus: String,
    server_ephemeral: String,
    version: i32,
    salt: String,
    #[serde(rename = "SRPSession")]
    srp_session: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "PascalCase")]
struct AuthResponse {
    code: i32,
    #[serde(rename = "UID")]
    uid: String,
    access_token: String,
    refresh_token: String,
    token_type: String,
    server_proof: String,
    #[serde(rename = "2FA")]
    two_fa: Option<TwoFAInfo>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "PascalCase")]
struct TwoFAInfo {
    enabled: i32,
    #[serde(rename = "TOTP")]
    totp: i32,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "PascalCase")]
struct RefreshResponse {
    code: i32,
    access_token: String,
    refresh_token: String,
    token_type: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "PascalCase")]
struct ApiError {
    code: i32,
    error: Option<String>,
}

#[derive(Clone)]
struct Pending2FA {
    uid: String,
    access_token: String,
    refresh_token: String,
    token_type: String,
}

pub struct AuthManager {
    client: reqwest::Client,
    base_url: String,
    session: RwLock<Option<AuthSession>>,
    pending_2fa: RwLock<Option<Pending2FA>>,
}

impl AuthManager {
    pub fn new(base_url: &str) -> Self {
        Self {
            client: reqwest::Client::builder()
                .redirect(reqwest::redirect::Policy::none())
                .build()
                .expect("Failed to create HTTP client"),
            base_url: base_url.to_string(),
            session: RwLock::new(None),
            pending_2fa: RwLock::new(None),
        }
    }

    /// Login with username and password using SRP
    pub async fn login(&self, username: &str, password: &str) -> Result<AuthSession, AuthError> {
        // Step 1: Get auth info (SRP parameters)
        let info = self.get_auth_info(username).await?;

        println!("[Auth] Got SRP params - version: {}, session: {}", info.version, &info.srp_session[..8]);

        // Step 2: Calculate SRP proofs using proton-srp
        let auth = SRPAuth::with_pgp(
            password,
            info.version as u8,
            &info.salt,
            &info.modulus,
            &info.server_ephemeral,
        ).map_err(|e| AuthError::Srp(format!("{:?}", e)))?;

        let proofs: SRPProofB64 = auth
            .generate_proofs()
            .map_err(|e| AuthError::Srp(format!("{:?}", e)))?
            .into();

        println!("[Auth] Generated SRP proofs");

        // Step 3: Submit auth request
        let auth_resp = self.submit_auth(
            username,
            &proofs.client_ephemeral,
            &proofs.client_proof,
            &info.srp_session,
        ).await?;

        // Step 4: Verify server proof
        if !proofs.compare_server_proof(&auth_resp.server_proof) {
            println!("[Auth] Server proof verification FAILED");
            return Err(AuthError::InvalidCredentials);
        }

        println!("[Auth] Server proof verified");

        // Step 5: Check for 2FA
        if let Some(two_fa) = &auth_resp.two_fa {
            if two_fa.enabled != 0 {
                println!("[Auth] 2FA required (TOTP: {})", two_fa.totp);
                let mut pending = self.pending_2fa.write().await;
                *pending = Some(Pending2FA {
                    uid: auth_resp.uid.clone(),
                    access_token: auth_resp.access_token.clone(),
                    refresh_token: auth_resp.refresh_token.clone(),
                    token_type: auth_resp.token_type.clone(),
                });
                return Err(AuthError::TwoFactorRequired);
            }
        }

        // Step 6: Store session
        let session = AuthSession {
            uid: auth_resp.uid,
            access_token: auth_resp.access_token,
            refresh_token: auth_resp.refresh_token,
            token_type: auth_resp.token_type,
        };

        {
            let mut s = self.session.write().await;
            *s = Some(session.clone());
        }

        println!("[Auth] Login successful - UID: {}", &session.uid[..8]);
        Ok(session)
    }

    /// Submit 2FA TOTP code
    pub async fn submit_2fa(&self, totp_code: &str) -> Result<AuthSession, AuthError> {
        let pending = {
            let p = self.pending_2fa.read().await;
            p.clone().ok_or(AuthError::NotAuthenticated)?
        };

        println!("[Auth] Submitting 2FA code");

        let resp = self.client
            .post(format!("{}/api/auth/v4/2fa", self.base_url))
            .header("x-pm-uid", &pending.uid)
            .header("Authorization", format!("{} {}", pending.token_type, pending.access_token))
            .header("x-pm-appversion", "web-drive@5.0.0")
            .header("Content-Type", "application/json")
            .json(&serde_json::json!({
                "TwoFactorCode": totp_code
            }))
            .send()
            .await?;

        if !resp.status().is_success() {
            let status = resp.status();
            let body = resp.text().await.unwrap_or_default();
            println!("[Auth] 2FA failed: {} - {}", status, body);
            return Err(AuthError::InvalidCredentials);
        }

        let session = AuthSession {
            uid: pending.uid,
            access_token: pending.access_token,
            refresh_token: pending.refresh_token,
            token_type: pending.token_type,
        };

        {
            let mut s = self.session.write().await;
            *s = Some(session.clone());
            let mut p = self.pending_2fa.write().await;
            *p = None;
        }

        println!("[Auth] 2FA verification successful");
        Ok(session)
    }

    /// Refresh access token
    pub async fn refresh_token(&self) -> Result<AuthSession, AuthError> {
        let current = {
            let s = self.session.read().await;
            s.clone().ok_or(AuthError::NotAuthenticated)?
        };

        println!("[Auth] Refreshing token for UID: {}", &current.uid[..8]);

        let resp = self.client
            .post(format!("{}/api/auth/v4/refresh", self.base_url))
            .header("x-pm-uid", &current.uid)
            .header("x-pm-appversion", "web-drive@5.0.0")
            .header("Content-Type", "application/json")
            .json(&serde_json::json!({
                "UID": current.uid,
                "RefreshToken": current.refresh_token,
                "ResponseType": "token",
                "GrantType": "refresh_token",
                "RedirectURI": "https://proton.me"
            }))
            .send()
            .await?;

        if !resp.status().is_success() {
            let status = resp.status();
            let body = resp.text().await.unwrap_or_default();
            println!("[Auth] Token refresh failed: {} - {}", status, body);
            return Err(AuthError::InvalidCredentials);
        }

        let refresh: RefreshResponse = resp.json().await
            .map_err(|e| AuthError::InvalidResponse(format!("Failed to parse refresh response: {}", e)))?;

        if refresh.code != 1000 {
            return Err(AuthError::InvalidResponse(format!("Error code: {}", refresh.code)));
        }

        let session = AuthSession {
            uid: current.uid,
            access_token: refresh.access_token,
            refresh_token: refresh.refresh_token,
            token_type: refresh.token_type,
        };

        {
            let mut s = self.session.write().await;
            *s = Some(session.clone());
        }

        println!("[Auth] Token refreshed successfully");
        Ok(session)
    }

    /// Get current session
    pub async fn get_session(&self) -> Option<AuthSession> {
        self.session.read().await.clone()
    }

    /// Set session (for restoring from storage)
    pub async fn set_session(&self, session: AuthSession) {
        let mut s = self.session.write().await;
        *s = Some(session);
    }

    /// Logout
    pub async fn logout(&self) -> Result<(), AuthError> {
        if let Some(session) = self.get_session().await {
            println!("[Auth] Logging out UID: {}", &session.uid[..8]);
            let _ = self.client
                .delete(format!("{}/api/auth/v4", self.base_url))
                .header("x-pm-uid", &session.uid)
                .header("Authorization", format!("{} {}", session.token_type, session.access_token))
                .header("x-pm-appversion", "web-drive@5.0.0")
                .send()
                .await;
        }

        let mut s = self.session.write().await;
        *s = None;

        Ok(())
    }

    // Private helper methods

    async fn get_auth_info(&self, username: &str) -> Result<AuthInfoResponse, AuthError> {
        let resp = self.client
            .post(format!("{}/api/auth/v4/info", self.base_url))
            .header("x-pm-appversion", "web-drive@5.0.0")
            .header("Content-Type", "application/json")
            .json(&serde_json::json!({ "Username": username }))
            .send()
            .await?;

        let status = resp.status();
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_default();
            println!("[Auth] Auth info failed: {} - {}", status, body);

            // Try to parse error
            if let Ok(err) = serde_json::from_str::<ApiError>(&body) {
                if err.code == 9001 {
                    return Err(AuthError::HumanVerificationRequired);
                }
            }

            return Err(AuthError::InvalidCredentials);
        }

        let info: AuthInfoResponse = resp.json().await
            .map_err(|e| AuthError::InvalidResponse(format!("Failed to parse auth info: {}", e)))?;

        if info.code != 1000 {
            return Err(AuthError::InvalidResponse(format!("Error code: {}", info.code)));
        }

        Ok(info)
    }

    async fn submit_auth(
        &self,
        username: &str,
        client_ephemeral: &str,
        client_proof: &str,
        srp_session: &str,
    ) -> Result<AuthResponse, AuthError> {
        let resp = self.client
            .post(format!("{}/api/auth/v4", self.base_url))
            .header("x-pm-appversion", "web-drive@5.0.0")
            .header("Content-Type", "application/json")
            .json(&serde_json::json!({
                "Username": username,
                "ClientEphemeral": client_ephemeral,
                "ClientProof": client_proof,
                "SRPSession": srp_session
            }))
            .send()
            .await?;

        let status = resp.status();
        if !status.is_success() {
            let body = resp.text().await.unwrap_or_default();
            println!("[Auth] Auth submit failed: {} - {}", status, body);
            return Err(AuthError::InvalidCredentials);
        }

        let auth: AuthResponse = resp.json().await
            .map_err(|e| AuthError::InvalidResponse(format!("Failed to parse auth response: {}", e)))?;

        if auth.code != 1000 {
            return Err(AuthError::InvalidResponse(format!("Error code: {}", auth.code)));
        }

        Ok(auth)
    }
}
