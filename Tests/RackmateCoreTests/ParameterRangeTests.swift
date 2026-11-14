import Testing
@testable import RackmateCore

@Suite("ParameterRange")
struct ParameterRangeTests {
    @Test func linearRangeMapsBothWays() {
        let range = ParameterRange(minimum: 0, maximum: 10, scale: .linear, isStepped: false)
        #expect(range.value(atFraction: 0.25) == 2.5 && range.fraction(of: 2.5) == 0.25)
    }

    @Test func logarithmicCutoffIsHalfWayAtTheGeometricMean() {
        let range = ParameterRange(minimum: 20, maximum: 20_000, scale: .logarithmic, isStepped: false)
        #expect(abs(range.value(atFraction: 0.5) - 632.46) < 0.1)
        #expect(abs(range.fraction(of: 632.46) - 0.5) < 0.0001)
    }

    @Test func logarithmicWithANonPositiveMinimumIsLinear() {
        let range = ParameterRange(minimum: 0, maximum: 10, scale: .logarithmic, isStepped: false)
        #expect(range.value(atFraction: 0.25) == 2.5)
    }

    @Test func aSteppedParameterTakesTheNearestStep() {
        let range = ParameterRange(minimum: 0, maximum: 2, scale: .linear, isStepped: true)
        #expect(range.value(atFraction: 0.3) == 1 && range.value(atFraction: 0.2) == 0)
    }

    @Test func fractionsAndValuesAreClamped() {
        let range = ParameterRange(minimum: 0, maximum: 10, scale: .linear, isStepped: false)
        #expect(range.value(atFraction: 1.5) == 10 && range.value(atFraction: -0.5) == 0)
        #expect(range.fraction(of: 20) == 1 && range.fraction(of: -5) == 0)
    }

    @Test func everyScaleRoundTripsAndKeepsItsEnds() {
        let scales: [ParameterScale] = [.linear, .logarithmic, .exponential, .squareRoot, .squared, .cubeRoot, .cubed]
        for scale in scales {
            let range = ParameterRange(minimum: 20, maximum: 20_000, scale: scale, isStepped: false)
            #expect(range.value(atFraction: 0) == 20 && range.value(atFraction: 1) == 20_000)
            for fraction in [0.0, 0.1, 0.5, 0.9, 1.0] {
                let back = range.fraction(of: range.value(atFraction: fraction))
                #expect(abs(back - fraction) < 0.0001, "\(scale) at \(fraction): \(back)")
            }
        }
    }

    @Test func aRangeWithEqualEndsHasFractionZero() {
        let range = ParameterRange(minimum: 3, maximum: 3, scale: .linear, isStepped: false)
        #expect(range.fraction(of: 3) == 0 && range.value(atFraction: 0.7) == 3)
    }

    @Test func knobValueFollowsTheRangeAndItsDirection() {
        var mapping = ControlMapping(knob: .fixture(), parameter: 0, parameterName: "Mix", from: 0.6, to: 0.1)
        #expect(mapping.fraction(forKnob: 0) == 0.6 && mapping.fraction(forKnob: 127) == 0.1)
        mapping.from = 0.3; mapping.to = 0.7
        #expect(abs(mapping.fraction(forKnob: 64) - 0.5016) < 0.001)
    }
}
