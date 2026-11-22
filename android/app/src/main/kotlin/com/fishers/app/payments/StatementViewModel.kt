package com.fishers.app.payments

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fishers.app.clubs.refusalOf
import com.fishers.app.net.PaymentsApi
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class StatementState(
    /** What the server made of the file; null until one has been read. */
    val preview: StatementPreview? = null,
    /** The lines to apply, by hash: every ticked-off line to start with. */
    val ticked: Set<String> = emptySet(),
    val isReading: Boolean = false,
    val isApplying: Boolean = false,
    /** The file could not be read, or the server could not make sense of it. */
    val error: String? = null,
    /** "8 payments ticked off." once applied. */
    val done: String? = null,
    /** For "Needs a look" in words: the members' names, and the payments waiting to be checked. */
    val names: List<String> = emptyList(),
    val claims: List<Payment> = emptyList(),
) {
    /** What Apply sends: the ticked lines that the server said can be applied. */
    val toSend: List<String> get() = preview?.toApply?.map { it.hash }?.filter { it in ticked }.orEmpty()
}

/**
 * Payments → Import a bank statement, for money admins (§12): pick the CSV
 * from the bank, see what each payment in it matches, untick any that are
 * wrong, and apply the rest in one go.
 *
 * The file is held here and nowhere else — not in [StatementState], whose
 * `toString` could end up printed — and dropped once applied or abandoned.
 */
class StatementViewModel(
    private val api: PaymentsApi,
    private val clubId: String,
) : ViewModel() {

    private val _state = MutableStateFlow(StatementState())
    val state: StateFlow<StatementState> = _state.asStateFlow()

    /** The statement as picked: in memory only, sent as it is, never logged. */
    private var csv: String? = null

    /** A file was picked and read: ask the server what is in it. */
    fun read(text: String) {
        if (_state.value.isReading || _state.value.isApplying) return
        csv = text
        _state.value = StatementState(isReading = true)
        viewModelScope.launch {
            runCatching { api.previewStatement(clubId, JsonUpload.statement(text)) }
                .onSuccess { preview ->
                    _state.update {
                        it.copy(isReading = false, preview = preview, ticked = preview.toApply.map { line -> line.hash }.toSet())
                    }
                    if (preview.toCheck.isNotEmpty()) lookUpWhy()
                }
                .onFailure { e ->
                    // `empty_statement`, `unknown_statement`, `statement_too_long`: each says what to do.
                    val refusal = refusalOf(e)
                    csv = null
                    _state.update { it.copy(isReading = false, error = statementProblem(refusal?.code) ?: failureText(e, refusal)) }
                }
        }
    }

    /** The phone could not read the file itself: too big, or not text. */
    fun fileProblem(text: String) {
        csv = null
        _state.value = StatementState(error = text)
    }

    /** Untick a line that isn't right, or tick it again. */
    fun toggle(hash: String) = _state.update {
        it.copy(ticked = if (hash in it.ticked) it.ticked - hash else it.ticked + hash)
    }

    /**
     * Apply the ticked lines. The server reads the statement again and only
     * applies what it still matches, so a line done meanwhile is skipped and
     * said so; applying the same statement twice changes nothing.
     */
    fun apply() {
        val s = _state.value
        val text = csv ?: return
        val lines = s.toSend
        if (lines.isEmpty() || s.isApplying || s.isReading) return
        _state.update { it.copy(isApplying = true, error = null) }
        viewModelScope.launch {
            runCatching { api.applyStatement(clubId, StatementBody(text, lines)) }
                .onSuccess { applied ->
                    csv = null
                    _state.value = StatementState(done = applied.words())
                }
                .onFailure { e ->
                    val refusal = refusalOf(e)
                    _state.update { it.copy(isApplying = false, error = statementProblem(refusal?.code) ?: failureText(e, refusal)) }
                }
        }
    }

    /** Start again with another file. */
    fun startAgain() {
        csv = null
        _state.value = StatementState()
    }

    /**
     * The words for "Needs a look" want two things the preview leaves out:
     * who in the club shares a surname, and what somebody said they paid.
     * Extras: without them the lines still say why, more plainly.
     */
    private fun lookUpWhy() {
        viewModelScope.launch {
            coroutineScope {
                val members = async { runCatching { api.moneyMembers(clubId) }.getOrNull() }
                val overview = async { runCatching { api.money(clubId) }.getOrNull() }
                val names = members.await()?.map { it.name }.orEmpty()
                val claims = overview.await()?.toCheck.orEmpty()
                _state.update { it.copy(names = names, claims = claims) }
            }
        }
    }

    override fun onCleared() {
        csv = null
    }
}
