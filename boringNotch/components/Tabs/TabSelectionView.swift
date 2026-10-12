// Modified 2026-10-10: Agents integration in the junque1r4 GPL-3.0 fork.
//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import SwiftUI
import Defaults

struct TabModel: Identifiable {
    var id: String { label }
    let label: String
    let icon: String
    let view: NotchViews
}

let tabs = [
    TabModel(label: "Home", icon: "house.fill", view: .home),
    TabModel(label: "Shelf", icon: "tray.fill", view: .shelf),
    TabModel(label: "Agents Status", icon: "", view: .agents),
    TabModel(label: "Dot", icon: "bubble.left.and.bubble.right.fill", view: .dot)
]

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.boringShelf) private var shelfEnabled
    @Namespace var animation
    private var visibleTabs: [TabModel] {
        Self.availableTabs(shelfEnabled: shelfEnabled)
    }
    static func availableTabs(shelfEnabled: Bool) -> [TabModel] {
        shelfEnabled ? tabs : [tabs[0], tabs[2], tabs[3]]
    }
    var body: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs) { tab in
                    TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view) {
                        withAnimation(.smooth) {
                            coordinator.currentView = tab.view
                        }
                    }
                    .frame(height: 26)
                    .overlay(alignment: .topTrailing) {
                        if tab.view == .dot && DotChatStore.shared.unreadCount > 0 {
                            Text(DotChatStore.shared.unreadCount > 9 ? "9+" : "\(DotChatStore.shared.unreadCount)")
                                .font(.system(size: 8, weight: .bold)).foregroundStyle(.black)
                                .padding(.horizontal, 3).frame(minWidth: 12, minHeight: 12)
                                .background(.yellow, in: Capsule()).padding(.trailing, 4)
                                .accessibilityLabel("\(DotChatStore.shared.unreadCount) unread Dot replies")
                                .allowsHitTesting(false)
                        }
                    }
                    .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
                    .background {
                        if tab.view == coordinator.currentView {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                        } else {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                                .hidden()
                        }
                    }
            }
        }
        .clipShape(Capsule())
    }
}

struct AgentsRobotIcon: View {
    var body: some View {
        ZStack {
            Capsule().frame(width: 2, height: 4).offset(y: -7)
            Circle().frame(width: 3, height: 3).offset(y: -10)
            RoundedRectangle(cornerRadius: 4).stroke(lineWidth: 1.5)
                .frame(width: 13, height: 10).offset(y: 1)
            HStack(spacing: 3) {
                Circle().frame(width: 2, height: 2)
                Circle().frame(width: 2, height: 2)
            }.offset(y: 0)
            Capsule().frame(width: 5, height: 1.5).offset(y: 4)
        }
        .frame(width: 17, height: 18)
        .accessibilityHidden(true)
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel(camera: CameraModel()))
}
