// SPDX-License-Identifier: MIT
// Copyright (c) 2026 José González Divassón
//
// KeyClick.swift - plays the key click (KeyClickSound, the Qt app's sound) without blocking the caller.

import AVFoundation
import Foundation

@MainActor
enum KeyClick {
    /// Tests: how many times play() was called (whether or not a sound device exists).
    private(set) static var playCount = 0
    private static var players: [AVAudioPlayer] = []
    private static var next = 0

    /// Play once. A few players in turn, so fast typing overlaps instead of cutting the previous click off.
    static func play() {
        playCount += 1
        if players.isEmpty {
            let wav = KeyClickSound.wav()
            players = (0..<4).compactMap { _ in try? AVAudioPlayer(data: wav, fileTypeHint: AVFileType.wav.rawValue) }
            players.forEach { $0.volume = 0.8; $0.prepareToPlay() }
        }
        guard !players.isEmpty else { return }
        let p = players[next % players.count]; next += 1
        p.currentTime = 0
        p.play()
    }
}
