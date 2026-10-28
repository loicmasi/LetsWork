import SwiftUI

extension BatteryStatus {
    /// Vert sur secteur, rouge quand la batterie est faible, blanc sinon.
    var tint: Color {
        if isPluggedIn { return .green }
        return isLow ? .red : .white
    }

    /// « 16 % », selon la langue du système.
    var percentText: String {
        level.formatted(.percent.precision(.fractionLength(0)))
    }
}

/// Pile à la manière de la barre d'état de l'iPhone : contour, remplissage au niveau exact, éclair en charge.
struct BatteryGlyph: View {
    let status: BatteryStatus

    private static let bodySize = CGSize(width: 25, height: 12)
    private static let inset: CGFloat = 2

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .strokeBorder(.white.opacity(0.45), lineWidth: 1)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(status.tint)
                    .frame(width: max(2, (Self.bodySize.width - 2 * Self.inset) * status.level))
                    .padding(Self.inset)
            }
            .frame(width: Self.bodySize.width, height: Self.bodySize.height)
            .overlay {
                if status.isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 1)
                }
            }
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(.white.opacity(0.45))
                .frame(width: 1.5, height: 4)
        }
        .accessibilityHidden(true)
    }
}

/// Niveau de charge de la page d'accueil, dans l'espace à droite de l'encoche.
struct BatteryIndicator: View {
    let status: BatteryStatus

    var body: some View {
        HStack(spacing: 6) {
            Text(status.percentText)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(status.isLow ? .red : .white)
            BatteryGlyph(status: status)
        }
        .help(status.summary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Batterie")
        .accessibilityValue("\(status.percentText), \(status.summary)")
    }
}

/// Au branchement du chargeur, à la manière de l'iPhone : état de charge à gauche, niveau à droite.
struct ChargingIndicatorView: View {
    let status: BatteryStatus
    let notch: NotchGeometry

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.green)
                Text(status.powerTitle)
                    .lineLimit(1)
            }
            .frame(width: IslandMetrics.hudWingWidth)
            Spacer()
                .frame(width: notch.size.width)
            HStack(spacing: 6) {
                Text(status.percentText)
                    .monospacedDigit()
                    .foregroundStyle(.green)
                BatteryGlyph(status: status)
            }
            .frame(width: IslandMetrics.hudWingWidth)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.white)
        .frame(height: notch.size.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.powerTitle)
        .accessibilityValue(status.percentText)
    }
}

/// Alerte de batterie faible, au style de la pop-up de notification : pile et niveau dans les ailes,
/// puis « Batterie faible » et le conseil de brancher le Mac sous l'encoche.
struct LowBatteryAlertView: View {
    let status: BatteryStatus
    let notch: NotchGeometry

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                BatteryGlyph(status: status)
                    .frame(width: IslandMetrics.compactWingWidth)
                Spacer()
                    .frame(width: notch.size.width)
                Text(status.percentText)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.red)
                    .frame(width: IslandMetrics.compactWingWidth)
            }
            .frame(height: notch.size.height)

            VStack(spacing: 2) {
                Text("Batterie faible")
                    .font(.system(size: 12, weight: .semibold))
                Text(status.lowBatteryAdvice)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 22)
            .frame(maxHeight: .infinity)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
    }
}
