export type PlayerStateName = "Lobby" | "Safe"
export type RoundPhase = "Lobby" | "Intermission" | "Reveal" | "Round" | "End"
export type EndReason = "Survived" | "LastStanding" | "Aborted"

export type RoundEndExtra = {
	winners: { string },
	reason: EndReason,
}

return {}
