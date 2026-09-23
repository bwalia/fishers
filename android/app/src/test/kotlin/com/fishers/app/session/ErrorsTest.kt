package com.fishers.app.session

import okhttp3.MediaType.Companion.toMediaType
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import retrofit2.HttpException
import retrofit2.Response
import java.io.IOException

/**
 * What somebody reads when it goes wrong.
 *
 * This is not cosmetic. "Unable to resolve host" tells a captain nothing they
 * can act on; "no connection" tells them to walk to the other end of the
 * ground. The two that matter — wrong details, and no signal — need different
 * things from the reader, so they must not read the same.
 */
class ErrorsTest {

    private fun http(code: Int) = HttpException(
        Response.error<Any>(code, "".toResponseBody("application/json".toMediaType())),
    )

    @Test
    fun `a refusal says the details were wrong, not that the request failed`() {
        assertEquals("That email or password was not right.", readableError(http(401)))
    }

    @Test
    fun `being rate limited says to wait, because trying harder makes it worse`() {
        assertTrue(readableError(http(429)).contains("minute"))
    }

    @Test
    fun `a server fault is not blamed on the reader`() {
        val message = readableError(http(503))
        assertTrue(message, message.contains("server"))
        assertTrue("and it does not accuse them", !message.contains("password"))
    }

    @Test
    fun `no signal reads as no signal`() {
        val message = readableError(IOException("Unable to resolve host \"int.fishers.cloud\""))
        assertTrue(message, message.contains("connection"))
        assertTrue("without the hostname nobody can act on", !message.contains("resolve"))
    }

    @Test
    fun `anything else still says something`() {
        assertTrue(readableError(IllegalStateException()).isNotBlank())
    }
}
