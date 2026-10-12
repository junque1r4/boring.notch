// Modified 2026-10-10: Agents integration in the junque1r4 GPL-3.0 fork.
//
//  TabButton.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-24.
//

import SwiftUI

struct TabButton: View {
    let label: String
    let icon: String
    let selected: Bool
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            Group {
                if label == "Agents Status" { AgentsRobotIcon() }
                else if label == "Dot" {
                    Image("DotLogo").renderingMode(.original).resizable().scaledToFit().frame(width: 24, height: 24)
                }
                else { Image(systemName: icon) }
            }
                .padding(.horizontal, 15)
                .contentShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
        .help(label)
        .accessibilityLabel(label)
    }
}

#Preview {
    TabButton(label: "Home", icon: "tray.fill", selected: true) {
        Log.general.debug("Tapped")
    }
}
