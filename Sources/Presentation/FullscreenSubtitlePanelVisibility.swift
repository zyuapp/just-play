import Foundation

struct FullscreenSubtitlePanelVisibility {
  enum HoverEffect: Equatable {
    case show
    case scheduleHide
  }

  private(set) var isVisible = false
  private var isHotspotHovered = false
  private var isPanelHovered = false

  mutating func hotspotHoverChanged(_ hovering: Bool) -> HoverEffect {
    isHotspotHovered = hovering
    return effect(forHovering: hovering)
  }

  mutating func panelHoverChanged(_ hovering: Bool) -> HoverEffect {
    isPanelHovered = hovering
    return effect(forHovering: hovering)
  }

  mutating func hideIfIdle() {
    if !isHotspotHovered, !isPanelHovered {
      isVisible = false
    }
  }

  mutating func reset() {
    isHotspotHovered = false
    isPanelHovered = false
    isVisible = false
  }

  private mutating func effect(forHovering hovering: Bool) -> HoverEffect {
    if hovering {
      isVisible = true
      return .show
    }

    return .scheduleHide
  }
}
