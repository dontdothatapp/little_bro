import Accelerate
import Foundation

/// A metronome that can be nudged towards measured beats without ever jumping:
/// tempo glides and phase errors are absorbed by briefly speeding up or slowing down.
public struct BeatClock: Sendable {
    public private(set) var bpm: Double
    /// Beats elapsed; continuous. The fractional part is the phase within the current beat.
    public private(set) var position: Double = 0
    private var targetBpm: Double
    private var phaseError: Double = 0

    public init(bpm: Double = 112) {
        self.bpm = bpm
        targetBpm = bpm
    }

    public var phase: Double { position - floor(position) }

    public mutating func advance(_ dt: Double) {
        guard dt > 0 else { return }
        bpm += (targetBpm - bpm) * min(1, dt * 2.5)
        let base = bpm / 60
        // Absorb at most ±30 % tempo while correcting phase, so it never looks like a skip.
        let correction = clamp(phaseError * 3, -0.3, 0.3)
        let rate = base * (1 + correction)
        position += rate * dt
        phaseError -= (rate - base) * dt
    }

    /// Feed a measurement: the tempo and the phase (0…1) the music is at right now.
    public mutating func sync(bpm measured: Double, phase measuredPhase: Double) {
        guard measured.isFinite, measured > 40, measured < 220 else { return }
        // Keep whichever octave is closest to what we're already doing (avoids half/double flips).
        var b = measured
        while b > bpm * 1.45 { b /= 2 }
        while b < bpm / 1.45 { b *= 2 }
        targetBpm = b
        var err = measuredPhase - phase
        err -= (err + 0.5).rounded(.down) // wrap to [-0.5, 0.5)
        phaseError = err
    }
}

/// Estimates tempo and beat phase from audio: spectral-flux onsets, autocorrelation for
/// the tempo (with a gentle preference for 90–140 BPM), comb matching for the phase.
public final class BeatDetector {
    public struct Estimate: Equatable, Sendable {
        public var bpm: Double
        /// Phase (0…1) at the end of the audio analysed so far.
        public var phase: Double
        /// 0…1, how periodic the onsets are.
        public var confidence: Double
    }

    public let sampleRate: Double
    private let fftSize = 1024
    private let hop = 512
    private let log2n: vDSP_Length = 10
    private let setup: FFTSetup
    private var window: [Float]
    private var fifo: [Float] = []
    private var prevLogMag: [Float]
    private var odf: [Float] = []        // onset detection function (full band), one value per hop
    private var lowOdf: [Float] = []     // the same for the bass band (kicks mark the beat)
    private let maxSeconds = 8.0

    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
        setup = vDSP_create_fftsetup(10, FFTRadix(kFFTRadix2))!
        window = [Float](repeating: 0, count: 1024)
        vDSP_hann_window(&window, vDSP_Length(1024), Int32(vDSP_HANN_NORM))
        prevLogMag = [Float](repeating: 0, count: 512)
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    public var frameRate: Double { sampleRate / Double(hop) }
    public var secondsAnalysed: Double { Double(odf.count) / frameRate }

    public func reset() {
        fifo.removeAll()
        odf.removeAll()
        lowOdf.removeAll()
        prevLogMag = [Float](repeating: 0, count: fftSize / 2)
    }

    /// Feed mono samples.
    public func process(_ samples: UnsafeBufferPointer<Float>) {
        fifo.append(contentsOf: samples)
        while fifo.count >= fftSize {
            analyseFrame(Array(fifo[0..<fftSize]))
            fifo.removeFirst(hop)
        }
        let cap = Int(maxSeconds * frameRate)
        if odf.count > cap {
            odf.removeFirst(odf.count - cap)
            lowOdf.removeFirst(lowOdf.count - cap)
        }
    }

    public func process(_ samples: [Float]) {
        samples.withUnsafeBufferPointer { process($0) }
    }

    private func analyseFrame(_ frame: [Float]) {
        let n = fftSize
        var windowed = [Float](repeating: 0, count: n)
        vDSP_vmul(frame, 1, window, 1, &windowed, 1, vDSP_Length(n))
        var real = [Float](repeating: 0, count: n / 2)
        var imag = [Float](repeating: 0, count: n / 2)
        var mags = [Float](repeating: 0, count: n / 2)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBufferPointer { wp in
                    wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { cp in
                        vDSP_ctoz(cp, 2, &split, 1, vDSP_Length(n / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&split, 1, &mags, 1, vDSP_Length(n / 2))
            }
        }
        // Log-compressed magnitude, positive differences summed = spectral flux.
        var flux: Float = 0
        var low: Float = 0
        let lowBins = max(2, Int(220 / (sampleRate / Double(n))))
        for i in 1..<(n / 2) {
            let lm = log1pf(mags[i] * 10)
            let d = lm - prevLogMag[i]
            if d > 0 {
                flux += d
                if i <= lowBins { low += d }
            }
            prevLogMag[i] = lm
        }
        odf.append(flux)
        lowOdf.append(low)
    }

    public func estimate() -> Estimate? {
        let fr = frameRate
        let n = odf.count
        guard n >= Int(3.0 * fr) else { return nil }
        // Detrend: subtract a moving average and half-wave rectify.
        let span = max(1, Int(0.25 * fr))
        var env = [Double](repeating: 0, count: n)
        var running = 0.0
        var cumulative = [Double](repeating: 0, count: n + 1)
        for i in 0..<n {
            running += Double(odf[i])
            cumulative[i + 1] = running
        }
        for i in 0..<n {
            let a = max(0, i - span), b = min(n, i + span + 1)
            let mean = (cumulative[b] - cumulative[a]) / Double(b - a)
            env[i] = max(0, Double(odf[i]) - mean)
        }
        let energy = env.reduce(0) { $0 + $1 * $1 }
        guard energy > 1e-9 else { return nil }
        // Bass-band onsets, detrended the same way, for placing the beat.
        var lowEnv = [Double](repeating: 0, count: n)
        var lowCum = [Double](repeating: 0, count: n + 1)
        for i in 0..<n { lowCum[i + 1] = lowCum[i] + Double(lowOdf[i]) }
        for i in 0..<n {
            let a = max(0, i - span), b = min(n, i + span + 1)
            lowEnv[i] = max(0, Double(lowOdf[i]) - (lowCum[b] - lowCum[a]) / Double(b - a))
        }
        let fullMean = env.reduce(0, +) / Double(n), lowMean = lowEnv.reduce(0, +) / Double(n)
        // Mostly bass, a little full band (for music without a clear kick).
        let phaseEnv = (0..<n).map { i in
            (lowMean > 1e-9 ? lowEnv[i] / lowMean : 0) + 0.35 * (fullMean > 1e-9 ? env[i] / fullMean : 0)
        }

        // Autocorrelation over plausible beat periods (55–200 BPM), weighted by a tempo prior.
        let minLag = Int(floor(60.0 / 200 * fr)), maxLag = Int(ceil(60.0 / 55 * fr))
        guard maxLag < n - 1 else { return nil }
        let acfMax = min(2 * maxLag + 1, n - 1)
        var acf = [Double](repeating: 0, count: acfMax + 1)
        for lag in max(1, minLag - 1)...acfMax {
            var sum = 0.0
            for i in lag..<n { sum += env[i] * env[i - lag] }
            acf[lag] = sum / Double(n - lag)
        }
        let zero = energy / Double(n)
        var best = -1.0, bestLag = minLag
        for lag in minLag...maxLag {
            // Reward periods whose double also correlates (beats, not just eighth notes).
            let double = 2 * lag <= acfMax ? acf[2 * lag] : 0
            let bpm = 60 * fr / Double(lag)
            let prior = exp(-0.5 * pow(log2(bpm / 118) / 0.75, 2))
            let score = (acf[lag] + 0.5 * double) * prior
            if score > best { best = score; bestLag = lag }
        }
        // Parabolic refinement of the peak.
        var period = Double(bestLag)
        if bestLag > 1 && bestLag + 1 < acf.count {
            let a = acf[bestLag - 1], b = acf[bestLag], c = acf[bestLag + 1]
            let denom = a - 2 * b + c
            if abs(denom) > 1e-12 { period += clamp(0.5 * (a - c) / denom, -0.5, 0.5) }
        }
        let bpm = 60 * fr / period
        let confidence = clamp(acf[bestLag] / zero, 0, 1)

        // Phase: which offset makes a comb of beats line up with the onsets best?
        let steps = max(1, Int(period.rounded()))
        var bestOffset = 0, bestScore = -1.0
        for off in 0..<steps {
            var sum = 0.0
            var k = 0.0
            while true {
                let idx = Double(n - 1 - off) - k * period
                if idx < 0 { break }
                let i = Int(idx.rounded())
                sum += phaseEnv[i] * (1 - 0.06 * k) // recent beats count a bit more
                k += 1
                if k > 24 { break }
            }
            if sum > bestScore { bestScore = sum; bestOffset = off }
        }
        // The last beat was `bestOffset` frames ago (plus half a hop of analysis latency).
        let framesSinceBeat = Double(bestOffset) + Double(fftSize) / Double(hop) / 2
        let phase = (framesSinceBeat / period).truncatingRemainder(dividingBy: 1)
        return Estimate(bpm: bpm, phase: phase, confidence: confidence)
    }
}
