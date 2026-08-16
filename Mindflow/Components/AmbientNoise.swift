//
//  AmbientNoise.swift
//  Mindflow
//

import SwiftUI

struct AmbientNoise: View {
    private let specks = (0..<260).map { index in
        NoiseSpeck(
            x: Double((index * 47) % 101) / 100,
            y: Double((index * 83) % 103) / 102,
            opacity: Double((index * 19) % 29) / 100 + 0.02
        )
    }

    var body: some View {
        Canvas { context, size in
            for speck in specks {
                let rect = CGRect(
                    x: speck.x * size.width,
                    y: speck.y * size.height,
                    width: 1.5,
                    height: 1.5
                )
                context.opacity = speck.opacity
                context.fill(Path(ellipseIn: rect), with: .color(.white))
            }
        }
        .blendMode(.screen)
    }
}

private struct NoiseSpeck {
    let x: Double
    let y: Double
    let opacity: Double
}
