import DeviceActivity

final class NoorFocusMonitor: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        guard activity == NoorFocusState.activity else { return }
        NoorFocusState.apply()
    }
}
