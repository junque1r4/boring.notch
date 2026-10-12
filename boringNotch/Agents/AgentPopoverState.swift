// Modified 2026-10-10. SPDX-License-Identifier: GPL-3.0-only
/// Keep the notch open across a transition between the two quota popovers.
struct AgentPopoverState {
    private var presented: Set<String> = []
    var isActive: Bool { !presented.isEmpty }
    mutating func update(providerID: String, showing: Bool) {
        if showing { presented.insert(providerID) } else { presented.remove(providerID) }
    }
    mutating func reset() { presented.removeAll() }
}
