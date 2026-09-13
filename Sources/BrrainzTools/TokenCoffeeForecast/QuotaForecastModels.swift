import Foundation

public struct QuotaCycleRunForecast: Equatable, Sendable {
    public let projectedWeeklyUsedPercentAtReset: Double
    public let lowProjectedWeeklyUsedPercentAtReset: Double
    public let highProjectedWeeklyUsedPercentAtReset: Double
    public let ghostRuns: [QuotaForecastRun]
    public let averageRuns: [QuotaForecastRun]
    public let lineSegments: [QuotaForecastLineSegment]
    public let lowLineSegments: [QuotaForecastLineSegment]
    public let highLineSegments: [QuotaForecastLineSegment]
    public let earliestLineSegments: [QuotaForecastLineSegment]
    public let latestLineSegments: [QuotaForecastLineSegment]
    public let corridorPoints: [QuotaForecastCorridorPoint]
    public let observedIntensityRuns: [QuotaForecastRun]

    public init(
        projectedWeeklyUsedPercentAtReset: Double,
        lowProjectedWeeklyUsedPercentAtReset: Double? = nil,
        highProjectedWeeklyUsedPercentAtReset: Double? = nil,
        ghostRuns: [QuotaForecastRun],
        averageRuns: [QuotaForecastRun] = [],
        lineSegments: [QuotaForecastLineSegment] = [],
        lowLineSegments: [QuotaForecastLineSegment] = [],
        highLineSegments: [QuotaForecastLineSegment] = [],
        earliestLineSegments: [QuotaForecastLineSegment] = [],
        latestLineSegments: [QuotaForecastLineSegment] = [],
        corridorPoints: [QuotaForecastCorridorPoint],
        observedIntensityRuns: [QuotaForecastRun] = []
    ) {
        self.projectedWeeklyUsedPercentAtReset = projectedWeeklyUsedPercentAtReset
        self.lowProjectedWeeklyUsedPercentAtReset = lowProjectedWeeklyUsedPercentAtReset ?? projectedWeeklyUsedPercentAtReset
        self.highProjectedWeeklyUsedPercentAtReset = highProjectedWeeklyUsedPercentAtReset ?? projectedWeeklyUsedPercentAtReset
        self.ghostRuns = ghostRuns
        self.averageRuns = averageRuns
        self.lineSegments = lineSegments
        self.lowLineSegments = lowLineSegments.isEmpty ? lineSegments : lowLineSegments
        self.highLineSegments = highLineSegments.isEmpty ? lineSegments : highLineSegments
        self.earliestLineSegments = earliestLineSegments
        self.latestLineSegments = latestLineSegments
        self.corridorPoints = corridorPoints
        self.observedIntensityRuns = observedIntensityRuns
    }
}

public enum QuotaForecastLineSegmentKind: String, Equatable, Sendable {
    case projectedIdle
    case projectedActivity
    case currentProjectedActivity
}

public struct QuotaForecastLineSegment: Equatable, Sendable {
    public let startDate: Date
    public let endDate: Date
    public let startUsedPercent: Double
    public let endUsedPercent: Double
    public let kind: QuotaForecastLineSegmentKind

    public init(
        startDate: Date,
        endDate: Date,
        startUsedPercent: Double,
        endUsedPercent: Double,
        kind: QuotaForecastLineSegmentKind
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.startUsedPercent = startUsedPercent
        self.endUsedPercent = endUsedPercent
        self.kind = kind
    }
}

public struct QuotaForecastRun: Equatable, Sendable {
    public let startDate: Date
    public let endDate: Date
    public let startUsedPercent: Double
    public let endUsedPercent: Double

    public init(
        startDate: Date,
        endDate: Date,
        startUsedPercent: Double,
        endUsedPercent: Double
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.startUsedPercent = startUsedPercent
        self.endUsedPercent = endUsedPercent
    }
}

public struct QuotaForecastCorridorPoint: Equatable, Sendable {
    public let date: Date
    public let averageUsedPercent: Double
    public let lowerUsedPercent: Double
    public let upperUsedPercent: Double

    public init(
        date: Date,
        averageUsedPercent: Double,
        lowerUsedPercent: Double,
        upperUsedPercent: Double
    ) {
        self.date = date
        self.averageUsedPercent = averageUsedPercent
        self.lowerUsedPercent = lowerUsedPercent
        self.upperUsedPercent = upperUsedPercent
    }
}

