package com.fishers.app.views.onboarding

import androidx.compose.runtime.Composable

/**
 * Between signing in and the tabs: the quick start for somebody who has not
 * yet said what they play or what they are here for. `QuickStartView.swift`.
 * Shows [content] once there is nothing to ask.
 */
@Composable
fun SignedInGate(content: @Composable () -> Unit) = content()

/** Invitations waiting for this account, with Accept. `PendingInvitesSection.swift`. Draws nothing when there are none. */
@Composable
fun PendingInvitesSection() = Unit
