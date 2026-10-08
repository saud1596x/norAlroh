import ManagedSettings
import ManagedSettingsUI
import UIKit

final class NoorFocusShield: ShieldConfigurationDataSource {
    private var ward: ShieldConfiguration {
        let ink = UIColor(red: 0.45, green: 0.27, blue: 0.08, alpha: 1)
        return ShieldConfiguration(backgroundBlurStyle: .systemThinMaterial, backgroundColor: UIColor(red: 1, green: 0.97, blue: 0.91, alpha: 1),
            icon: UIImage(systemName: "book.closed"), title: .init(text: "وردك أولًا", color: ink),
            subtitle: .init(text: "افتح نور الروح وأكمل ورد اليوم. سيُفتح هذا التطبيق تلقائيًا بعد تأكيد قراءة صفحات ورد الختمة.", color: ink),
            primaryButtonLabel: .init(text: "إغلاق", color: .white), primaryButtonBackgroundColor: ink)
    }
    override func configuration(shielding application: Application) -> ShieldConfiguration { ward }
    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration { ward }
}
