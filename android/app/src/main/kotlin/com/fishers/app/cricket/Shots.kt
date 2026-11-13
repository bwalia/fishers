package com.fishers.app.cricket

import com.fishers.app.i18n.t

/** How often the scorer is asked where the ball went. `WagonWheelMode` in `LiveScorerView.swift`. */
enum class WheelMode(val wire: String) {
    Off("off"), Boundaries("boundaries"), EveryShot("everyScoringShot");

    fun asks(runs: Int): Boolean = when (this) {
        Off -> false
        Boundaries -> runs >= 4
        EveryShot -> runs > 0
    }

    val label: String
        get() = when (this) {
            Off -> t("sc.off_label")
            Boundaries -> t("ld.boundaries")
            EveryShot -> t("sc.every_shot")
        }

    companion object {
        fun of(wire: String?) = entries.firstOrNull { it.wire == wire } ?: EveryShot
    }
}

/** The strokes, in the wire names `ShotKind` uses, and where each region is. */
object Shots {
    val kinds = listOf(
        "drive", "cut", "pull", "hook", "sweep", "reverse_sweep", "glance",
        "flick", "loft", "defence", "edge", "leave", "other",
    )

    /** The shots that actually make this many runs, first. */
    fun likely(runs: Int): List<String> = when (runs) {
        0 -> listOf("defence", "leave", "edge", "drive", "cut", "pull", "other")
        4 -> listOf("drive", "cut", "pull", "sweep", "glance", "flick", "edge", "loft")
        6 -> listOf("loft", "pull", "hook", "drive", "sweep")
        else -> listOf("drive", "flick", "glance", "cut", "pull", "sweep", "other")
    }

    fun ordered(runs: Int): List<String> = likely(runs).let { it + kinds.filterNot(it::contains) }

    fun label(kind: String): String = t("shot.$kind")

    /**
     * The batter's own field, named — `region_for` in `backend/cricket/src/types.rs`.
     * `angle` is 0 straight down the ground past the bowler, clockwise; a
     * left-hander's field is the mirror image, so the same angle gets the
     * opposite name.
     */
    fun region(angle: Int, batsLeft: Boolean): String {
        val a = ((angle % 360) + 360) % 360
        val seen = if (batsLeft) (360 - a) % 360 else a
        return t(
            when (seen) {
                in 0..44 -> "region.long_on"
                in 45..89 -> "region.mid_wicket"
                in 90..134 -> "region.square_leg"
                in 135..179 -> "region.fine_leg"
                in 180..224 -> "region.third_man"
                in 225..269 -> "region.point"
                in 270..314 -> "region.cover"
                else -> "region.long_off"
            },
        )
    }
}
