package com.fishers.app.session

import android.content.Context
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.exceptions.NoCredentialException
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.google.android.libraries.identity.googleid.GoogleIdTokenParsingException

/** What asking Google for a token came to. Not an exception: three of the four
 *  are ordinary things that happen to ordinary people. */
sealed interface GoogleResult {
    /** Google vouches for them. Send it to the server, which checks it again. */
    data class Token(val idToken: String) : GoogleResult

    /** They closed the sheet. Said nothing, because they asked for nothing. */
    data object Cancelled : GoogleResult

    /** Play services is there and has no Google account to offer. */
    data object NoAccount : GoogleResult

    /** Anything else: no Play services, or Google could not be reached. */
    data object Failed : GoogleResult
}

/**
 * Ask Google who this is.
 *
 * `serverClientId` is the *web* client id, which `GET /auth/google` hands the
 * app. Credential Manager mints the ID token for that audience, and the server
 * accepts it because the web client id is one of the two it verifies against —
 * the other being the iPhone's. No server change, and one verifier for three
 * platforms.
 *
 * Two things outside this file have to be true for it to work on a real phone,
 * and neither shows up in a build: an **Android** OAuth client must exist in
 * the brand's Google Cloud project for this package name, and it must carry
 * the SHA-1 of the key the app was signed with. Missing, Google answers
 * "no credential available" — which looks exactly like having no account.
 * `docs/ANDROID_RELEASE.md` says which fingerprints and where to find them.
 *
 * `context` must be an Activity: the account chooser is a sheet drawn over it.
 */
suspend fun requestGoogleIdToken(context: Context, serverClientId: String): GoogleResult {
    val request = GetCredentialRequest.Builder()
        .addCredentialOption(GetSignInWithGoogleOption.Builder(serverClientId).build())
        .build()
    return try {
        val credential = CredentialManager.create(context).getCredential(context, request).credential
        if (credential is CustomCredential &&
            credential.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL
        ) {
            GoogleResult.Token(GoogleIdTokenCredential.createFrom(credential.data).idToken)
        } else {
            GoogleResult.Failed
        }
    } catch (e: GetCredentialCancellationException) {
        GoogleResult.Cancelled
    } catch (e: NoCredentialException) {
        GoogleResult.NoAccount
    } catch (e: GetCredentialException) {
        GoogleResult.Failed
    } catch (e: GoogleIdTokenParsingException) {
        GoogleResult.Failed
    }
}
