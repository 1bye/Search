import SwiftUI

struct PageTransitionControls: View {
    @ObservedObject var prefs: Preferences
    @State private var replay = 0

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Page transition").font(.system(size: 13)).foregroundStyle(Palette.ink)
                Segmented(options: PageTransition.allCases.map { ($0, $0.title) }, selection: $prefs.pageTransition, wide: true)
                    .accessibilityRepresentation {
                        Picker("Page transition", selection: $prefs.pageTransition) {
                            ForEach(PageTransition.allCases) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented)
                    }
            }
            .padding(14)
            if prefs.pageTransition != .none {
                TransitionPreview(style: prefs.pageTransition, tuning: prefs.pageTransitionTuning, replay: replay)
                    .frame(height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 14)
                    .accessibilityHidden(true)
                HStack {
                    if Motion.reduced {
                        Text("Reduce Motion is on").font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Quick("Reset") { prefs.resetPageTransitionTuning(); replay += 1 }
                    Quick("Preview") { replay += 1 }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                Rule()
                Line("Speed", String(format: "%.2g× · %.0f ms", prefs.pageTransitionTuning.speed,
                                     prefs.pageTransitionTuning.duration * 1000)) {
                    Slider(value: $prefs.pageTransitionTuning.speed, in: 0.25...3, step: 0.05)
                        .frame(width: 150).accessibilityLabel("Transition speed")
                }
                Rule()
                Line("Offset", "\(Int((prefs.pageTransitionTuning.offset * 100).rounded()))% · extra horizontal travel") {
                    Slider(value: $prefs.pageTransitionTuning.offset, in: 0...0.5, step: 0.025)
                        .frame(width: 150).accessibilityLabel("Transition offset")
                }
                Rule()
                Line("Zoom", zoomDescription) {
                    Slider(value: $prefs.pageTransitionTuning.zoom, in: -0.3...0.3, step: 0.025)
                        .frame(width: 150).accessibilityLabel("Transition zoom")
                }
                if prefs.pageTransition == .cube {
                    Rule()
                    Line("Perspective", "\(Int((prefs.pageTransitionTuning.perspective * 100).rounded()))% · cube depth") {
                        Slider(value: $prefs.pageTransitionTuning.perspective, in: 0...2, step: 0.1)
                            .frame(width: 150).accessibilityLabel("Cube perspective")
                    }
                }
            }
        }
    }

    private var zoomDescription: String {
        let zoom = prefs.pageTransitionTuning.zoom
        guard abs(zoom) > 0.001 else { return "No zoom · left out, right in" }
        return "\(Int((abs(zoom) * 100).rounded()))% \(zoom < 0 ? "out" : "in"), then back"
    }
}

/// The live page renderer's transforms, applied to isolated SwiftUI sample cards.
private struct TransitionPreview: View {
    let style: PageTransition
    let tuning: PageTransitionTuning
    let replay: Int
    @State private var progress: CGFloat = 1
    @State private var next = 2

    private struct Run: Equatable {
        let style: PageTransition
        let tuning: PageTransitionTuning
        let replay: Int
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                sample(3 - next)
                    .modifier(Face(progress: progress, incoming: false, direction: next == 2 ? 1 : -1,
                                   size: geometry.size, style: style, tuning: tuning))
                sample(next)
                    .modifier(Face(progress: progress, incoming: true, direction: next == 2 ? 1 : -1,
                                   size: geometry.size, style: style, tuning: tuning))
            }
            .clipped()
        }
        .task(id: Run(style: style, tuning: tuning, replay: replay)) {
            var immediate = Transaction(animation: nil)
            immediate.disablesAnimations = true
            withTransaction(immediate) {
                next = 3 - next
                progress = Motion.reduced ? 1 : 0
            }
            guard !Motion.reduced else { return }
            // Commit the starting pose before animating, including after a slider changes.
            do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            withAnimation(.timingCurve(0.42, 0, 0.58, 1, duration: tuning.duration)) { progress = 1 }
        }
    }

    private func sample(_ number: Int) -> some View {
        HStack(spacing: 18) {
            Text("\(number)").font(.system(size: 42, weight: .light, design: .rounded))
            VStack(alignment: .leading, spacing: 8) {
                Text("Page \(number)").font(.system(size: 15, weight: .medium))
                RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.5)).frame(width: 130, height: 4)
                RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.3)).frame(width: 90, height: 4)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(number == 1 ? Color(red: 0.24, green: 0.33, blue: 0.72) : Color(red: 0.15, green: 0.52, blue: 0.49))
        .drawingGroup()
    }

    private struct Face: AnimatableModifier {
        var progress: CGFloat
        let incoming: Bool
        let direction: CGFloat
        let size: CGSize
        let style: PageTransition
        let tuning: PageTransitionTuning

        var animatableData: CGFloat {
            get { progress }
            set { progress = newValue }
        }

        func body(content: Content) -> some View {
            let fades = style == .fade || style == .zoom
            content
                .overlay(Color.black.opacity(style == .cube ? Double(incoming ? 1 - progress : progress) * 0.22 : 0))
                .projectionEffect(ProjectionTransform(PageMotion.transform(
                    progress: progress, incoming: incoming, direction: direction, size: size, anchor: .zero,
                    style: style, tuning: tuning)))
                .opacity(!incoming && progress >= 1 ? 0 : (incoming && fades ? Double(progress) : 1))
        }
    }
}
