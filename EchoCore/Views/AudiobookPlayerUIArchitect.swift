import SwiftUI

@MainActor
@Observable
final class AudiobookArchitectModel {
    // Top Navigation
    var buttonVerticalSafetyOffset: Double = 20
    var scrimGradientOpacity: Double = 0.7
    
    // Image & Overlays
    enum CoverSizingStrategy: String, CaseIterable {
        case fitFullWidth = "Fit Full Width (Turn 7)"
        case fitInTopArea = "Fit in Top Area (Turn 5)"
    }
    var coverSizingStrategy: CoverSizingStrategy = .fitFullWidth
    
    enum DynamicColorLogic: String, CaseIterable {
        case bottomLeftArt = "Extraction: Bottom-Left Art"
        case dominantArt = "Extraction: Dominant Art"
        case manualFallback = "Manual Color Fallback"
    }
    var dynamicColorLogic: DynamicColorLogic = .bottomLeftArt
    
    enum LowerBackgroundBlend: String, CaseIterable {
        case smoothDynamic = "Smooth Dynamic Blend (Turn 5)"
        case neutralDark = "Neutral Dark (Turn 7)"
    }
    var lowerBackgroundBlend: LowerBackgroundBlend = .smoothDynamic
    
    // Progress Bars
    enum SegmentationStrategy: String, CaseIterable {
        case chapterDurations = "Chapter Durations"
        case fixed15Min = "Fixed 15min Intervals"
        case fixedCount = "Turn 6 Fixed Count (6)"
    }
    var segmentationStrategy: SegmentationStrategy = .chapterDurations
    var globalBarSegmentCount: Double = 6
    var scrubberProgress: Double = 0.4
    
    // Control Deck
    enum TransportInternalLayout: String, CaseIterable {
        case arched = "Arched (Arch layout)"
        case staggered = "Staggered"
        case linear = "Linear (Turn 7)"
    }
    var transportInternalLayout: TransportInternalLayout = .linear
    
    var primaryButtonGlyphSize: Double = 1.0
    var secondaryButtonGlyphSize: Double = 1.0
    var buttonTargetPaddingOpacity: Double = 0.2
    
    enum MaterialChoice: String, CaseIterable {
        case ultraThin = "ultraThinMaterial"
        case regular = "regularMaterial"
        case thick = "thickMaterial"
        
        var material: Material {
            switch self {
            case .ultraThin: return .ultraThinMaterial
            case .regular: return .regularMaterial
            case .thick: return .thickMaterial
            }
        }
    }
    var materialType: MaterialChoice = .regular
    var verticalPillarSpacing: Double = 16
    
    // Derived properties
    var extractedColor: Color {
        switch dynamicColorLogic {
        case .bottomLeftArt: return .orange
        case .dominantArt: return .blue
        case .manualFallback: return .accentColor
        }
    }
}

struct AudiobookPlayerUIArchitect: View {
    @State private var model = AudiobookArchitectModel()
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Simulation Canvas
                simulationCanvas
                    .frame(height: 500)
                    .clipShape(.rect(cornerRadius: 32))
                    .padding()
                    .shadow(radius: 10)
                
                Divider()
                
                // Control Panel
                ScrollView {
                    controlPanel
                        .padding()
                }
            }
            .navigationTitle("Player Architect")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    // MARK: - Simulation Canvas
    
    @ViewBuilder
    private var simulationCanvas: some View {
        ZStack(alignment: .top) {
            // Background
            backgroundLayer
            
            VStack(spacing: 0) {
                // Image and Overlays
                ZStack(alignment: .top) {
                    artworkLayer
                    
                    // Scrim
                    LinearGradient(
                        colors: [.black.opacity(model.scrimGradientOpacity), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 100)
                    .allowsHitTesting(false)
                    
                    // Top buttons
                    HStack {
                        circleButton(systemImage: "folder")
                        Spacer()
                        // Fake Dynamic Island space
                        Capsule()
                            .fill(.black)
                            .frame(width: 120, height: 36)
                        Spacer()
                        circleButton(systemImage: "ellipsis")
                    }
                    .padding(.horizontal)
                    .padding(.top, model.buttonVerticalSafetyOffset)
                    
                    // Image Bottom Overlays
                    VStack(alignment: .leading) {
                        Spacer()
                        Text("Chapter 10: The Legacy Systems")
                            .font(.headline)
                            .foregroundStyle(.white)
                        HStack {
                            Text("10:15").bold()
                            Text("-11:45").foregroundStyle(.white.opacity(0.7))
                        }
                        .font(.subheadline)
                        .foregroundStyle(model.extractedColor)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
                
                // Progress Bars
                VStack(spacing: 8) {
                    globalProgressBar
                        .frame(height: 4)
                    
                    Slider(value: $model.scrubberProgress)
                        .tint(model.extractedColor)
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                Spacer()
                
                // Bottom Deck (Pill Layouts)
                VStack(spacing: model.verticalPillarSpacing) {
                    transportPill
                    bottomToolbarPill
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
        }
    }
    
    @ViewBuilder
    private var backgroundLayer: some View {
        switch model.lowerBackgroundBlend {
        case .smoothDynamic:
            LinearGradient(
                colors: [Color.brown.opacity(0.3), Color(uiColor: .systemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        case .neutralDark:
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
        }
    }
    
    @ViewBuilder
    private var artworkLayer: some View {
        GeometryReader { proxy in
            // Mock artwork (using a gradient to simulate)
            LinearGradient(colors: [.orange, .brown, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(
                    width: proxy.size.width,
                    height: model.coverSizingStrategy == .fitFullWidth ? proxy.size.width : proxy.size.width * 0.8
                )
                .clipShape(
                    .rect(cornerRadius: model.coverSizingStrategy == .fitFullWidth ? 0 : 16)
                )
                .padding(.horizontal, model.coverSizingStrategy == .fitFullWidth ? 0 : 16)
                .padding(.top, model.coverSizingStrategy == .fitFullWidth ? 0 : 16)
        }
        .frame(height: 350)
    }
    
    private func circleButton(systemImage: String) -> some View {
        Button(action: {}) {
            Image(systemName: systemImage)
                .foregroundStyle(.primary)
                .padding(10)
                .background(.ultraThinMaterial)
                .clipShape(.circle)
        }
    }
    
    @ViewBuilder
    private var globalProgressBar: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                let segments = calculateSegments()
                ForEach(0..<segments.count, id: \.self) { index in
                    let weight = segments[index]
                    let totalWeight = segments.reduce(0, +)
                    let width = max(0, (proxy.size.width - CGFloat(segments.count - 1) * 2) * (weight / totalWeight))
                    
                    Capsule()
                        .fill(index == 3 ? model.extractedColor : Color.gray.opacity(0.3))
                        .frame(width: width)
                }
            }
        }
    }
    
    private func calculateSegments() -> [Double] {
        switch model.segmentationStrategy {
        case .chapterDurations:
            // Mock data for "Kill It With Fire"
            return [15, 22, 18, 30, 25, 45, 10, 20]
        case .fixed15Min:
            return Array(repeating: 15, count: 12)
        case .fixedCount:
            return Array(repeating: 1, count: Int(model.globalBarSegmentCount))
        }
    }
    
    @ViewBuilder
    private var transportPill: some View {
        HStack {
            Spacer()
            
            if model.transportInternalLayout == .arched {
                // Arched layout
                VStack {
                    Spacer().frame(height: 20)
                    transportButton(systemImage: "gobackward.30", scale: model.secondaryButtonGlyphSize)
                }
                Spacer()
                transportButton(systemImage: "play.fill", scale: model.primaryButtonGlyphSize)
                Spacer()
                VStack {
                    Spacer().frame(height: 20)
                    transportButton(systemImage: "goforward.30", scale: model.secondaryButtonGlyphSize)
                }
            } else if model.transportInternalLayout == .staggered {
                transportButton(systemImage: "gobackward.30", scale: model.secondaryButtonGlyphSize)
                Spacer()
                transportButton(systemImage: "play.fill", scale: model.primaryButtonGlyphSize)
                Spacer()
                transportButton(systemImage: "goforward.30", scale: model.secondaryButtonGlyphSize)
            } else {
                // Linear
                HStack(spacing: 30) {
                    transportButton(systemImage: "gobackward.30", scale: model.secondaryButtonGlyphSize)
                    transportButton(systemImage: "play.fill", scale: model.primaryButtonGlyphSize)
                    transportButton(systemImage: "goforward.30", scale: model.secondaryButtonGlyphSize)
                }
            }
            
            Spacer()
        }
        .padding()
        .background(model.materialType.material)
        .clipShape(.rect(cornerRadius: 32))
    }
    
    @ViewBuilder
    private var bottomToolbarPill: some View {
        HStack {
            Button("Speed", systemImage: "speedometer") {}
            Spacer()
            Button("Sleep", systemImage: "moon.zzz") {}
            Spacer()
            Button("Bookmark", systemImage: "bookmark") {}
        }
        .labelStyle(.iconOnly)
        .font(.title3)
        .foregroundStyle(.primary)
        .padding()
        .background(model.materialType.material)
        .clipShape(.capsule)
    }
    
    private func transportButton(systemImage: String, scale: Double) -> some View {
        Button(action: {}) {
            Image(systemName: systemImage)
                .font(.system(size: 24 * scale, weight: .bold))
                .foregroundStyle(.primary)
                .padding(16)
                .background(Color.gray.opacity(model.buttonTargetPaddingOpacity))
                .clipShape(.circle)
        }
    }
    
    // MARK: - Control Panel
    
    @ViewBuilder
    private var controlPanel: some View {
        VStack(alignment: .leading, spacing: 24) {
            GroupBox("Top Navigation") {
                VStack(alignment: .leading) {
                    Text("Button Vertical Safety Offset: \(model.buttonVerticalSafetyOffset, format: .number.precision(.fractionLength(0)))")
                    Slider(value: $model.buttonVerticalSafetyOffset, in: 0...40)
                    
                    Text("Scrim Gradient Opacity: \(model.scrimGradientOpacity, format: .number.precision(.fractionLength(2)))")
                    Slider(value: $model.scrimGradientOpacity, in: 0...1)
                }
            }
            
            GroupBox("Image & Overlays") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Cover Sizing Strategy")
                    Picker("Cover Sizing Strategy", selection: $model.coverSizingStrategy) {
                        ForEach(AudiobookArchitectModel.CoverSizingStrategy.allCases, id: \.self) { strategy in
                            Text(strategy.rawValue).tag(strategy)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    Text("Dynamic Color Logic")
                    Picker("Dynamic Color Logic", selection: $model.dynamicColorLogic) {
                        ForEach(AudiobookArchitectModel.DynamicColorLogic.allCases, id: \.self) { logic in
                            Text(logic.rawValue).tag(logic)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    Text("Lower Background Blend")
                    Picker("Lower Background Blend", selection: $model.lowerBackgroundBlend) {
                        ForEach(AudiobookArchitectModel.LowerBackgroundBlend.allCases, id: \.self) { blend in
                            Text(blend.rawValue).tag(blend)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            
            GroupBox("Progress Bars") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Segmentation Strategy")
                    Picker("Segmentation Strategy", selection: $model.segmentationStrategy) {
                        ForEach(AudiobookArchitectModel.SegmentationStrategy.allCases, id: \.self) { strategy in
                            Text(strategy.rawValue).tag(strategy)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    if model.segmentationStrategy == .fixedCount {
                        Text("Global Bar Segment Count: \(model.globalBarSegmentCount, format: .number.precision(.fractionLength(0)))")
                        Slider(value: $model.globalBarSegmentCount, in: 1...20, step: 1)
                    }
                }
            }
            
            GroupBox("Control Deck (Stacked Pills)") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Transport Internal Layout")
                    Picker("Transport Internal Layout", selection: $model.transportInternalLayout) {
                        ForEach(AudiobookArchitectModel.TransportInternalLayout.allCases, id: \.self) { layout in
                            Text(layout.rawValue).tag(layout)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    Text("Primary Button (Play/Skip) Glyph Size: \(model.primaryButtonGlyphSize, format: .number.precision(.fractionLength(2)))")
                    Slider(value: $model.primaryButtonGlyphSize, in: 0.8...1.5)
                    
                    Text("Secondary Button (30s Skip) Glyph Size: \(model.secondaryButtonGlyphSize, format: .number.precision(.fractionLength(2)))")
                    Slider(value: $model.secondaryButtonGlyphSize, in: 0.6...1.2)
                    
                    Text("Button Target Padding Opacity: \(model.buttonTargetPaddingOpacity, format: .number.precision(.fractionLength(2)))")
                    Slider(value: $model.buttonTargetPaddingOpacity, in: 0...1)
                    
                    Divider()
                    
                    Text("Material Type")
                    Picker("Material Type", selection: $model.materialType) {
                        ForEach(AudiobookArchitectModel.MaterialChoice.allCases, id: \.self) { material in
                            Text(material.rawValue).tag(material)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    Text("Vertical Pillar Spacing: \(model.verticalPillarSpacing, format: .number.precision(.fractionLength(0)))")
                    Slider(value: $model.verticalPillarSpacing, in: 0...40)
                }
            }
        }
    }
}

#Preview {
    AudiobookPlayerUIArchitect()
}
